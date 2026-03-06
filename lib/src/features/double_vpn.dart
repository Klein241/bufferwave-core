import 'dart:math';
import '../transport/websocket_transport.dart';
import '../models/premium_config.dart';
import '../vpn/vpn_bridge.dart';

/// ════════════════════════════════════════════════════════════════
/// BufferWave Core — Double VPN (NordVPN style)
///
/// Chain of 2 relay nodes for double encryption.
/// Jean → Node A (encryption 1) → Node B (encryption 2) → Internet
/// ════════════════════════════════════════════════════════════════

class DoubleVpnSession {
  final String primaryNodeId;
  final String secondaryNodeId;
  final String userId;
  final String encryptionKey1;
  final String encryptionKey2;
  final DateTime startedAt;

  const DoubleVpnSession({
    required this.primaryNodeId,
    required this.secondaryNodeId,
    required this.userId,
    required this.encryptionKey1,
    required this.encryptionKey2,
    required this.startedAt,
  });

  String get shortPrimary => primaryNodeId.length > 10
      ? '${primaryNodeId.substring(0, 10)}...' : primaryNodeId;
  String get shortSecondary => secondaryNodeId.length > 10
      ? '${secondaryNodeId.substring(0, 10)}...' : secondaryNodeId;

  Map<String, dynamic> toJson() => {
    'primaryNodeId': primaryNodeId,
    'secondaryNodeId': secondaryNodeId,
    'userId': userId,
    'startedAt': startedAt.toIso8601String(),
  };
}

class DoubleVpnFeature {
  DoubleVpnSession? _session;
  Function(String)? onStatusChanged;

  DoubleVpnSession? get session => _session;
  bool get isActive => _session != null;

  /// Start Double VPN: route through 2 nodes
  Future<DoubleVpnSession?> start({
    required String primaryNodeId,
    required String secondaryNodeId,
    required String userId,
    bool killSwitch = false,
  }) async {
    final key1 = _generateKey();
    final key2 = _generateKey();

    _session = DoubleVpnSession(
      primaryNodeId: primaryNodeId,
      secondaryNodeId: secondaryNodeId,
      userId: userId,
      encryptionKey1: key1,
      encryptionKey2: key2,
      startedAt: DateTime.now(),
    );

    // Start VPN with primary node
    final ok = await VpnBridge.startVpn(primaryNodeId, userId, killSwitch: killSwitch);
    if (!ok) {
      _session = null;
      return null;
    }

    // Tell the server to set up the chain: primary → secondary
    final ws = WebSocketTransport();
    ws.send({
      'type': 'SETUP_DOUBLE_VPN',
      'userId': userId,
      'primaryNodeId': primaryNodeId,
      'secondaryNodeId': secondaryNodeId,
      'encryptionKey1': key1,
      'encryptionKey2': key2,
    });

    onStatusChanged?.call('🔒🔒 Double VPN actif: ${_session!.shortPrimary} → ${_session!.shortSecondary}');
    return _session;
  }

  Future<void> stop() async {
    _session = null;
    onStatusChanged?.call('Double VPN désactivé');
  }

  String _generateKey() {
    final rng = Random.secure();
    return List.generate(32, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }
}
