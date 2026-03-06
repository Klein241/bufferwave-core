import '../transport/websocket_transport.dart';

/// ════════════════════════════════════════════════════════════════
/// BufferWave Core — Multihop
///
/// Route traffic through multiple nodes in different countries.
/// Entry Node → Transit Node(s) → Exit Node → Internet
/// ════════════════════════════════════════════════════════════════

class MultihopRoute {
  final List<String> nodeIds;
  final List<String> countries;
  final int hopCount;
  final DateTime startedAt;

  const MultihopRoute({
    required this.nodeIds,
    required this.countries,
    required this.hopCount,
    required this.startedAt,
  });

  String get routeLabel => countries.join(' → ');

  Map<String, dynamic> toJson() => {
    'nodeIds': nodeIds,
    'countries': countries,
    'hopCount': hopCount,
    'startedAt': startedAt.toIso8601String(),
  };
}

class MultihopFeature {
  MultihopRoute? _route;
  bool _enabled = false;
  Function(String)? onStatusChanged;

  MultihopRoute? get route => _route;
  bool get isEnabled => _enabled;

  /// Build a multihop route through N countries
  MultihopRoute? buildRoute({
    required List<String> desiredCountries,
    required List<Map<String, dynamic>> availableNodes,
  }) {
    final routeNodes = <String>[];
    final routeCountries = <String>[];

    for (final country in desiredCountries) {
      final node = availableNodes.firstWhere(
        (n) => n['country'] == country && n['online'] == true,
        orElse: () => <String, dynamic>{},
      );
      if (node.isNotEmpty) {
        routeNodes.add(node['id'] as String);
        routeCountries.add(country);
      }
    }

    if (routeNodes.length < 2) return null;

    return MultihopRoute(
      nodeIds: routeNodes,
      countries: routeCountries,
      hopCount: routeNodes.length,
      startedAt: DateTime.now(),
    );
  }

  /// Enable multihop with a specific route
  void enable(MultihopRoute route) {
    _route = route;
    _enabled = true;

    // Tell server to set up multihop chain
    final ws = WebSocketTransport();
    ws.send({
      'type': 'SETUP_MULTIHOP',
      'nodeIds': route.nodeIds,
      'countries': route.countries,
      'hopCount': route.hopCount,
    });

    onStatusChanged?.call('🔗 Multihop actif: ${route.routeLabel}');
  }

  void disable() {
    _route = null;
    _enabled = false;
    onStatusChanged?.call('Multihop désactivé');
  }
}
