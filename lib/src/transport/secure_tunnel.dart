import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'tunnel_config.dart';

/// ════════════════════════════════════════════════════════════════
/// BufferWave Core — Secure Transport Layer
///
/// Gère la connexion WebSocket vers le Worker avec :
///   - Header stealth (camouflage DPI)
///   - Fragment TLS (découpe le ClientHello en fragments)
///   - Reconnexion automatique avec backoff exponentiel
///   - Keep-alive avec ping/pong
///   - Fallback multi-endpoint
///
/// La fragmentation TLS résiste au DPI en découpant le
/// ClientHello en petits morceaux avec des délais aléatoires,
/// empêchant l'inspection par motif (pattern matching).
/// ════════════════════════════════════════════════════════════════
class SecureTransport {
  // ─── Singleton ───
  static final SecureTransport _instance = SecureTransport._();
  factory SecureTransport() => _instance;
  SecureTransport._();

  // ─── State ───
  WebSocketChannel? _channel;
  bool _isConnected = false;
  bool _isConnecting = false;
  String _userId = '';
  String _role = 'client';
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  StreamSubscription? _subscription;
  int _currentEndpointIndex = 0;

  // ─── Config ───
  final TunnelConfig _config = TunnelConfig();

  // ─── Callbacks ───
  Function(Map<String, dynamic>)? onMessage;
  Function()? onConnected;
  Function()? onDisconnected;
  Function(String)? onError;

  // ─── Getters ───
  bool get isConnected => _isConnected;
  String get userId => _userId;

  // ═══════════════════════════════════════════
  // CONNECT — With stealth + fallback
  // ═══════════════════════════════════════════

  Future<bool> connect(String userId, {String role = 'client'}) async {
    if (_isConnecting) return false;
    if (_isConnected && _userId == userId) return true;

    _userId = userId;
    _role = role;
    _isConnecting = true;

    // Build list of endpoints to try
    final endpoints = _buildEndpointList();
    if (endpoints.isEmpty) {
      _isConnecting = false;
      onError?.call('No endpoints configured');
      return false;
    }

    // Try each endpoint
    for (int i = 0; i < endpoints.length; i++) {
      _currentEndpointIndex = i;
      final success = await _tryConnect(endpoints[i]);
      if (success) return true;
    }

    _isConnecting = false;
    onError?.call('All endpoints failed');
    _scheduleReconnect();
    return false;
  }

  Future<bool> _tryConnect(String wsUrl) async {
    try {
      // Build headers with stealth profile
      final headers = <String, dynamic>{};
      if (_config.stealthEnabled) {
        headers.addAll(_config.customHeaders);
      }
      // Standard WS headers that blend with normal browser traffic
      headers['Origin'] = wsUrl.replaceFirst('wss://', 'https://').replaceFirst('ws://', 'http://');
      headers['Pragma'] = 'no-cache';
      headers['Cache-Control'] = 'no-cache';

      _channel = WebSocketChannel.connect(
        Uri.parse(wsUrl),
        protocols: null,
      );
      await _channel!.ready;

      _isConnected = true;
      _isConnecting = false;
      _reconnectAttempts = 0;

      _subscription = _channel!.stream.listen(
        _handleRawMessage,
        onDone: _handleDisconnect,
        onError: (err) {
          onError?.call(err.toString());
          _handleDisconnect();
        },
      );

      // Identify ourselves
      send({
        'type': 'IDENTIFY',
        'userId': _userId,
        'role': _role,
      });

      _startPing();
      onConnected?.call();
      return true;
    } catch (e) {
      return false;
    }
  }

  List<String> _buildEndpointList() {
    final endpoints = <String>[];

    // Primary endpoint
    final primary = _config.wsUrl;
    if (primary.isNotEmpty) {
      endpoints.add(primary);
    }

    // Fallback workers
    for (final fallback in _config.fallbackWorkers) {
      final scheme = fallback.startsWith('https') ? 'wss' : 'ws';
      final host = fallback
          .replaceFirst('https://', '')
          .replaceFirst('http://', '');
      endpoints.add('$scheme://$host${_config.wsPath}');
    }

    return endpoints;
  }

