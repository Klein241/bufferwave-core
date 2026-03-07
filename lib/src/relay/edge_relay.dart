import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';

/// ════════════════════════════════════════════════════════════════
/// EdgeRelay — Relay Client for Edge Servers
///
/// Architecture inspirée des relais distribués (DERP-like) :
///   - Connexion WebSocket à un relay edge (Cloudflare Worker)
///   - Pairing bidirectionnel entre 2 peers
///   - Support binaire (paquets IP) + JSON (signaling)
///   - Reconnexion automatique avec backoff exponentiel
///   - Keepalive adaptatif (normal: 15s, éco: 45s)
///   - Multi-endpoint fallback
///
/// Réutilisable dans tout projet nécessitant un relay réseau.
///
/// Usage :
///   final relay = EdgeRelay(
///     endpoints: ['wss://worker.example.com/tunnel'],
///     localId: 'my-node-id',
///     peerId: 'target-node-id',
///   );
///   relay.onData = (bytes) => handleData(bytes);
///   relay.onPaired = () => print('Paired!');
///   await relay.connect();
///   relay.sendBinary(myPacket);
///   await relay.disconnect();
/// ════════════════════════════════════════════════════════════════
class EdgeRelay {
  /// Endpoints de relay ordonnés par priorité.
  /// Si le premier échoue, on passe au suivant.
  final List<String> endpoints;

  /// Identifiant local du nœud.
  final String localId;

  /// Identifiant du peer cible (pour le pairing).
  final String peerId;

  /// Paramètres additionnels dans l'URL (ex: mode=tailscale).
  final Map<String, String> queryParams;

  // ─── State ───
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _keepaliveTimer;
  Timer? _reconnectTimer;
  int _endpointIndex = 0;
  int _reconnectAttempts = 0;
  bool _running = false;
  bool _paired = false;
  DateTime _lastActivity = DateTime.now();

  // ─── Config ───
  int _keepaliveIntervalSec = 15;
  static const int _maxReconnectAttempts = 20;
  static const int _reconnectBaseMs = 2000;
  static const int _reconnectMaxMs = 120000;

  // ─── Callbacks ───
  /// Appelé quand des données binaires sont reçues du peer.
  void Function(Uint8List data)? onData;

  /// Appelé quand un message JSON est reçu du relay.
  void Function(Map<String, dynamic> msg)? onMessage;

  /// Appelé quand le relay a pairé ce nœud avec le peer.
  void Function()? onPaired;

  /// Appelé à chaque connexion établie (pas encore pairé).
  void Function()? onConnected;

  /// Appelé à chaque déconnexion.
  void Function()? onDisconnected;

  /// Appelé quand le relay change d'endpoint (fallback).
  void Function(int index, String endpoint)? onEndpointChanged;

  /// Appelé en cas d'erreur.
  void Function(String error)? onError;

  // ─── Getters ───
  bool get isConnected => _channel != null && _running;
  bool get isPaired => _paired;
  int get currentEndpointIndex => _endpointIndex;
  String get currentEndpoint =>
      _endpointIndex < endpoints.length ? endpoints[_endpointIndex] : '';
  Duration get timeSinceActivity =>
      DateTime.now().difference(_lastActivity);

  EdgeRelay({
    required this.endpoints,
    required this.localId,
    required this.peerId,
    this.queryParams = const {},
  });

  // ═══════════════════════════════════════════
  // CONNECT
  // ═══════════════════════════════════════════

  /// Connecte au relay edge. Essaie les endpoints dans l'ordre.
  Future<bool> connect() async {
    _running = true;
    _endpointIndex = 0;
    _reconnectAttempts = 0;
    return _connectToEndpoint();
  }

