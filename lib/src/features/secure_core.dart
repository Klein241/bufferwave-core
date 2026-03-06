import '../transport/websocket_transport.dart';
import '../vpn/vpn_bridge.dart';

/// ════════════════════════════════════════════════════════════════
/// BufferWave Core — Secure Core (ProtonVPN style)
///
/// Routes traffic through hardened servers in privacy-friendly
/// countries (CH, IS, SE) before reaching the destination.
/// Jean → Secure Core Node (CH/IS/SE) → Destination Node → Internet
/// ════════════════════════════════════════════════════════════════

class SecureCoreSession {
  final String secureCoreNodeId;
  final String secureCoreCountry;
  final String destinationNodeId;
  final String destinationCountry;
  final int encryptionLayers;
  final DateTime startedAt;

  const SecureCoreSession({
    required this.secureCoreNodeId,
    required this.secureCoreCountry,
    required this.destinationNodeId,
    required this.destinationCountry,
    required this.encryptionLayers,
    required this.startedAt,
  });

  Map<String, dynamic> toJson() => {
    'secureCoreNodeId': secureCoreNodeId,
    'secureCoreCountry': secureCoreCountry,
    'destinationNodeId': destinationNodeId,
    'destinationCountry': destinationCountry,
    'encryptionLayers': encryptionLayers,
    'startedAt': startedAt.toIso8601String(),
  };
}

class SecureCoreFeature {
  SecureCoreSession? _session;
  Function(String)? onStatusChanged;

  SecureCoreSession? get session => _session;
  bool get isActive => _session != null;

  /// Privacy-friendly countries for Secure Core routing
  static const secureCoreCountries = ['CH', 'IS', 'SE', 'CA', 'DE'];

  /// Enable Secure Core routing
  Future<SecureCoreSession?> enable({
    required String destinationCountry,
    required List<Map<String, dynamic>> availableNodes,
  }) async {
    // Find a Secure Core node (CH, IS, SE priority)
    Map<String, dynamic>? secureCoreNode;
    for (final country in secureCoreCountries) {
      try {
        secureCoreNode = availableNodes.firstWhere(
          (n) => n['country'] == country && n['online'] == true,
        );
        break;
      } catch (_) {
        continue;
      }
    }

    secureCoreNode ??= availableNodes.isNotEmpty ? availableNodes[0] : null;
    if (secureCoreNode == null) return null;

    // Find destination node
    Map<String, dynamic>? destNode;
    try {
      destNode = availableNodes.firstWhere(
        (n) => n['country'] == destinationCountry && n['online'] == true,
      );
    } catch (_) {
      destNode = availableNodes.isNotEmpty ? availableNodes.last : null;
    }
    if (destNode == null) return null;

    _session = SecureCoreSession(
      secureCoreNodeId: secureCoreNode['id'] as String? ?? 'sc_node',
      secureCoreCountry: secureCoreNode['country'] as String? ?? 'CH',
      destinationNodeId: destNode['id'] as String? ?? 'dest_node',
      destinationCountry: destinationCountry,
      encryptionLayers: 3,
      startedAt: DateTime.now(),
    );

    // Set up Secure Core routing on the server
    final ws = WebSocketTransport();
    ws.send({
      'type': 'ENABLE_SECURE_CORE',
      'secureCoreNodeId': _session!.secureCoreNodeId,
      'destinationNodeId': _session!.destinationNodeId,
      'encryptionLayers': 3,
    });

    onStatusChanged?.call('🏰 Secure Core: ${_session!.secureCoreCountry} → ${_session!.destinationCountry}');
    return _session;
  }

  void disable() {
    _session = null;
    onStatusChanged?.call('Secure Core désactivé');
  }
}
