import 'dart:async';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'vpn/vpn_bridge.dart';
import 'api/bufferwave_api.dart';
import 'features/kill_switch.dart';
import 'features/doh_resolver.dart';
import 'transport/tunnel_config.dart';

/// ════════════════════════════════════════════════════════════════
/// BUFFERWAVE CORE v12.0 — Production VPN API
///
/// Moteur réseau vendable — 5 piliers :
///   1. Tunnel VLESS (Cloudflare Worker stealth)
///   2. VPN Bridge (Flutter ↔ Android native)
///   3. Kill Switch (coupe internet si VPN tombe)
///   4. DoH Resolver (DNS chiffré, pas d'UDP clair)
///   5. Stealth Engine (obfuscation, fragment TLS, decoy)
///
/// Usage :
///   final bw = BufferWave();
///   await bw.initialize();
///
///   // Configurer (obligatoire — aucune clé hardcodée)
///   bw.configure(
///     workerUrl: 'https://my-worker.example.com',
///     tunnelKey: 'mon-uuid-unique',
///   );
///
///   // Connecter
///   await bw.connect(killSwitch: true, stealth: true);
///
///   // Status
///   print(bw.status);
///
///   // Déconnecter
///   await bw.disconnect();
/// ════════════════════════════════════════════════════════════════

// ─── Connection Status ───
enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  reconnecting,
  error,
}

// ─── Status Snapshot ───
class BufferWaveStatus {
  final ConnectionStatus connection;
  final String userId;
  final String nodeId;
  final Duration uptime;
  final bool vpnActive;
  final bool killSwitchArmed;
  final bool dohEnabled;
  final bool stealthEnabled;
  final bool fragmentEnabled;
  final String protocol;
  final String workerUrl;

  const BufferWaveStatus({
    required this.connection,
    required this.userId,
    required this.nodeId,
    required this.uptime,
    required this.vpnActive,
    required this.killSwitchArmed,
    this.dohEnabled = false,
    this.stealthEnabled = false,
    this.fragmentEnabled = false,
    this.protocol = 'VLESS',
    this.workerUrl = '',
  });

  bool get isConnected => connection == ConnectionStatus.connected;
  bool get isDisconnected => connection == ConnectionStatus.disconnected;
  bool get hasError => connection == ConnectionStatus.error;

  Map<String, dynamic> toJson() => {
    'connection': connection.name,
    'userId': userId,
    'nodeId': nodeId,
    'uptimeSeconds': uptime.inSeconds,
    'vpnActive': vpnActive,
    'killSwitchArmed': killSwitchArmed,
    'dohEnabled': dohEnabled,
    'stealthEnabled': stealthEnabled,
    'fragmentEnabled': fragmentEnabled,
    'protocol': protocol,
    'workerUrl': workerUrl,
  };

  @override
  String toString() => 'BufferWaveStatus(${connection.name}, node=$nodeId, '
      'uptime=${uptime.inSeconds}s, stealth=$stealthEnabled, doh=$dohEnabled)';
}

/// ════════════════════════════════════════════════════════════════
/// BUFFERWAVE — Main API Class
///
/// Singleton. Thread-safe. Zero UI dependency.
/// ════════════════════════════════════════════════════════════════
class BufferWave {
  // ─── Singleton ───
  static final BufferWave _instance = BufferWave._();
  factory BufferWave() => _instance;
  BufferWave._();

  // ─── State ───
  ConnectionStatus _status = ConnectionStatus.disconnected;
  String _userId = '';
  String _nodeId = '';
  Timer? _heartbeatTimer;
  bool _initialized = false;

  // ─── Components ───
  final KillSwitchFeature _killSwitch = KillSwitchFeature();
  final DohResolver _doh = DohResolver();
  final TunnelConfig _config = TunnelConfig();

  // ─── Callbacks ───
  Function(ConnectionStatus status)? onStatusChanged;
  Function(String error)? onError;
  Function(String message)? onMessage;

  // ─── Getters ───
  ConnectionStatus get connectionStatus => _status;
  bool get isConnected => _status == ConnectionStatus.connected;
  bool get isInitialized => _initialized;
  bool get isKillSwitchArmed => _killSwitch.isArmed;
  String get userId => _userId;
  KillSwitchFeature get killSwitch => _killSwitch;
  DohResolver get doh => _doh;
  TunnelConfig get config => _config;

  // ────────────────────────────────────────────────────────────
  // INITIALIZE — Must be called before connect()
  // ────────────────────────────────────────────────────────────

  /// Initialise le moteur : charge la config, prépare les composants
  Future<void> initialize() async {
    if (_initialized) return;

    await _config.load();
    _userId = await _getOrCreateUserId();

    // Auto-configure DoH si endpoint disponible
    if (_config.dohEndpoint.isNotEmpty) {
      _doh.setEndpoint(_config.dohEndpoint);
    }

    _initialized = true;
    onMessage?.call('BufferWave Core initialisé');
  }

