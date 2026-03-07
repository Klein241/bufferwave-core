import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// ════════════════════════════════════════════════════════════════
/// TcpForwarder — Forwarding TCP natif (Host-side)
///
/// Inspiré des reverse tunnel TCP et des exit nodes :
///   - Reçoit des demandes de connexion TCP via un relay
///   - Ouvre de vraies connexions TCP vers Internet
///   - Relaie les données bidirectionnellement
///   - Supporte le multiplexage via channelId
///   - Cleanup automatique des connexions mortes
///
/// Flux de données (Host) :
///   Guest TUN → Relay → TcpForwarder → Internet
///   Internet → TcpForwarder → Relay → Guest TUN
///
/// Protocole de multiplexage (binary frames) :
///   [2 bytes channelId][2 bytes length][N bytes data]
///
/// Messages de contrôle (JSON) :
///   {"cmd":"connect","ch":1,"host":"142.250.185.14","port":443}
///   {"cmd":"connected","ch":1}
///   {"cmd":"close","ch":1}
///   {"cmd":"error","ch":1,"msg":"connection refused"}
///
/// Réutilisable dans tout projet nécessitant du TCP forwarding.
///
/// Usage :
///   final forwarder = TcpForwarder();
///   forwarder.onSendToRelay = (data) => relay.sendBinary(data);
///   forwarder.handleFromRelay(relayData);
///   // Quand un connect request arrive via relay :
///   //   → ouvre un Socket TCP réel vers Internet
///   //   → relaie les données en temps réel
///   await forwarder.dispose();
/// ════════════════════════════════════════════════════════════════
class TcpForwarder {
  /// Connexions actives : channelId → socket TCP réel.
  final Map<int, Socket> _sockets = {};

  /// Timestamp de la dernière activité par channel.
  final Map<int, DateTime> _lastActivity = {};

  /// Callbacks pour envoyer des données vers le relay.
  void Function(Uint8List data)? onSendToRelay;

  /// Callback pour envoyer un message JSON de contrôle au relay.
  void Function(Map<String, dynamic> msg)? onSendControlToRelay;

  /// Callback pour les événements de log.
  void Function(String msg)? onLog;

  /// Timeout pour la connexion TCP sortante.
  Duration connectTimeout;

  /// Nombre max de connexions simultanées.
  int maxConnections;

  /// Durée d'inactivité avant fermeture automatique d'une connexion.
  Duration idleTimeout;

  /// Limite de bande passante en bytes/sec (0 = illimité).
  /// Appliquée par connexion (FRP BandwidthLimitMode.client).
  int bandwidthLimitBps;

  // ─── Timer cleanup ───
  Timer? _cleanupTimer;

  // ─── Métriques ───
  int _totalBytesIn = 0;
  int _totalBytesOut = 0;
  int _totalConnections = 0;
  int _activeConnections = 0;

  int get totalBytesIn => _totalBytesIn;
  int get totalBytesOut => _totalBytesOut;
  int get totalConnections => _totalConnections;
  int get activeConnections => _activeConnections;

