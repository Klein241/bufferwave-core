import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';

/// ════════════════════════════════════════════════════════════════
/// EdgeRelay — Distributed Relay Client Engine
///
/// Architecture :
///   - WebSocket relay vers un edge server (Cloudflare Worker)
///   - Pairing bidirectionnel (localId ↔ peerId)
///   - Support binaire (paquets IP) + JSON (signaling)
///   - Reconnexion auto avec backoff exponentiel + jitter
///   - Keepalive adaptatif (normal: 15s, éco: 45s)
///   - Multi-endpoint fallback avec shuffle aléatoire
///   - Token bucket rate limiting (limite BPS)
///   - Graceful restart (serveur signale un redémarrage)
///   - Health monitoring (connexion saine / dégradée)
///   - Bandwidth tracking (bytes in/out/s)
///   - Work connection pool (pré-allocation)
///
/// Patterns combinés de 3 architectures :
///   - Relay distribué (DERP-like) : pairing, send(dst, pkt)
///   - Reverse tunnel (FRP-like) : work connections, bandwidth limit
///   - Self-hosted coordination : multi-region, shuffle, merge maps
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
  final List<String> endpoints;

  /// Identifiant local du nœud.
  final String localId;

  /// Identifiant du peer cible.
  final String peerId;

  /// Paramètres additionnels dans l'URL.
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
  final _rng = Random();

  // ─── Config ───
  int _keepaliveIntervalSec = 15;
  static const int _maxReconnectAttempts = 30;
  static const int _reconnectBaseMs = 2000;
  static const int _reconnectMaxMs = 120000;
  static const int _readTimeoutSec = 120; // Timeout lecture (DERP=120s)

  // ─── Rate Limiting (token bucket, inspiré DERP ServerInfo) ───
  int _rateLimitBytesPerSec = 0; // 0 = illimité
  int _rateLimitBurst = 0;
  int _tokenBucket = 0;
  DateTime _lastTokenRefill = DateTime.now();

  /// Max taille d'un paquet (1MB, DERP=64KB mais on est plus permissif)
  static const int maxPacketSize = 1 << 20;

  // ─── Bandwidth tracking ───
  int _totalBytesIn = 0;
  int _totalBytesOut = 0;
  int _bytesInWindow = 0;
  int _bytesOutWindow = 0;
  int _currentBpsIn = 0;
  int _currentBpsOut = 0;
  Timer? _bwTimer;

  // ─── Health monitoring ───
  RelayHealth _health = RelayHealth.unknown;
  int _pingsSent = 0;
  int _pongsReceived = 0;
  String? _healthProblem;

  // ─── Callbacks ───
  void Function(Uint8List data)? onData;
  void Function(Map<String, dynamic> msg)? onMessage;
  void Function()? onPaired;
  void Function()? onConnected;
  void Function()? onDisconnected;
  void Function(int index, String endpoint)? onEndpointChanged;
  void Function(String error)? onError;
  void Function(RelayHealth health, String? problem)? onHealthChanged;

  // ─── Getters ───
  bool get isConnected => _channel != null && _running;
  bool get isPaired => _paired;
  int get currentEndpointIndex => _endpointIndex;
  String get currentEndpoint =>
      _endpointIndex < endpoints.length ? endpoints[_endpointIndex] : '';
  Duration get timeSinceActivity =>
      DateTime.now().difference(_lastActivity);
  int get totalBytesIn => _totalBytesIn;
  int get totalBytesOut => _totalBytesOut;
  int get currentBpsIn => _currentBpsIn;
  int get currentBpsOut => _currentBpsOut;
  RelayHealth get health => _health;
  String? get healthProblem => _healthProblem;

  EdgeRelay({
    required this.endpoints,
    required this.localId,
    required this.peerId,
    this.queryParams = const {},
  });

  // ═══════════════════════════════════════════
  // CONNECT
  // ═══════════════════════════════════════════

  Future<bool> connect() async {
    _running = true;
    _endpointIndex = 0;
    _reconnectAttempts = 0;
    _totalBytesIn = 0;
    _totalBytesOut = 0;
    _startBandwidthTracking();
    return _connectToEndpoint();
  }

  Future<bool> _connectToEndpoint() async {
    if (!_running) return false;
    if (_endpointIndex >= endpoints.length) {
      _endpointIndex = 0;
      _reconnectAttempts++;
      if (_reconnectAttempts > _maxReconnectAttempts) {
        _setHealth(RelayHealth.dead, 'max reconnect attempts');
        onError?.call('Relay: max reconnect attempts reached');
        return false;
      }
      // Backoff exponentiel avec jitter (empêche thundering herd)
      final base = (_reconnectBaseMs * _reconnectAttempts)
          .clamp(_reconnectBaseMs, _reconnectMaxMs);
      final jitter = _rng.nextInt((base * 0.3).toInt().clamp(1, 5000));
      await Future.delayed(Duration(milliseconds: base + jitter));
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
      _pingsSent = 0;
      _pongsReceived = 0;
      _setHealth(RelayHealth.connecting, null);
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
  // SEND with rate limiting
  // ═══════════════════════════════════════════

  /// Envoie des données binaires au peer via le relay.
  /// Respecte la limite de débit si configurée.
  bool sendBinary(Uint8List data) {
    if (_channel == null || !_running) return false;
    if (data.length > maxPacketSize) {
      onError?.call('Relay: packet too large: ${data.length}');
      return false;
    }

    // Rate limiting check (token bucket)
    if (!_checkRateLimit(data.length)) return false;

    try {
      _channel!.sink.add(data);
      _totalBytesOut += data.length;
      _bytesOutWindow += data.length;
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
      final encoded = json.encode(msg);
      _channel!.sink.add(encoded);
      _totalBytesOut += encoded.length;
      _lastActivity = DateTime.now();
    } catch (e) {
      onError?.call('Relay sendJson error: $e');
    }
  }

  // ═══════════════════════════════════════════
  // RATE LIMITING (Token Bucket)
  // ═══════════════════════════════════════════

  /// Configure la limite de débit (bytes/sec).
  /// 0 = illimité.
  void setRateLimit({int bytesPerSec = 0, int burst = 0}) {
    _rateLimitBytesPerSec = bytesPerSec;
    _rateLimitBurst = burst > 0 ? burst : bytesPerSec * 2;
    _tokenBucket = _rateLimitBurst;
    _lastTokenRefill = DateTime.now();
  }

  bool _checkRateLimit(int packetLen) {
    if (_rateLimitBytesPerSec <= 0) return true;

    // Refill tokens
    final now = DateTime.now();
    final elapsed = now.difference(_lastTokenRefill).inMilliseconds / 1000.0;
    _tokenBucket = (_tokenBucket + (elapsed * _rateLimitBytesPerSec).toInt())
        .clamp(0, _rateLimitBurst);
    _lastTokenRefill = now;

    if (_tokenBucket >= packetLen) {
      _tokenBucket -= packetLen;
      return true;
    }

    // Drop packet (rate exceeded)
    return false;
  }

  // ═══════════════════════════════════════════
  // RECEIVE
  // ═══════════════════════════════════════════

  void _handleMessage(dynamic raw) {
    _lastActivity = DateTime.now();

    // Données binaires (paquets IP du peer)
    if (raw is List<int>) {
      final bytes = Uint8List.fromList(raw);
      _totalBytesIn += bytes.length;
      _bytesInWindow += bytes.length;
      onData?.call(bytes);
      return;
    }

    // Message texte (JSON signaling du relay)
    if (raw is String) {
      _totalBytesIn += raw.length;
      try {
        final msg = json.decode(raw) as Map<String, dynamic>;
        final action = msg['action'] as String? ?? '';

        switch (action) {
          case 'relay_paired':
            _paired = true;
            _setHealth(RelayHealth.healthy, null);
            onPaired?.call();
            break;
          case 'relay_waiting':
            _setHealth(RelayHealth.connecting, 'waiting for peer');
            break;
          case 'pong':
            _pongsReceived++;
            break;
          case 'server_restarting':
            // Graceful restart : serveur nous dit de se reconnecter
            final reconnectIn = msg['reconnect_in'] as int? ?? 2000;
            final tryFor = msg['try_for'] as int? ?? 10000;
            _handleServerRestart(reconnectIn, tryFor);
            break;
          case 'health':
            // Server health status
            final problem = msg['problem'] as String? ?? '';
            if (problem.isEmpty) {
              _setHealth(RelayHealth.healthy, null);
            } else {
              _setHealth(RelayHealth.degraded, problem);
            }
            break;
          case 'rate_limit':
            // Server sends rate limit info
            final bps = msg['bytes_per_sec'] as int? ?? 0;
            final burst = msg['burst'] as int? ?? 0;
            if (bps > 0) setRateLimit(bytesPerSec: bps, burst: burst);
            break;
          default:
            onMessage?.call(msg);
        }
      } catch (_) {
        onData?.call(Uint8List.fromList(raw.codeUnits));
      }
    }
  }

  // ═══════════════════════════════════════════
  // KEEPALIVE — Adaptatif
  // ═══════════════════════════════════════════

  void _startKeepalive() {
    _keepaliveTimer?.cancel();
    _keepaliveTimer = Timer.periodic(
      Duration(seconds: _keepaliveIntervalSec),
      (_) {
        if (!_running || _channel == null) return;

        // Ping
        _pingsSent++;
        sendJson({'a': 'ping', 'n': localId, 't': DateTime.now().millisecondsSinceEpoch});

        // Vérifier silence prolongé (path healing)
        final silenceThreshold = _readTimeoutSec;
        if (timeSinceActivity.inSeconds > silenceThreshold) {
          _setHealth(RelayHealth.dead, 'silence ${timeSinceActivity.inSeconds}s');
          _healPath();
        }

        // Health check : si trop de pings sans pongs → dégradé
        if (_pingsSent > 3 && _pongsReceived < _pingsSent ~/ 2) {
          _setHealth(RelayHealth.degraded, 'ping loss');
        }
      },
    );
  }

  void setEcoMode(bool enabled) {
    _keepaliveIntervalSec = enabled ? 45 : 15;
    if (_running) _startKeepalive();
  }

  // ═══════════════════════════════════════════
  // GRACEFUL SERVER RESTART (inspiré DERP)
  // ═══════════════════════════════════════════

  void _handleServerRestart(int reconnectInMs, int tryForMs) {
    _setHealth(RelayHealth.restarting, 'server restarting');

    // Smear out reconnects avec jitter aléatoire
    final jitter = _rng.nextInt(reconnectInMs.clamp(500, 5000));
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: reconnectInMs + jitter), () {
      if (_running) {
        _endpointIndex = 0;
        _reconnectAttempts = 0;
        _connectToEndpoint();
      }
    });
  }

  // ═══════════════════════════════════════════
  // PATH HEALING
  // ═══════════════════════════════════════════

  void _healPath() {
    if (!_running) return;
    _paired = false;
    _channel?.sink.close();
    _channel = null;
    _subscription?.cancel();

    // Shuffle endpoints pour ne pas tous taper le même
    if (endpoints.length > 1) {
      _endpointIndex = _rng.nextInt(endpoints.length);
    } else {
      _endpointIndex = 0;
    }

    _connectToEndpoint();
  }

  void _handleDisconnect() {
    if (!_running) return;
    _paired = false;
    _keepaliveTimer?.cancel();
    _subscription?.cancel();
    _channel = null;
    _setHealth(RelayHealth.disconnected, null);
    onDisconnected?.call();

    // Reconnexion avec backoff + jitter
    final base = (_reconnectBaseMs * (_reconnectAttempts + 1))
        .clamp(_reconnectBaseMs, _reconnectMaxMs);
    final jitter = _rng.nextInt((base * 0.2).toInt().clamp(1, 3000));
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: base + jitter), () {
      _reconnectTimer = null;
      if (_running) {
        _reconnectAttempts++;
        _connectToEndpoint();
      }
    });
  }

  // ═══════════════════════════════════════════
  // HEALTH MONITORING
  // ═══════════════════════════════════════════

  void _setHealth(RelayHealth h, String? problem) {
    if (_health != h || _healthProblem != problem) {
      _health = h;
      _healthProblem = problem;
      onHealthChanged?.call(h, problem);
    }
  }

  // ═══════════════════════════════════════════
  // BANDWIDTH TRACKING (mesure BPS glissant)
  // ═══════════════════════════════════════════

  void _startBandwidthTracking() {
    _bwTimer?.cancel();
    _bwTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _currentBpsIn = _bytesInWindow ~/ 5;
      _currentBpsOut = _bytesOutWindow ~/ 5;
      _bytesInWindow = 0;
      _bytesOutWindow = 0;
    });
  }

  // ═══════════════════════════════════════════
  // DISCONNECT
  // ═══════════════════════════════════════════

  Future<void> disconnect() async {
    _running = false;
    _paired = false;
    _keepaliveTimer?.cancel();
    _reconnectTimer?.cancel();
    _bwTimer?.cancel();
    _subscription?.cancel();
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _setHealth(RelayHealth.disconnected, null);
    onDisconnected?.call();
  }

  void dispose() {
    disconnect();
    onData = null;
    onMessage = null;
    onPaired = null;
    onConnected = null;
    onDisconnected = null;
    onEndpointChanged = null;
    onError = null;
    onHealthChanged = null;
  }
}

/// État de santé de la connexion relay.
enum RelayHealth {
  unknown,
  connecting,
  healthy,
  degraded,
  restarting,
  disconnected,
  dead,
}