  // ────────────────────────────────────────────────────────────
  // CONFIGURE — Set connection parameters
  // ────────────────────────────────────────────────────────────

  /// Configure les paramètres de connexion
  /// OBLIGATOIRE avant connect() — aucune clé hardcodée
  void configure({
    String? workerUrl,
    String? tunnelKey,
    String? backupKey,
    String? panelSecret,
    String? originProxy,
    String? dohEndpoint,
    List<String>? fallbackWorkers,
  }) {
    if (workerUrl != null) {
      _config.setWorkerUrl(workerUrl);
      BufferWaveApi.setBaseUrl(workerUrl);
    }
    if (tunnelKey != null) _config.setTunnelKey(tunnelKey);
    if (backupKey != null) _config.setBackupKey(backupKey);
    if (panelSecret != null) _config.setPanelSecret(panelSecret);
    if (originProxy != null) _config.setOriginProxy(originProxy);
    if (dohEndpoint != null) {
      _config.setDohEndpoint(dohEndpoint);
      _doh.setEndpoint(dohEndpoint);
    }
    if (fallbackWorkers != null) _config.setFallbackWorkers(fallbackWorkers);

    onMessage?.call('Configuration mise à jour');
  }

  // ────────────────────────────────────────────────────────────
  // CONNECT
  // ────────────────────────────────────────────────────────────

  /// Connect to BufferWave VPN
  ///
  /// [killSwitch] — blocks all internet when VPN drops
  /// [stealth]    — enable stealth headers to resist DPI
  /// [doh]        — route DNS via HTTPS instead of UDP
  /// [fragment]   — fragment TLS ClientHello to bypass DPI
  /// [nodeId]     — optional PoP identifier
  /// [userId]     — optional user identifier
  Future<bool> connect({
    bool killSwitch = false,
    bool stealth = false,
    bool doh = true,
    bool fragment = false,
    String? nodeId,
    String? userId,
  }) async {
    if (!_initialized) {
      await initialize();
    }

    if (!_config.isConfigured) {
      onError?.call(
        'Non configuré — appelez configure() avec workerUrl et tunnelKey'
      );
      return false;
    }

    if (_status == ConnectionStatus.connected ||
        _status == ConnectionStatus.connecting) {
      onMessage?.call('Déjà connecté ou en cours');
      return _status == ConnectionStatus.connected;
    }

    _setStatus(ConnectionStatus.connecting);

    try {
      // 1. Resolve user ID
      _userId = userId ?? await _getOrCreateUserId();
      _nodeId = nodeId ?? 'edge';

      // 2. Enable stealth if requested
      if (stealth && !_config.stealthEnabled) {
        _config.enableStealth(profile: StealthProfile.browser);
      }

      // 3. Enable fragment if requested
      if (fragment && !_config.fragmentEnabled) {
        _config.enableFragment();
      }

      // 4. Enable DoH if requested
      if (doh) {
        _doh.enable();
        if (_config.dohEndpoint.isNotEmpty) {
          _doh.setEndpoint(_config.dohEndpoint);
        }
      }

      // 5. Start native VPN via MethodChannel
      final ok = await VpnBridge.startVpn(
        _nodeId,
        _userId,
        killSwitch: killSwitch,
      );

      if (!ok) {
        _setStatus(ConnectionStatus.error);
        onError?.call('Démarrage VPN échoué — permission refusée ?');
        return false;
      }

      // 6. Arm kill switch if requested
      if (killSwitch) {
        _killSwitch.enable(
          onVpnConnected: () {
            onMessage?.call('VPN reconnecté');
          },
          onVpnDisconnected: () {
            onMessage?.call('Kill Switch: trafic bloqué');
            _setStatus(ConnectionStatus.error);
          },
        );
      }

      // 7. Register with Worker (non-blocking)
      _registerAsync();

      // 8. Start heartbeat
      _startHeartbeat();

      _setStatus(ConnectionStatus.connected);
      onMessage?.call(
        'BufferWave connecté via $_nodeId '
        '(stealth=${_config.stealthEnabled}, doh=${_doh.isEnabled})'
      );
      return true;

    } catch (e) {
      _setStatus(ConnectionStatus.error);
      onError?.call('Connexion échouée: $e');
      return false;
    }
  }

  // ────────────────────────────────────────────────────────────
  // DISCONNECT
  // ────────────────────────────────────────────────────────────

  Future<void> disconnect() async {
    _killSwitch.disable();
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    await VpnBridge.stopVpn();

    // Notify Worker (best-effort)
    BufferWaveApi.disconnect(_userId).catchError((_) {});

    _nodeId = '';
    _setStatus(ConnectionStatus.disconnected);
    onMessage?.call('BufferWave déconnecté');
  }

  // ────────────────────────────────────────────────────────────
  // STATUS
  // ────────────────────────────────────────────────────────────

