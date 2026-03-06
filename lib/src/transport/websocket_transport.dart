import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

/// ════════════════════════════════════════════════════════════════
/// BufferWave Core — WebSocket Transport Layer
///
/// Pure network transport. No UI. No Flutter widgets.
/// Manages WebSocket tunnel to the BufferWave Cloudflare Worker.
/// ════════════════════════════════════════════════════════════════
class WebSocketTransport {
  String _wsUrl;

  // ─── Singleton ───
  static final WebSocketTransport _instance = WebSocketTransport._();
  factory WebSocketTransport() => _instance;
  WebSocketTransport._() : _wsUrl = 'wss://bufferwave-worker.bufferwave.workers.dev/tunnel';

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

  // ─── Callbacks ───
  Function(Map<String, dynamic>)? onMessage;
  Function()? onConnected;
  Function()? onDisconnected;
  Function(String)? onError;

  // ─── Getters ───
  bool get isConnected => _isConnected;
  String get userId => _userId;
  String get wsUrl => _wsUrl;

  /// Configure the WebSocket URL (for custom domain / bypass SNI)
  void setUrl(String url) {
    _wsUrl = url;
  }

  // ─────────────────────────────────────────
  // CONNECT
  // ─────────────────────────────────────────
  Future<bool> connect(String userId, {String role = 'client'}) async {
    if (_isConnecting) return false;
    if (_isConnected && _userId == userId) return true;

    _userId = userId;
    _role = role;
    _isConnecting = true;

    try {
      _channel = WebSocketChannel.connect(Uri.parse(_wsUrl));
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
      _isConnecting = false;
      _isConnected = false;
      onError?.call('WebSocket connexion échouée: $e');
      _scheduleReconnect();
      return false;
    }
  }

  // ─────────────────────────────────────────
  // SEND
  // ─────────────────────────────────────────
  void send(Map<String, dynamic> data) {
    if (!_isConnected || _channel == null) return;
    try {
      _channel!.sink.add(json.encode(data));
    } catch (e) {
      onError?.call('Send error: $e');
    }
  }

  // ─────────────────────────────────────────
  // MESSAGE HANDLING
  // ─────────────────────────────────────────
  void _handleRawMessage(dynamic raw) {
    try {
      final data = json.decode(raw.toString()) as Map<String, dynamic>;
      final type = data['type'] as String? ?? '';

      switch (type) {
        case 'PONG':
          return;
        case 'IDENTIFIED':
          break;
      }

      onMessage?.call(data);
    } catch (_) {}
  }

  // ─────────────────────────────────────────
  // KEEP-ALIVE
  // ─────────────────────────────────────────
  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      if (_isConnected) {
        send({'type': 'PING', 'timestamp': DateTime.now().millisecondsSinceEpoch});
      }
    });
  }

  // ─────────────────────────────────────────
  // DISCONNECT & RECONNECT
  // ─────────────────────────────────────────
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
    final delay = Duration(seconds: (2 * _reconnectAttempts).clamp(2, 30));
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      if (!_isConnected && _userId.isNotEmpty) {
        connect(_userId, role: _role);
      }
    });
  }

  // ─────────────────────────────────────────
  // CLOSE
  // ─────────────────────────────────────────
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
