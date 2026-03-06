import 'dart:async';
import '../vpn/vpn_bridge.dart';

/// ════════════════════════════════════════════════════════════════
/// BUFFERWAVE — Kill Switch
///
/// Bloque TOUT le trafic internet si le tunnel VPN tombe.
///
/// 2 niveaux de protection :
///   1. Monitoring Dart : vérifie toutes les 3s si le VPN tourne
///   2. Natif Android : via VPN always-on + block sans VPN
///      (configuré dans BufferWaveVpnService via le flag killSwitch)
///
/// Usage :
///   killSwitch.enable(
///     onVpnDisconnected: () => print('BLOCKED'),
///     onVpnConnected: () => print('OK'),
///   );
///   killSwitch.disable();
///
/// ════════════════════════════════════════════════════════════════

class KillSwitchFeature {
  bool _armed = false;
  Timer? _monitor;
  bool _wasConnected = false;
  int _disconnectCount = 0;
  DateTime? _lastTrigger;

  /// Callbacks
  Function(String reason)? onTriggered;
  Function(String status)? onStatusChanged;

  /// State
  bool get isArmed => _armed;
  int get disconnectCount => _disconnectCount;
  DateTime? get lastTrigger => _lastTrigger;

  /// Arm the kill switch
  void enable({
    required Function() onVpnConnected,
    required Function() onVpnDisconnected,
  }) {
    _armed = true;
    _wasConnected = true;

    // Listen to VPN bridge connection changes
    VpnBridge.onConnectionChanged = (connected) {
      if (!_armed) return;

      if (!connected && _wasConnected) {
        // VPN just dropped — TRIGGER
        _wasConnected = false;
        _trigger('VPN tunnel dropped unexpectedly');
        onVpnDisconnected();
      } else if (connected && !_wasConnected) {
        // VPN recovered
        _wasConnected = true;
        onStatusChanged?.call('✅ VPN restored — Kill Switch still armed');
        onVpnConnected();
      }
    };

    // Periodic health check — catches cases where the bridge
    // callback doesn't fire (e.g. native crash)
    _startMonitor(onVpnDisconnected);

    onStatusChanged?.call('🔴 Kill Switch armed');
  }

  /// Disarm the kill switch
  void disable() {
    _armed = false;
    _monitor?.cancel();
    _monitor = null;
    VpnBridge.onConnectionChanged = null;
    onStatusChanged?.call('Kill Switch disarmed');
  }

  /// Internal: trigger the kill switch
  void _trigger(String reason) {
    if (!_armed) return;
    _disconnectCount++;
    _lastTrigger = DateTime.now();
    onTriggered?.call(reason);
    onStatusChanged?.call('🔴 KILL SWITCH: $reason');

    // ★ Request native kill switch activation
    // This tells Android to block all non-VPN traffic
    _activateNativeKillSwitch();
  }

  /// Periodic monitoring — backup safety net
  void _startMonitor(Function() onVpnDisconnected) {
    _monitor?.cancel();
    _monitor = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!_armed) {
        _monitor?.cancel();
        return;
      }

      try {
        final running = await VpnBridge.isRunning();

        if (!running && _wasConnected) {
          _wasConnected = false;
          _trigger('VPN stopped unexpectedly (monitor)');
          onVpnDisconnected();
        } else if (running && !_wasConnected) {
          _wasConnected = true;
          onStatusChanged?.call('✅ VPN restored');
        }
      } catch (_) {
        // Ignore transient errors
      }
    });
  }

  /// Request native Android kill switch
  /// This uses the MethodChannel to tell Android to enable
  /// "Block connections without VPN" at the system level
  void _activateNativeKillSwitch() {
    VpnBridge.enableNativeKillSwitch();
  }

  void dispose() {
    disable();
  }
}
