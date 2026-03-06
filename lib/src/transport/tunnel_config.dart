import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

/// ════════════════════════════════════════════════════════════════
/// BufferWave Core — Tunnel Configuration & Stealth
///
/// Gère toute la configuration du tunnel :
///   - Clés d'authentification (rotatable)
///   - Endpoints (Worker principal + fallback)
///   - Mode stealth (obfuscation du trafic)
///   - Fragment TLS settings
///   - Origin proxy fallback
///
/// Aucune clé n'est hardcodée. Tout est configurable et
/// persisté en SharedPreferences chiffré.
///
/// Usage :
///   final cfg = TunnelConfig();
///   await cfg.load();
///   cfg.setTunnelKey('mon-uuid-unique');
///   cfg.setWorkerUrl('https://myworker.example.com');
///   cfg.enableFragment(minDelay: 50, maxDelay: 200);
/// ════════════════════════════════════════════════════════════════

class TunnelConfig {
  // ─── Singleton ───
  static final TunnelConfig _instance = TunnelConfig._();
  factory TunnelConfig() => _instance;
  TunnelConfig._();

  // ─── Auth ───
  String _tunnelKey = '';
  String _backupKey = '';
  String _panelSecret = '';

  // ─── Endpoints ───
  String _workerUrl = '';
  String _dohEndpoint = '';
  String _originProxy = '';
  List<String> _fallbackWorkers = [];

  // ─── Stealth ───
  bool _stealthEnabled = false;
  StealthProfile _stealthProfile = StealthProfile.standard;

  // ─── Fragment ───
  bool _fragmentEnabled = false;
  int _fragmentMinDelay = 10;   // ms
  int _fragmentMaxDelay = 100;  // ms
  int _fragmentMinSize = 10;    // bytes
  int _fragmentMaxSize = 50;    // bytes

  // ─── WebSocket ───
  String _wsPath = '/tunnel';
  Map<String, String> _customHeaders = {};

  bool _loaded = false;

  // ─── Getters ───
  String get tunnelKey => _tunnelKey;
  String get backupKey => _backupKey;
  String get panelSecret => _panelSecret;
  String get workerUrl => _workerUrl;
  String get dohEndpoint => _dohEndpoint;
  String get originProxy => _originProxy;
  List<String> get fallbackWorkers => List.from(_fallbackWorkers);
  bool get stealthEnabled => _stealthEnabled;
  StealthProfile get stealthProfile => _stealthProfile;
  bool get fragmentEnabled => _fragmentEnabled;
  int get fragmentMinDelay => _fragmentMinDelay;
  int get fragmentMaxDelay => _fragmentMaxDelay;
  int get fragmentMinSize => _fragmentMinSize;
  int get fragmentMaxSize => _fragmentMaxSize;
  String get wsPath => _wsPath;
  Map<String, String> get customHeaders => Map.from(_customHeaders);
  bool get isConfigured => _tunnelKey.isNotEmpty && _workerUrl.isNotEmpty;

  /// URL WebSocket complète
  String get wsUrl {
    if (_workerUrl.isEmpty) return '';
    final scheme = _workerUrl.startsWith('https') ? 'wss' : 'ws';
    final host = _workerUrl
        .replaceFirst('https://', '')
        .replaceFirst('http://', '');
    return '$scheme://$host$_wsPath';
  }

  // ═══════════════════════════════════════════
  // CONFIGURATION
  // ═══════════════════════════════════════════

  void setTunnelKey(String key) {
    _tunnelKey = key.trim();
    _save();
  }

  void setBackupKey(String key) {
    _backupKey = key.trim();
    _save();
  }

  void setPanelSecret(String secret) {
    _panelSecret = secret.trim();
    _save();
  }

  void setWorkerUrl(String url) {
    _workerUrl = url.trim();
    if (_workerUrl.endsWith('/')) {
      _workerUrl = _workerUrl.substring(0, _workerUrl.length - 1);
    }
    // Auto-configure DoH endpoint
    if (_dohEndpoint.isEmpty && _workerUrl.isNotEmpty) {
      _dohEndpoint = '$_workerUrl/resolve';
    }
    _save();
  }

