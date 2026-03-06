import '../transport/websocket_transport.dart';

/// ════════════════════════════════════════════════════════════════
/// BufferWave Core — Lightway Protocol (ExpressVPN style)
///
/// Ultra-fast protocol using ChaCha20-Poly1305 cipher.
/// Supports UDP (fast) and TCP (stable) modes.
/// ════════════════════════════════════════════════════════════════

enum LightwayProtocol { udp, tcp }

class LightwayConfig {
  final LightwayProtocol protocol;
  final int port;
  final String cipher;
  final bool compression;
  final int expectedLatencyMs;

  const LightwayConfig({
    required this.protocol,
    required this.port,
    required this.cipher,
    required this.compression,
    required this.expectedLatencyMs,
  });

  String get protocolLabel =>
      protocol == LightwayProtocol.udp ? 'UDP (rapide)' : 'TCP (stable)';

  Map<String, dynamic> toJson() => {
    'protocol': protocol.name,
    'port': port,
    'cipher': cipher,
    'compression': compression,
    'expectedLatencyMs': expectedLatencyMs,
  };
}

class LightwayFeature {
  bool _enabled = false;
  LightwayProtocol _activeProtocol = LightwayProtocol.udp;
  int _port = 1194;
  Function(String)? onStatusChanged;

  bool get isEnabled => _enabled;
  LightwayProtocol get activeProtocol => _activeProtocol;

  /// Enable Lightway protocol
  LightwayConfig enable({
    LightwayProtocol protocol = LightwayProtocol.udp,
  }) {
    _activeProtocol = protocol;
    _port = protocol == LightwayProtocol.udp ? 1194 : 443;
    _enabled = true;

    // Configure the relay to use optimized packet handling
    final ws = WebSocketTransport();
    ws.send({
      'type': 'ENABLE_LIGHTWAY',
      'protocol': protocol.name,
      'port': _port,
      'cipher': 'ChaCha20-Poly1305',
      'compression': true,
    });

    final config = LightwayConfig(
      protocol: protocol,
      port: _port,
      cipher: 'ChaCha20-Poly1305',
      compression: true,
      expectedLatencyMs: protocol == LightwayProtocol.udp ? 8 : 25,
    );

    onStatusChanged?.call('⚡ Lightway ${config.protocolLabel} activé');
    return config;
  }

  void disable() {
    _enabled = false;
    onStatusChanged?.call('Lightway désactivé');
  }
}
