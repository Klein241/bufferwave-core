import 'dart:async';
import 'package:flutter/services.dart';
import '../transport/tunnel_config.dart';

/// ════════════════════════════════════════════════════════════════
/// BufferWave Core — VPN Bridge
///
/// Pont pur entre Flutter/Dart et le VPN natif Android.
/// Communication via MethodChannel uniquement.
/// Aucune dépendance UI.
///
/// MethodChannel "bufferwave/vpn" :
///   startVpn(config)        → bool
///   startLocalProxy(config) → bool
///   stopVpn()               → void
///   isRunning()              → bool
///   getVpnStatus()          → Map
///   enableKillSwitch()      → void
///   disableKillSwitch()     → void
/// ════════════════════════════════════════════════════════════════
class VpnBridge {
  static const MethodChannel _channel = MethodChannel('bufferwave/vpn');

  static bool _isRunning = false;
  static String _connectedNodeId = '';
  static DateTime? _connectionStart;
  static Timer? _statusCheckTimer;
  static final TunnelConfig _config = TunnelConfig();

  // ─── Callbacks ───
  static Function(bool connected)? onConnectionChanged;
  static Function(String status)? onStatusChanged;

  // ════════════════════════════════════════════
  // START VPN — Standard VLESS mode
  // ════════════════════════════════════════════

  static Future<bool> startVpn(String nodeId, String userId, {
    bool killSwitch = false,
  }) async {
    try {
      final result = await _channel.invokeMethod('startVpn', {
        'nodeId': nodeId,
        'userId': userId,
        'killSwitch': killSwitch,
        // Pass tunnel config to native service
        'tunnelKey': _config.tunnelKey,
        'workerUrl': _config.workerUrl,
        'wsPath': _config.wsPath,
        'dohEndpoint': _config.dohEndpoint,
        'originProxy': _config.originProxy,
        'stealthEnabled': _config.stealthEnabled,
        'fragmentEnabled': _config.fragmentEnabled,
        'fragmentMinDelay': _config.fragmentMinDelay,
        'fragmentMaxDelay': _config.fragmentMaxDelay,
        'fragmentMinSize': _config.fragmentMinSize,
        'fragmentMaxSize': _config.fragmentMaxSize,
        'customHeaders': _config.customHeaders,
      });
      final success = result == true;
      if (success) {
        _isRunning = true;
        _connectedNodeId = nodeId;
        _connectionStart = DateTime.now();
        onConnectionChanged?.call(true);
        onStatusChanged?.call('Tunnel actif');
        _startStatusCheck();
      }
      return success;
    } catch (e) {
      onStatusChanged?.call('Erreur tunnel: $e');
      return false;
    }
  }

  // ════════════════════════════════════════════
  // START LOCAL PROXY — P2P mode (Marie's relay)
  // ════════════════════════════════════════════

  static Future<bool> startLocalProxy({
    required String proxyHost,
    required int proxyPort,
    bool killSwitch = false,
  }) async {
    try {
      final result = await _channel.invokeMethod('startVpn', {
        'nodeId': 'local',
        'userId': 'p2p',
        'killSwitch': killSwitch,
        'localProxy': true,
        'proxyHost': proxyHost,
        'proxyPort': proxyPort,
      });
      final success = result == true;
      if (success) {
        _isRunning = true;
        _connectedNodeId = 'p2p-$proxyHost';
        _connectionStart = DateTime.now();
        onConnectionChanged?.call(true);
        onStatusChanged?.call('Tunnel P2P actif via $proxyHost');
        _startStatusCheck();
      }
      return success;
    } catch (e) {
      onStatusChanged?.call('Erreur proxy local: $e');
      return false;
    }
  }

  // ════════════════════════════════════════════
  // STOP VPN
  // ════════════════════════════════════════════

  static Future<void> stopVpn() async {
    try {
      await _channel.invokeMethod('stopVpn');
    } catch (_) {}
    _cleanup();
    onConnectionChanged?.call(false);
    onStatusChanged?.call('Mode sécurisé arrêté');
  }

  // ════════════════════════════════════════════
  // STATUS
  // ════════════════════════════════════════════

  static Future<bool> isRunning() async {
    try {
      final result = await _channel.invokeMethod('isRunning');
      _isRunning = result == true;
      return _isRunning;
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, dynamic>> getStatus() async {
    try {
      final result = await _channel.invokeMethod('getVpnStatus');
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
    } catch (_) {}
    return {
      'isRunning': _isRunning,
      'nodeId': _connectedNodeId,
      'uptimeSeconds': connectionDuration.inSeconds,
    };
  }

  // ════════════════════════════════════════════
  // KILL SWITCH (Native)
  // ════════════════════════════════════════════

  static void enableNativeKillSwitch() {
    try {
      _channel.invokeMethod('enableKillSwitch');
    } catch (_) {}
  }

  static void disableNativeKillSwitch() {
    try {
      _channel.invokeMethod('disableKillSwitch');
    } catch (_) {}
  }

  // ════════════════════════════════════════════
  // PERIODIC MONITORING
  // ════════════════════════════════════════════

  static void _startStatusCheck() {
    _statusCheckTimer?.cancel();
    _statusCheckTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!_isRunning) {
        _statusCheckTimer?.cancel();
        return;
      }
      final running = await isRunning();
      if (!running && _isRunning) {
        _isRunning = false;
        _connectedNodeId = '';
        onConnectionChanged?.call(false);
        onStatusChanged?.call('Tunnel perdu');
      }
    });
  }

  static void _cleanup() {
    _isRunning = false;
    _connectedNodeId = '';
    _connectionStart = null;
    _statusCheckTimer?.cancel();
    _statusCheckTimer = null;
  }

  // ─── Getters ───
  static bool get running => _isRunning;
  static String get connectedNodeId => _connectedNodeId;
  static Duration get connectionDuration =>
      _connectionStart != null
          ? DateTime.now().difference(_connectionStart!)
          : Duration.zero;
}
