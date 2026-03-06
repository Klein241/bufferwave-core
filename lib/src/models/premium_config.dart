/// ════════════════════════════════════════════════════════════════
/// BufferWave Core — Premium Configuration Model
///
/// Shared configuration state for all premium features.
/// ════════════════════════════════════════════════════════════════

import '../features/lightway.dart';

class PremiumConfig {
  final bool doubleVpnEnabled;
  final bool lightwayEnabled;
  final LightwayProtocol lightwayProtocol;
  final bool cleanWebEnabled;
  final bool multihopEnabled;
  final bool blockAds;
  final bool blockMalware;
  final bool blockTrackers;
  final bool secureCoreEnabled;
  final bool killSwitchEnabled;
  final bool splitTunnelingEnabled;

  const PremiumConfig({
    this.doubleVpnEnabled = false,
    this.lightwayEnabled = false,
    this.lightwayProtocol = LightwayProtocol.udp,
    this.cleanWebEnabled = false,
    this.multihopEnabled = false,
    this.blockAds = true,
    this.blockMalware = true,
    this.blockTrackers = true,
    this.secureCoreEnabled = false,
    this.killSwitchEnabled = false,
    this.splitTunnelingEnabled = false,
  });

  factory PremiumConfig.defaults() => const PremiumConfig();

  PremiumConfig copyWith({
    bool? doubleVpnEnabled, bool? lightwayEnabled,
    LightwayProtocol? lightwayProtocol,
    bool? cleanWebEnabled, bool? multihopEnabled,
    bool? blockAds, bool? blockMalware, bool? blockTrackers,
    bool? secureCoreEnabled, bool? killSwitchEnabled,
    bool? splitTunnelingEnabled,
  }) => PremiumConfig(
    doubleVpnEnabled:     doubleVpnEnabled     ?? this.doubleVpnEnabled,
    lightwayEnabled:      lightwayEnabled       ?? this.lightwayEnabled,
    lightwayProtocol:     lightwayProtocol      ?? this.lightwayProtocol,
    cleanWebEnabled:      cleanWebEnabled       ?? this.cleanWebEnabled,
    multihopEnabled:      multihopEnabled       ?? this.multihopEnabled,
    blockAds:             blockAds              ?? this.blockAds,
    blockMalware:         blockMalware          ?? this.blockMalware,
    blockTrackers:        blockTrackers         ?? this.blockTrackers,
    secureCoreEnabled:    secureCoreEnabled      ?? this.secureCoreEnabled,
    killSwitchEnabled:    killSwitchEnabled      ?? this.killSwitchEnabled,
    splitTunnelingEnabled: splitTunnelingEnabled ?? this.splitTunnelingEnabled,
  );

  Map<String, dynamic> toJson() => {
    'doubleVpn': doubleVpnEnabled, 'lightway': lightwayEnabled,
    'lightwayProtocol': lightwayProtocol.name,
    'cleanWeb': cleanWebEnabled, 'multihop': multihopEnabled,
    'blockAds': blockAds, 'blockMalware': blockMalware, 'blockTrackers': blockTrackers,
    'secureCore': secureCoreEnabled, 'killSwitch': killSwitchEnabled,
    'splitTunneling': splitTunnelingEnabled,
  };

  factory PremiumConfig.fromJson(Map<String, dynamic> j) => PremiumConfig(
    doubleVpnEnabled:     j['doubleVpn'] ?? false,
    lightwayEnabled:      j['lightway'] ?? false,
    lightwayProtocol:     j['lightwayProtocol'] == 'tcp'
        ? LightwayProtocol.tcp : LightwayProtocol.udp,
    cleanWebEnabled:      j['cleanWeb'] ?? false,
    multihopEnabled:      j['multihop'] ?? false,
    blockAds:             j['blockAds'] ?? true,
    blockMalware:         j['blockMalware'] ?? true,
    blockTrackers:        j['blockTrackers'] ?? true,
    secureCoreEnabled:    j['secureCore'] ?? false,
    killSwitchEnabled:    j['killSwitch'] ?? false,
    splitTunnelingEnabled: j['splitTunneling'] ?? false,
  );
}
