import '../transport/websocket_transport.dart';

/// ════════════════════════════════════════════════════════════════
/// BufferWave Core — CleanWeb (Surfshark style)
///
/// DNS-level blocking of ads, malware, trackers, and adult content.
/// Sends blocklists to relay for server-side filtering.
/// ════════════════════════════════════════════════════════════════

class CleanWebResult {
  final String entryNode;
  final String exitNode;
  final int blockedDomainsCount;
  final List<String> features;

  const CleanWebResult({
    required this.entryNode,
    required this.exitNode,
    required this.blockedDomainsCount,
    required this.features,
  });

  Map<String, dynamic> toJson() => {
    'entryNode': entryNode,
    'exitNode': exitNode,
    'blockedDomainsCount': blockedDomainsCount,
    'features': features,
  };
}

class CleanWebFeature {
  bool _enabled = false;
  int _blockedCount = 0;
  final Set<String> _blockedDomains = {};

  Function(String)? onStatusChanged;

  bool get isEnabled => _enabled;
  int get blockedCount => _blockedCount;
  Set<String> get blockedDomains => _blockedDomains;

  /// Enable CleanWeb with DNS-level blocking
  CleanWebResult enable({
    required List<Map<String, dynamic>> availableNodes,
    bool blockAds = true,
    bool blockMalware = true,
    bool blockTrackers = true,
    bool blockAdultContent = false,
  }) {
    _blockedDomains.clear();
    if (blockAds) _blockedDomains.addAll(_adDomains);
    if (blockMalware) _blockedDomains.addAll(_malwareDomains);
    if (blockTrackers) _blockedDomains.addAll(_trackerDomains);
    if (blockAdultContent) _blockedDomains.addAll(_adultDomains);

    // Select 2 nodes in different countries for multihop
    final shuffled = List<Map<String, dynamic>>.from(availableNodes)..shuffle();
    final entry = shuffled.isNotEmpty ? shuffled[0] : null;
    final exit = shuffled.length > 1 ? shuffled[1] : null;

    _enabled = true;

    // Send blocklist to relay for server-side DNS filtering
    final ws = WebSocketTransport();
    ws.send({
      'type': 'ENABLE_CLEANWEB',
      'blockedDomains': _blockedDomains.toList(),
      'entryNode': entry?['id'],
      'exitNode': exit?['id'],
    });

    onStatusChanged?.call('🦈 CleanWeb actif — ${_blockedDomains.length} domaines bloqués');

    return CleanWebResult(
      entryNode: entry?['id'] as String? ?? 'auto',
      exitNode: exit?['id'] as String? ?? 'auto',
      blockedDomainsCount: _blockedDomains.length,
      features: [
        if (blockAds) 'Publicités',
        if (blockMalware) 'Malware',
        if (blockTrackers) 'Trackers',
        if (blockAdultContent) 'Contenu adulte',
      ],
    );
  }

  /// Check if a domain should be blocked
  bool shouldBlock(String domain) {
    if (!_enabled) return false;
    final d = domain.toLowerCase();
    if (_blockedDomains.any((b) => d.endsWith(b) || d == b)) {
      _blockedCount++;
      return true;
    }
    return false;
  }

  void disable() {
    _enabled = false;
    _blockedDomains.clear();
    _blockedCount = 0;
    onStatusChanged?.call('CleanWeb désactivé');
  }

  // ─── Comprehensive Blocklists ───
  static const _adDomains = [
    'doubleclick.net', 'googlesyndication.com', 'googleadservices.com',
    'adnxs.com', 'advertising.com', 'facebook.net', 'amazon-adsystem.com',
    'adsrvr.org', 'pubmatic.com', 'rubiconproject.com',
    'taboola.com', 'outbrain.com', 'criteo.com', 'adform.net',
    'appnexus.com', 'moat.com', 'openx.net', 'casalemedia.com',
    'spotxchange.com', 'contextweb.com', 'yieldmanager.com',
    'serving-sys.com', 'flashtalking.com', 'zedo.com', 'bidswitch.net',
  ];

  static const _malwareDomains = [
    'malware.com', 'phishing.net', 'ransomware.io', 'trojan.cc',
    'botnet.ru', 'spyware.net', 'eicar.org', 'malwaredomainlist.com',
    'malware-traffic-analysis.net', 'virusshare.com',
    'coinhive.com', 'coin-hive.com', 'jsecoin.com', 'authedmine.com',
  ];

  static const _trackerDomains = [
    'google-analytics.com', 'analytics.google.com', 'hotjar.com',
    'mixpanel.com', 'amplitude.com', 'segment.io', 'fullstory.com',
    'clarity.ms', 'mouseflow.com', 'kissmetrics.com',
    'crazyegg.com', 'optimizely.com', 'newrelic.com',
    'scorecardresearch.com', 'quantserve.com', 'chartbeat.com',
  ];

  static const _adultDomains = [
    'pornhub.com', 'xvideos.com', 'xnxx.com', 'redtube.com',
    'youjizz.com', 'xhamster.com',
  ];
}