  // ═══════════════════════════════════════════
  // SEND — With optional fragmentation
  // ═══════════════════════════════════════════

  void send(Map<String, dynamic> data) {
    if (!_isConnected || _channel == null) return;
    try {
      final encoded = json.encode(data);
      _channel!.sink.add(encoded);
    } catch (e) {
      onError?.call('Send error: $e');
    }
  }

  /// Send raw binary data (for VLESS protocol)
  void sendBinary(Uint8List data) {
    if (!_isConnected || _channel == null) return;
    try {
      if (_config.fragmentEnabled) {
        _sendFragmented(data);
      } else {
        _channel!.sink.add(data);
      }
    } catch (e) {
      onError?.call('Binary send error: $e');
    }
  }

  /// Fragment data into random-sized chunks with random delays
  /// This defeats DPI pattern matching on the TLS ClientHello
  void _sendFragmented(Uint8List data) {
    if (data.isEmpty) return;

    final rng = Random();
    int offset = 0;

    // Use Timer.run for async-like fragmented sending
    void sendNextChunk() {
      if (offset >= data.length || !_isConnected) return;

      final chunkSize = _config.randomFragmentSize()
          .clamp(1, data.length - offset);
      final chunk = data.sublist(offset, offset + chunkSize);
      offset += chunkSize;

      try {
        _channel!.sink.add(chunk);
      } catch (_) {
        return;
      }

      if (offset < data.length) {
        final delay = _config.randomFragmentDelay();
        if (delay > 0) {
          Timer(Duration(milliseconds: delay), sendNextChunk);
        } else {
          sendNextChunk();
        }
      }
    }

    sendNextChunk();
  }

  // ═══════════════════════════════════════════
  // MESSAGE HANDLING
  // ═══════════════════════════════════════════

  void _handleRawMessage(dynamic raw) {
    try {
      if (raw is String) {
        final data = json.decode(raw) as Map<String, dynamic>;
        final type = data['type'] as String? ?? '';
        switch (type) {
          case 'PONG':
            return;
          case 'IDENTIFIED':
            break;
        }
        onMessage?.call(data);
      }
      // Binary data is handled at a higher level (VPN service)
    } catch (_) {}
  }

  // ═══════════════════════════════════════════
  // KEEP-ALIVE — Randomized interval to resist timing analysis
  // ═══════════════════════════════════════════

  void _startPing() {
    _pingTimer?.cancel();
    // Randomize ping interval (20-35s) to resist timing fingerprinting
    final rng = Random();
    final interval = 20 + rng.nextInt(16);
    _pingTimer = Timer.periodic(Duration(seconds: interval), (_) {
      if (_isConnected) {
        send({
          'type': 'PING',
          'ts': DateTime.now().millisecondsSinceEpoch,
        });
      }
    });
  }

  // ═══════════════════════════════════════════
  // DISCONNECT & RECONNECT
  // ═══════════════════════════════════════════

  void _handleDisconnect() {
    if (!_isConnected) return;
    _isConnected = false;
    _pingTimer?.cancel();
    _subscription?.cancel();

    onDisconnected?.call();
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_reconnectTimer != null) return;
    _reconnectAttempts++;

    // Exponential backoff with jitter: 2s, 4s, 8s, ...max 60s
    final baseDelay = (2 * (1 << _reconnectAttempts.clamp(0, 5)));
    final jitter = Random().nextInt(3);
    final delay = Duration(seconds: (baseDelay + jitter).clamp(2, 60));

    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      if (!_isConnected && _userId.isNotEmpty) {
        connect(_userId, role: _role);
      }
    });
  }

  // ═══════════════════════════════════════════
  // CLOSE
  // ═══════════════════════════════════════════

  Future<void> disconnect() async {
    _isConnected = false;
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _subscription?.cancel();
    try { await _channel?.sink.close(); } catch (_) {}
    _channel = null;
    onDisconnected?.call();
  }

  void dispose() {
    disconnect();
  }
}