  Future<bool> _connectToEndpoint() async {
    if (!_running) return false;
    if (_endpointIndex >= endpoints.length) {
      // Tous les endpoints épuisés → retry du premier
      _endpointIndex = 0;
      _reconnectAttempts++;
      if (_reconnectAttempts > _maxReconnectAttempts) {
        onError?.call('Relay: max reconnect attempts reached');
        return false;
      }
      final delayMs = (_reconnectBaseMs * _reconnectAttempts)
          .clamp(_reconnectBaseMs, _reconnectMaxMs);
      await Future.delayed(Duration(milliseconds: delayMs));
      if (!_running) return false;
    }

    final base = endpoints[_endpointIndex];
    final params = {
      'user': localId,
      'peer': peerId,
      ...queryParams,
    };
    final queryStr = params.entries
        .map((e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
    final url = '$base?$queryStr';

    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      await _channel!.ready;

      _paired = false;
      _lastActivity = DateTime.now();
      _reconnectAttempts = 0;
      onEndpointChanged?.call(_endpointIndex, base);
      onConnected?.call();

      _subscription = _channel!.stream.listen(
        _handleMessage,
        onDone: _handleDisconnect,
        onError: (e) {
          onError?.call('Relay WS error: $e');
          _handleDisconnect();
        },
      );

      _startKeepalive();
      return true;
    } catch (e) {
      onError?.call('Relay connect fail [$_endpointIndex]: $e');
      _endpointIndex++;
      return _connectToEndpoint();
    }
  }

  // ═══════════════════════════════════════════
  // SEND
  // ═══════════════════════════════════════════

  /// Envoie des données binaires au peer via le relay.
  bool sendBinary(Uint8List data) {
    if (_channel == null || !_running) return false;
    try {
      _channel!.sink.add(data);
      _lastActivity = DateTime.now();
      return true;
    } catch (e) {
      onError?.call('Relay send error: $e');
      return false;
    }
  }

  /// Envoie un message JSON au relay.
  void sendJson(Map<String, dynamic> msg) {
    if (_channel == null || !_running) return;
    try {
      _channel!.sink.add(json.encode(msg));
      _lastActivity = DateTime.now();
    } catch (e) {
      onError?.call('Relay sendJson error: $e');
    }
  }

  // ═══════════════════════════════════════════
  // RECEIVE
  // ═══════════════════════════════════════════

  void _handleMessage(dynamic raw) {
    _lastActivity = DateTime.now();

    // Données binaires (paquets IP du peer)
    if (raw is List<int>) {
      onData?.call(Uint8List.fromList(raw));
      return;
    }

    // Message texte (JSON signaling du relay)
    if (raw is String) {
      try {
        final msg = json.decode(raw) as Map<String, dynamic>;
        final action = msg['action'] as String? ?? '';

        switch (action) {
          case 'relay_paired':
            _paired = true;
            onPaired?.call();
            break;
          case 'relay_waiting':
            // En attente du peer — continuer keepalive
            break;
          case 'pong':
            // Keepalive ack
            break;
          default:
            onMessage?.call(msg);
        }
      } catch (_) {
        // Pas du JSON — traiter comme binaire
        onData?.call(Uint8List.fromList(raw.codeUnits));
      }
    }
  }

  // ═══════════════════════════════════════════
  // KEEPALIVE — Adaptatif (normal/éco)
  // ═══════════════════════════════════════════

  void _startKeepalive() {
    _keepaliveTimer?.cancel();
    _keepaliveTimer = Timer.periodic(
      Duration(seconds: _keepaliveIntervalSec),
      (_) {
        if (!_running || _channel == null) return;

        // Envoyer ping léger
        sendJson({'a': 'ping', 'n': localId});

        // Vérifier silence prolongé (path healing)
        final silenceThreshold = _keepaliveIntervalSec * 6;
        if (timeSinceActivity.inSeconds > silenceThreshold) {
          onError?.call('Relay: silence ${timeSinceActivity.inSeconds}s > ${silenceThreshold}s → heal');
          _healPath();
        }
      },
    );
  }

  /// Bascule en mode éco (keepalive 45s au lieu de 15s).
  /// Utile quand le réseau est throttlé (< 10 KB/s).
  void setEcoMode(bool enabled) {
    _keepaliveIntervalSec = enabled ? 45 : 15;
    if (_running) _startKeepalive();
  }

  // ═══════════════════════════════════════════
  // PATH HEALING — Reconstruction du chemin
  // ═══════════════════════════════════════════

  void _healPath() {
    if (!_running) return;
    _paired = false;
    _channel?.sink.close();
    _channel = null;
    _subscription?.cancel();
    _endpointIndex = 0;
    _connectToEndpoint();
  }

  void _handleDisconnect() {
    if (!_running) return;
    _paired = false;
    _keepaliveTimer?.cancel();
    _subscription?.cancel();
    _channel = null;
    onDisconnected?.call();

    // Reconnexion automatique
    final delayMs = (_reconnectBaseMs * (_reconnectAttempts + 1))
        .clamp(_reconnectBaseMs, _reconnectMaxMs);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: delayMs), () {
      _reconnectTimer = null;
      if (_running) {
        _reconnectAttempts++;
        _connectToEndpoint();
      }
    });
  }

  // ═══════════════════════════════════════════
  // DISCONNECT
  // ═══════════════════════════════════════════

  /// Déconnexion propre du relay.
  Future<void> disconnect() async {
    _running = false;
    _paired = false;
    _keepaliveTimer?.cancel();
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    onDisconnected?.call();
  }

  /// Libère toutes les ressources.
  void dispose() {
    disconnect();
    onData = null;
    onMessage = null;
    onPaired = null;
    onConnected = null;
    onDisconnected = null;
    onEndpointChanged = null;
    onError = null;
  }
}
