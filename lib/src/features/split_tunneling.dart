import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// ════════════════════════════════════════════════════════════════
/// BufferWave Core — Split Tunneling
///
/// Choose which apps go through the VPN and which bypass it.
/// On Android, requires VPN restart via addDisallowedApplication.
/// ════════════════════════════════════════════════════════════════

enum TunnelMode { vpn, bypass, block }

class AppTunnel {
  final String packageName;
  final String appName;
  final TunnelMode mode;
  final String icon;

  const AppTunnel({
    required this.packageName,
    required this.appName,
    required this.mode,
    required this.icon,
  });

  AppTunnel copyWith({TunnelMode? mode}) => AppTunnel(
    packageName: packageName,
    appName: appName,
    mode: mode ?? this.mode,
    icon: icon,
  );

  String get modeLabel {
    switch (mode) {
      case TunnelMode.vpn:    return 'Via VPN';
      case TunnelMode.bypass: return 'Direct';
      case TunnelMode.block:  return 'Bloquée';
    }
  }

  Map<String, dynamic> toJson() => {
    'packageName': packageName,
    'appName': appName,
    'mode': mode.name,
    'icon': icon,
  };

  factory AppTunnel.fromJson(Map<String, dynamic> j) => AppTunnel(
    packageName: j['packageName'] ?? '',
    appName: j['appName'] ?? '',
    mode: TunnelMode.values.firstWhere(
      (m) => m.name == j['mode'],
      orElse: () => TunnelMode.vpn,
    ),
    icon: j['icon'] ?? '📱',
  );
}

class SplitTunnelingFeature {
  bool _enabled = false;
  Function(String)? onStatusChanged;

  bool get isEnabled => _enabled;

  /// Get the list of configured apps
  Future<List<AppTunnel>> getApps() async {
    final raw = (await SharedPreferences.getInstance()).getString('split_tunneling_apps');
    if (raw == null) return _defaultApps();
    try {
      return (json.decode(raw) as List)
          .map((e) => AppTunnel.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return _defaultApps();
    }
  }

  /// Set tunnel mode for a specific app
  Future<void> setAppMode(String packageName, TunnelMode mode) async {
    final apps = await getApps();
    final idx = apps.indexWhere((a) => a.packageName == packageName);
    final app = apps.firstWhere(
      (a) => a.packageName == packageName,
      orElse: () => AppTunnel(
        packageName: packageName,
        appName: packageName,
        mode: mode,
        icon: '📱',
      ),
    );
    final updated = app.copyWith(mode: mode);
    if (idx >= 0) {
      apps[idx] = updated;
    } else {
      apps.add(updated);
    }
    final p = await SharedPreferences.getInstance();
    await p.setString('split_tunneling_apps', json.encode(apps.map((a) => a.toJson()).toList()));
    _enabled = true;

    onStatusChanged?.call('Split Tunneling: ${app.appName} → ${updated.modeLabel}');
  }

  /// Get packages that should bypass the VPN
  Future<List<String>> getBypassPackages() async {
    final apps = await getApps();
    return apps.where((a) => a.mode == TunnelMode.bypass).map((a) => a.packageName).toList();
  }

  /// Get packages that should be blocked
  Future<List<String>> getBlockedPackages() async {
    final apps = await getApps();
    return apps.where((a) => a.mode == TunnelMode.block).map((a) => a.packageName).toList();
  }

  void enable() {
    _enabled = true;
    onStatusChanged?.call('Split Tunneling activé');
  }

  void disable() {
    _enabled = false;
    onStatusChanged?.call('Split Tunneling désactivé');
  }

  List<AppTunnel> _defaultApps() => [
    const AppTunnel(packageName: 'com.android.chrome', appName: 'Chrome', mode: TunnelMode.vpn, icon: '🌐'),
    const AppTunnel(packageName: 'com.whatsapp', appName: 'WhatsApp', mode: TunnelMode.vpn, icon: '💬'),
    const AppTunnel(packageName: 'com.youtube', appName: 'YouTube', mode: TunnelMode.vpn, icon: '▶️'),
    const AppTunnel(packageName: 'com.instagram.android', appName: 'Instagram', mode: TunnelMode.vpn, icon: '📸'),
    const AppTunnel(packageName: 'com.facebook.katana', appName: 'Facebook', mode: TunnelMode.vpn, icon: '👤'),
    const AppTunnel(packageName: 'com.spotify.music', appName: 'Spotify', mode: TunnelMode.bypass, icon: '🎵'),
    const AppTunnel(packageName: 'com.google.android.apps.maps', appName: 'Maps', mode: TunnelMode.bypass, icon: '🗺️'),
    const AppTunnel(packageName: 'com.bufferwave.app', appName: 'BufferWave', mode: TunnelMode.vpn, icon: '🌊'),
  ];
}