  BufferWaveStatus get status => BufferWaveStatus(
    connection: _status,
    userId: _userId,
    nodeId: _nodeId,
    uptime: VpnBridge.connectionDuration,
    vpnActive: VpnBridge.running,
    killSwitchArmed: _killSwitch.isArmed,
    dohEnabled: _doh.isEnabled,
    stealthEnabled: _config.stealthEnabled,
    fragmentEnabled: _config.fragmentEnabled,
    protocol: 'VLESS',
    workerUrl: BufferWaveApi.baseUrl,
  );

  // ────────────────────────────────────────────────────────────
  // KILL SWITCH TOGGLE
  // ────────────────────────────────────────────────────────────

  void enableKillSwitch() {
    if (!isConnected) return;
    _killSwitch.enable(
      onVpnConnected: () => onMessage?.call('VPN reconnecté'),
      onVpnDisconnected: () {
        onMessage?.call('Kill Switch: trafic bloqué');
        _setStatus(ConnectionStatus.error);
      },
    );
    onMessage?.call('Kill Switch armé');
  }

  void disableKillSwitch() {
    _killSwitch.disable();
    onMessage?.call('Kill Switch désarmé');
  }

  // ────────────────────────────────────────────────────────────
  // STEALTH TOGGLE
  // ────────────────────────────────────────────────────────────

  void enableStealth({StealthProfile profile = StealthProfile.browser}) {
    _config.enableStealth(profile: profile);
    onMessage?.call('Stealth activé (${profile.name})');
  }

  void disableStealth() {
    _config.disableStealth();
    onMessage?.call('Stealth désactivé');
  }

  // ────────────────────────────────────────────────────────────
  // FRAGMENT TLS TOGGLE
  // ────────────────────────────────────────────────────────────

  void enableFragment({
    int minDelay = 10,
    int maxDelay = 100,
    int minSize = 10,
    int maxSize = 50,
  }) {
    _config.enableFragment(
      minDelay: minDelay,
      maxDelay: maxDelay,
      minSize: minSize,
      maxSize: maxSize,
    );
    onMessage?.call('Fragment TLS activé ($minDelay-${maxDelay}ms)');
  }

  void disableFragment() {
    _config.disableFragment();
    onMessage?.call('Fragment TLS désactivé');
  }

  // ────────────────────────────────────────────────────────────
  // DoH TOGGLE
  // ────────────────────────────────────────────────────────────

  void enableDoh({String? endpoint}) {
    if (endpoint != null) {
      _doh.setEndpoint(endpoint);
    }
    _doh.enable();
    onMessage?.call('DoH activé');
  }

  void disableDoh() {
    _doh.disable();
    onMessage?.call('DoH désactivé');
  }

  // ────────────────────────────────────────────────────────────
  // SERVER NODES
  // ────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getNodes() =>
      BufferWaveApi.getCloudflareNodes();

  // ────────────────────────────────────────────────────────────
  // KEY MANAGEMENT
  // ────────────────────────────────────────────────────────────

  /// Génère une nouvelle clé tunnel aléatoire (UUID v4)
  String generateNewKey() => TunnelConfig.generateKey();

  /// Rotation de clé : déplace la clé actuelle en backup
  /// et active la nouvelle
  void rotateKey() {
    final currentKey = _config.tunnelKey;
    final newKey = generateNewKey();
    _config.setBackupKey(currentKey);
    _config.setTunnelKey(newKey);
    onMessage?.call('Clé tunnel rotée — mettre à jour le Worker');
  }

  // ────────────────────────────────────────────────────────────
  // DIAGNOSTICS
  // ────────────────────────────────────────────────────────────

  /// Retourne un snapshot complet pour debug
  Map<String, dynamic> diagnostics() => {
    'status': status.toJson(),
    'config': _config.toJson(),
    'doh': _doh.getStats(),
    'killSwitch': {
      'armed': _killSwitch.isArmed,
      'disconnectCount': _killSwitch.disconnectCount,
      'lastTrigger': _killSwitch.lastTrigger?.toIso8601String(),
    },
    'version': '12.0.0',
    'build': 'production',
  };

  // ────────────────────────────────────────────────────────────
  // INTERNAL
  // ────────────────────────────────────────────────────────────

  void _setStatus(ConnectionStatus s) {
    _status = s;
    onStatusChanged?.call(s);
  }

  void _registerAsync() {
    BufferWaveApi.registerNode(
      userId: _userId,
      country: 'AUTO',
      bandwidthMbps: 5,
    ).catchError((_) {});
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_status == ConnectionStatus.connected) {
        BufferWaveApi.heartbeat(_userId).catchError((_) {});
      }
    });
  }

  Future<String> _getOrCreateUserId() async {
    final p = await SharedPreferences.getInstance();
    var uid = p.getString('bw_user_id');
    if (uid == null) {
      uid = 'bw_${DateTime.now().millisecondsSinceEpoch}';
      await p.setString('bw_user_id', uid);
    }
    return uid;
  }

  void dispose() {
    disconnect();
    _doh.dispose();
    _config.dispose();
  }
}