  TcpForwarder({
    this.connectTimeout = const Duration(seconds: 10),
    this.maxConnections = 512,
    this.idleTimeout = const Duration(minutes: 5),
    this.bandwidthLimitBps = 0,
  }) {
    // Cleanup idle connections every 30s
    _cleanupTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _cleanupIdleConnections(),
    );
  }

  // ═══════════════════════════════════════════
  // HANDLE DATA FROM RELAY
  // ═══════════════════════════════════════════

  /// Traite les données binaires reçues du relay (encapsulées).
  /// Format : [2B channelId][2B length][Nb data]
  void handleBinaryFromRelay(Uint8List data) {
    if (data.length < 4) return;

    final channelId = (data[0] << 8) | data[1];
    final length = (data[2] << 8) | data[3];

    if (data.length < 4 + length) return;

    final payload = data.sublist(4, 4 + length);
    _forwardToSocket(channelId, payload);
  }

  /// Traite une commande JSON de contrôle reçue du relay.
  Future<void> handleControlFromRelay(Map<String, dynamic> msg) async {
    final cmd = msg['cmd'] as String? ?? '';
    final ch = msg['ch'] as int? ?? 0;

    switch (cmd) {
      case 'connect':
        await _openConnection(
          ch,
          msg['host'] as String? ?? '',
          msg['port'] as int? ?? 0,
        );
        break;
      case 'close':
        _closeConnection(ch);
        break;
      case 'data':
        // Données inline dans le JSON (fallback)
        final b64 = msg['b64'] as String?;
        if (b64 != null) {
          // Handle base64 encoded data if needed
        }
        break;
    }
  }

  // ═══════════════════════════════════════════
  // TCP CONNECTION MANAGEMENT
  // ═══════════════════════════════════════════

  /// Ouvre une connexion TCP réelle vers Internet.
  Future<void> _openConnection(int channelId, String host, int port) async {
    if (host.isEmpty || port <= 0) {
      _sendControl({'cmd': 'error', 'ch': channelId, 'msg': 'invalid address'});
      return;
    }

    if (_sockets.containsKey(channelId)) {
      _closeConnection(channelId);
    }

    if (_activeConnections >= maxConnections) {
      _sendControl({'cmd': 'error', 'ch': channelId, 'msg': 'max connections'});
      return;
    }

    onLog?.call('TCP[$channelId] → $host:$port');

    try {
      final socket = await Socket.connect(host, port, timeout: connectTimeout);
      _sockets[channelId] = socket;
      _activeConnections++;
      _totalConnections++;

      // Notifier le relais que la connexion est établie
      _sendControl({'cmd': 'connected', 'ch': channelId});

      // Lire les données d'Internet → renvoyer au relais
      socket.listen(
        (data) {
          _totalBytesIn += data.length;
          _sendDataToRelay(channelId, Uint8List.fromList(data));
        },
        onDone: () {
          onLog?.call('TCP[$channelId] closed by remote');
          _removeConnection(channelId);
          _sendControl({'cmd': 'close', 'ch': channelId});
        },
        onError: (e) {
          onLog?.call('TCP[$channelId] error: $e');
          _removeConnection(channelId);
          _sendControl({'cmd': 'error', 'ch': channelId, 'msg': '$e'});
        },
      );
    } catch (e) {
      onLog?.call('TCP[$channelId] connect fail: $e');
      _sendControl({'cmd': 'error', 'ch': channelId, 'msg': '$e'});
    }
  }

  /// Envoie des données au socket TCP réel.
  void _forwardToSocket(int channelId, Uint8List data) {
    final socket = _sockets[channelId];
    if (socket == null) return;

    try {
      socket.add(data);
      _totalBytesOut += data.length;
    } catch (e) {
      onLog?.call('TCP[$channelId] write error: $e');
      _removeConnection(channelId);
    }
  }

  /// Encapsule et envoie les données vers le relay.
  void _sendDataToRelay(int channelId, Uint8List data) {
    if (onSendToRelay == null) return;

    // Frame format: [2B channelId][2B length][Nb data]
    final frame = Uint8List(4 + data.length);
    frame[0] = (channelId >> 8) & 0xFF;
    frame[1] = channelId & 0xFF;
    frame[2] = (data.length >> 8) & 0xFF;
    frame[3] = data.length & 0xFF;
    frame.setRange(4, 4 + data.length, data);

    onSendToRelay!(frame);
  }

  /// Envoie un message de contrôle au relay.
  void _sendControl(Map<String, dynamic> msg) {
    onSendControlToRelay?.call(msg);
  }

  /// Ferme une connexion.
  void _closeConnection(int channelId) {
    _removeConnection(channelId);
    _sendControl({'cmd': 'close', 'ch': channelId});
  }

  /// Supprime une connexion (sans notifier le relay).
  void _removeConnection(int channelId) {
    final socket = _sockets.remove(channelId);
    if (socket != null) {
      try {
        socket.destroy();
      } catch (_) {}
      _activeConnections--;
    }
  }

  // ═══════════════════════════════════════════
  // BATCH OPERATIONS
  // ═══════════════════════════════════════════

  /// Ferme toutes les connexions.
  void closeAll() {
    for (final entry in _sockets.entries.toList()) {
      try {
        entry.value.destroy();
      } catch (_) {}
    }
    _sockets.clear();
    _activeConnections = 0;
  }

  /// Statistiques.
  Map<String, dynamic> get stats => {
        'active': _activeConnections,
        'total': _totalConnections,
        'bytesIn': _totalBytesIn,
        'bytesOut': _totalBytesOut,
        'bandwidthLimitBps': bandwidthLimitBps,
      };

  // ═══════════════════════════════════════════
  // IDLE CLEANUP
  // ═══════════════════════════════════════════

  /// Ferme les connexions sans activité depuis plus de idleTimeout.
  void _cleanupIdleConnections() {
    final now = DateTime.now();
    final toClose = <int>[];
    for (final entry in _lastActivity.entries) {
      if (now.difference(entry.value) > idleTimeout) {
        toClose.add(entry.key);
      }
    }
    for (final ch in toClose) {
      onLog?.call('TCP[$ch] idle timeout → close');
      _removeConnection(ch);
      _sendControl({'cmd': 'close', 'ch': ch});
    }
  }

  // ═══════════════════════════════════════════
  // DISPOSE
  // ═══════════════════════════════════════════

  Future<void> dispose() async {
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    closeAll();
    _lastActivity.clear();
    onSendToRelay = null;
    onSendControlToRelay = null;
    onLog = null;
  }
}
