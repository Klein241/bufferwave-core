import '../vpn/vpn_bridge.dart';

/// ════════════════════════════════════════════════════════════════
/// BufferWave Core — Smart Servers (CyberGhost style)
///
/// Intelligent server selection based on user activity type.
/// Scores nodes by bandwidth, latency, and activity fit.
/// ════════════════════════════════════════════════════════════════

enum SmartActivity { streaming, gaming, torrenting, browsing, voip }

class SmartServerResult {
  final String nodeId;
  final String country;
  final SmartActivity activity;
  final List<String> optimizations;
  final int expectedPing;

  const SmartServerResult({
    required this.nodeId,
    required this.country,
    required this.activity,
    required this.optimizations,
    required this.expectedPing,
  });

  String get activityLabel {
    switch (activity) {
      case SmartActivity.streaming:  return '📺 Streaming';
      case SmartActivity.gaming:     return '🎮 Gaming';
      case SmartActivity.torrenting: return '⬇️ Téléchargement';
      case SmartActivity.browsing:   return '🌐 Navigation';
      case SmartActivity.voip:       return '📞 Voix/Vidéo';
    }
  }

  Map<String, dynamic> toJson() => {
    'nodeId': nodeId,
    'country': country,
    'activity': activity.name,
    'optimizations': optimizations,
    'expectedPing': expectedPing,
  };
}

class SmartServersFeature {
  Function(String)? onStatusChanged;

  /// Select the best node for a given activity
  SmartServerResult selectBestServer({
    required SmartActivity activity,
    required List<Map<String, dynamic>> availableNodes,
  }) {
    if (availableNodes.isEmpty) {
      return SmartServerResult(
        nodeId: '', country: '',
        activity: activity, optimizations: [], expectedPing: 999,
      );
    }

    final scored = availableNodes
        .where((n) => n['online'] == true || n['hasWebSocket'] == true)
        .map((node) {
      double score = 0;
      final bw = (node['bandwidthMbps'] as num?)?.toDouble() ?? 0;
      final country = node['country'] as String? ?? '';
      final hasWs = node['hasWebSocket'] == true;

      if (hasWs) score += 50;

      switch (activity) {
        case SmartActivity.streaming:
          score += bw * 3;
          if (['FR', 'DE', 'US', 'CA', 'GB', 'NL'].contains(country)) score += 50;
          break;
        case SmartActivity.gaming:
          if (['CM', 'CI', 'SN', 'GA', 'CD'].contains(country)) score += 80;
          score += bw;
          break;
        case SmartActivity.torrenting:
          score += bw * 2;
          if (['NL', 'DE', 'SE', 'CA', 'RO'].contains(country)) score += 40;
          break;
        case SmartActivity.browsing:
          score += bw;
          if (country == 'CM' || country == 'CI' || country == 'SN') score += 30;
          break;
        case SmartActivity.voip:
          if (country == 'CM' || country == 'CI') score += 100;
          score += bw * 0.5;
          break;
      }
      return MapEntry(node, score);
    }).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (scored.isEmpty) {
      return SmartServerResult(
        nodeId: '', country: '',
        activity: activity, optimizations: [], expectedPing: 999,
      );
    }

    final best = scored.first.key;
    return SmartServerResult(
      nodeId: best['id'] as String? ?? '',
      country: best['country'] as String? ?? '',
      activity: activity,
      optimizations: _getOptimizations(activity),
      expectedPing: _estimatePing(best['country'] as String? ?? ''),
    );
  }

  /// Connect to the best smart server
  Future<bool> connectSmart({
    required SmartActivity activity,
    required List<Map<String, dynamic>> availableNodes,
    required String userId,
    bool killSwitch = false,
  }) async {
    final result = selectBestServer(activity: activity, availableNodes: availableNodes);
    if (result.nodeId.isEmpty) return false;

    final ok = await VpnBridge.startVpn(result.nodeId, userId, killSwitch: killSwitch);
    if (ok) {
      onStatusChanged?.call('🎯 Smart Server: ${result.activityLabel} — ${result.country}');
    }
    return ok;
  }

  List<String> _getOptimizations(SmartActivity activity) {
    switch (activity) {
      case SmartActivity.streaming:
        return ['HTTP/2 forcé', 'Buffer agrandi x4', 'Cache CDN optimisé', 'Débit prioritaire'];
      case SmartActivity.gaming:
        return ['UDP prioritaire', 'Latence minimisée', 'QoS Gaming', 'Jitter < 5ms'];
      case SmartActivity.torrenting:
        return ['P2P autorisé', 'Port forwarding', 'Vitesse max', 'NAT traversal'];
      case SmartActivity.browsing:
        return ['HTTPS forcé', 'Compression GZIP', 'DNS rapide', 'Prefetch actif'];
      case SmartActivity.voip:
        return ['Jitter réduit', 'Paquets prioritaires', 'G.711 optimisé', 'Echo annulation'];
    }
  }

  int _estimatePing(String country) {
    const pings = {
      'CM': 30, 'CI': 40, 'SN': 45, 'GA': 35, 'CD': 50, 'CG': 48,
      'FR': 120, 'BE': 130, 'DE': 140, 'CH': 145, 'NL': 135,
      'US': 200, 'CA': 190, 'GB': 125,
      'IS': 160, 'SE': 155, 'RO': 150,
    };
    return pings[country] ?? 150;
  }
}