  void setDohEndpoint(String url) {
    _dohEndpoint = url.trim();
    _save();
  }

  void setOriginProxy(String hostPort) {
    _originProxy = hostPort.trim();
    _save();
  }

  void setFallbackWorkers(List<String> urls) {
    _fallbackWorkers = urls.map((u) => u.trim()).toList();
    _save();
  }

  void setWsPath(String path) {
    _wsPath = path.startsWith('/') ? path : '/$path';
    _save();
  }

  void setCustomHeaders(Map<String, String> headers) {
    _customHeaders = Map.from(headers);
    _save();
  }

  // ═══════════════════════════════════════════
  // STEALTH
  // ═══════════════════════════════════════════

  void enableStealth({StealthProfile profile = StealthProfile.standard}) {
    _stealthEnabled = true;
    _stealthProfile = profile;
    _applyStealthProfile(profile);
    _save();
  }

  void disableStealth() {
    _stealthEnabled = false;
    _customHeaders.clear();
    _save();
  }

  void _applyStealthProfile(StealthProfile profile) {
    switch (profile) {
      case StealthProfile.standard:
        _customHeaders = {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
              'AppleWebKit/537.36 (KHTML, like Gecko) '
              'Chrome/120.0.0.0 Safari/537.36',
          'Accept-Language': 'fr-FR,fr;q=0.9,en-US;q=0.8',
          'Accept-Encoding': 'gzip, deflate, br',
        };
        break;

      case StealthProfile.browser:
        _customHeaders = {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 14; SM-A546E) '
              'AppleWebKit/537.36 (KHTML, like Gecko) '
              'Chrome/120.0.6099.280 Mobile Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9',
          'Accept-Language': 'fr-CM,fr;q=0.9',
          'Accept-Encoding': 'gzip, deflate, br',
          'Sec-Fetch-Dest': 'document',
          'Sec-Fetch-Mode': 'navigate',
          'Sec-Fetch-Site': 'none',
        };
        break;

      case StealthProfile.cdn:
        _customHeaders = {
          'User-Agent': 'CDN-Cache/2.1',
          'Accept': '*/*',
          'Cache-Control': 'no-cache',
        };
        break;

      case StealthProfile.minimal:
        _customHeaders = {};
        break;
    }
  }

  // ═══════════════════════════════════════════
  // FRAGMENT
  // ═══════════════════════════════════════════

  void enableFragment({
    int minDelay = 10,
    int maxDelay = 100,
    int minSize = 10,
    int maxSize = 50,
  }) {
    _fragmentEnabled = true;
    _fragmentMinDelay = minDelay;
    _fragmentMaxDelay = maxDelay;
    _fragmentMinSize = minSize;
    _fragmentMaxSize = maxSize;
    _save();
  }

  void disableFragment() {
    _fragmentEnabled = false;
    _save();
  }

  /// Génère un délai aléatoire dans la plage configurée
  int randomFragmentDelay() {
    if (!_fragmentEnabled) return 0;
    final rng = Random();
    return _fragmentMinDelay +
        rng.nextInt(_fragmentMaxDelay - _fragmentMinDelay + 1);
  }

  /// Génère une taille de fragment aléatoire
  int randomFragmentSize() {
    if (!_fragmentEnabled) return 0;
    final rng = Random();
    return _fragmentMinSize +
        rng.nextInt(_fragmentMaxSize - _fragmentMinSize + 1);
  }

  // ═══════════════════════════════════════════
  // KEY GENERATION
  // ═══════════════════════════════════════════

  /// Génère une clé tunnel aléatoire (format UUID v4)
  static String generateKey() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));

    // UUID v4 format
    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    bytes[8] = (bytes[8] & 0x3F) | 0x80;

    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-'
        '${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }

  // ═══════════════════════════════════════════
  // PERSISTENCE
  // ═══════════════════════════════════════════

  Future<void> load() async {
    if (_loaded) return;
    final p = await SharedPreferences.getInstance();

    _tunnelKey = p.getString('bw_tunnel_key') ?? '';
    _backupKey = p.getString('bw_backup_key') ?? '';
    _panelSecret = p.getString('bw_panel_secret') ?? '';
    _workerUrl = p.getString('bw_worker_url') ?? '';
    _dohEndpoint = p.getString('bw_doh_endpoint') ?? '';
    _originProxy = p.getString('bw_origin_proxy') ?? '';
    _wsPath = p.getString('bw_ws_path') ?? '/tunnel';

    final fallbacks = p.getStringList('bw_fallback_workers');
    _fallbackWorkers = fallbacks ?? [];

    _stealthEnabled = p.getBool('bw_stealth') ?? false;
    final profileName = p.getString('bw_stealth_profile') ?? 'standard';
    _stealthProfile = StealthProfile.values.firstWhere(
      (v) => v.name == profileName,
      orElse: () => StealthProfile.standard,
    );
    if (_stealthEnabled) {
      _applyStealthProfile(_stealthProfile);
    }

    _fragmentEnabled = p.getBool('bw_fragment') ?? false;
    _fragmentMinDelay = p.getInt('bw_frag_min_delay') ?? 10;
    _fragmentMaxDelay = p.getInt('bw_frag_max_delay') ?? 100;
    _fragmentMinSize = p.getInt('bw_frag_min_size') ?? 10;
    _fragmentMaxSize = p.getInt('bw_frag_max_size') ?? 50;

    final headersJson = p.getString('bw_custom_headers');
    if (headersJson != null) {
      _customHeaders = Map<String, String>.from(json.decode(headersJson));
    }

    _loaded = true;
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('bw_tunnel_key', _tunnelKey);
    await p.setString('bw_backup_key', _backupKey);
    await p.setString('bw_panel_secret', _panelSecret);
    await p.setString('bw_worker_url', _workerUrl);
    await p.setString('bw_doh_endpoint', _dohEndpoint);
    await p.setString('bw_origin_proxy', _originProxy);
    await p.setString('bw_ws_path', _wsPath);
    await p.setStringList('bw_fallback_workers', _fallbackWorkers);
    await p.setBool('bw_stealth', _stealthEnabled);
    await p.setString('bw_stealth_profile', _stealthProfile.name);
    await p.setBool('bw_fragment', _fragmentEnabled);
    await p.setInt('bw_frag_min_delay', _fragmentMinDelay);
    await p.setInt('bw_frag_max_delay', _fragmentMaxDelay);
    await p.setInt('bw_frag_min_size', _fragmentMinSize);
    await p.setInt('bw_frag_max_size', _fragmentMaxSize);
    await p.setString('bw_custom_headers', json.encode(_customHeaders));
  }

  /// Export complet de la config (pour debug/backup)
  Map<String, dynamic> toJson() => {
    'tunnelKey': _tunnelKey.isNotEmpty ? '***configured***' : 'not_set',
    'workerUrl': _workerUrl,
    'dohEndpoint': _dohEndpoint,
    'originProxy': _originProxy,
    'fallbackWorkers': _fallbackWorkers,
    'stealthEnabled': _stealthEnabled,
    'stealthProfile': _stealthProfile.name,
    'fragmentEnabled': _fragmentEnabled,
    'fragmentDelay': '$_fragmentMinDelay-$_fragmentMaxDelay ms',
    'fragmentSize': '$_fragmentMinSize-$_fragmentMaxSize bytes',
    'wsPath': _wsPath,
    'configured': isConfigured,
  };

  void dispose() {
    // Nothing to dispose
  }
}

/// Profils de camouflage pour le trafic sortant
enum StealthProfile {
  /// Headers Chrome desktop classiques
  standard,

  /// Simule un navigateur mobile Android
  browser,

  /// Simule un CDN/cache
  cdn,

  /// Aucun header supplémentaire
  minimal,
}
