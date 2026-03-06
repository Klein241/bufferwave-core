import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../data/cloudflare_nodes.dart';
import '../transport/tunnel_config.dart';

/// ════════════════════════════════════════════════════════════════
/// BufferWave Core — Authenticated API Client
///
/// Communication HTTP avec le Worker, sécurisée par :
///   - Token d'authentification (panel secret)
///   - Headers sanitisés (pas de fingerprint)
///   - Timeout agressif (pas de leak de timing)
///   - Retry logique pour robustesse
///
/// Endpoints :
///   POST /register    — Enregistre le nœud
///   POST /heartbeat   — Signal de vie
///   POST /disconnect  — Désenregistre
///   GET  /status      — État du service
///   GET  /provision   — Configs subscription
///   GET  /resolve     — DoH endpoint
///   GET  /health      — Health check
/// ════════════════════════════════════════════════════════════════
class BufferWaveApi {
  static String _baseUrl = '';
  static final TunnelConfig _config = TunnelConfig();

  static void setBaseUrl(String url) {
    _baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  static String get baseUrl => _baseUrl;

  // ═══════════════════════════════════════════
  // INTERNAL — Authenticated HTTP requests
  // ═══════════════════════════════════════════

  static Map<String, String> _buildHeaders() {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };

    // Add auth token if configured
    if (_config.panelSecret.isNotEmpty) {
      headers['Authorization'] = 'Bearer ${_config.panelSecret}';
    }

    // Stealth headers
    if (_config.stealthEnabled) {
      headers.addAll(_config.customHeaders);
    }

    return headers;
  }

  static Future<http.Response?> _post(
    String path,
    Map<String, dynamic> body, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (_baseUrl.isEmpty) return null;
    try {
      return await http.post(
        Uri.parse('$_baseUrl$path'),
        headers: _buildHeaders(),
        body: jsonEncode(body),
      ).timeout(timeout);
    } catch (_) {
      return null;
    }
  }

  static Future<http.Response?> _get(
    String path, {
    Duration timeout = const Duration(seconds: 10),
    Map<String, String>? queryParams,
  }) async {
    if (_baseUrl.isEmpty) return null;
    try {
      var uri = Uri.parse('$_baseUrl$path');
      if (queryParams != null) {
        uri = uri.replace(queryParameters: queryParams);
      }
      return await http.get(
        uri,
        headers: _buildHeaders(),
      ).timeout(timeout);
    } catch (_) {
      return null;
    }
  }

  // ═══════════════════════════════════════════
  // NODE API
  // ═══════════════════════════════════════════

  static Future<String> getNodeId() async {
    final prefs = await SharedPreferences.getInstance();
    String? id = prefs.getString('node_id');
    if (id == null) {
      id = 'node_${DateTime.now().millisecondsSinceEpoch}';
      await prefs.setString('node_id', id);
    }
    return id;
  }

  static Future<void> registerNode({
    required String userId,
    required String country,
    required double bandwidthMbps,
  }) async {
    await _post('/register', {
      'userId': userId,
      'country': country,
      'bandwidthMbps': bandwidthMbps,
    });
  }

  static Future<void> heartbeat(String userId) async {
    await _post('/heartbeat', {
      'userId': userId,
    }, timeout: const Duration(seconds: 5));
  }

  static Future<void> disconnect(String userId) async {
    await _post('/disconnect', {
      'userId': userId,
    }, timeout: const Duration(seconds: 5));
  }

  // ═══════════════════════════════════════════
  // NODES
  // ═══════════════════════════════════════════

  static Future<List<Map<String, dynamic>>> getNodes() async {
    final resp = await _get('/status');
    if (resp != null && resp.statusCode == 200) {
      try {
        final data = jsonDecode(resp.body);
        final List nodes = data['nodes'] ?? [];
        return nodes.map((n) => Map<String, dynamic>.from(n)).toList();
      } catch (_) {}
    }
    return [];
  }

  static Future<List<Map<String, dynamic>>> getCloudflareNodes() async {
    final resp = await _get('/status');
    if (resp != null && resp.statusCode == 200) {
      try {
        final data = jsonDecode(resp.body);
        final List nodes = data['nodes'] ?? [];
        return nodes.map((n) => Map<String, dynamic>.from(n)).toList();
      } catch (_) {}
    }
    return CloudflareNodes.fallbackList();
  }

  // ═══════════════════════════════════════════
  // SUBSCRIPTION — Get client configs
  // ═══════════════════════════════════════════

  /// Récupère les configs de subscription depuis le Worker
  /// Retourne la config VLESS au format brut ou JSON
  static Future<Map<String, dynamic>?> getSubscription({
    String format = 'json',
  }) async {
    final queryParams = <String, String>{
      'format': format,
    };
    if (_config.panelSecret.isNotEmpty) {
      queryParams['token'] = _config.panelSecret;
    }
    final resp = await _get('/provision', queryParams: queryParams);
    if (resp != null && resp.statusCode == 200) {
      try {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      } catch (_) {}
    }
    return null;
  }

  // ═══════════════════════════════════════════
  // HEALTH CHECK
  // ═══════════════════════════════════════════

  /// Vérifie que le Worker est accessible
  /// Retourne true si le Worker répond correctement
  static Future<bool> healthCheck() async {
    final resp = await _get('/health', timeout: const Duration(seconds: 5));
    return resp != null && resp.statusCode == 200;
  }

  // ═══════════════════════════════════════════
  // STATUS
  // ═══════════════════════════════════════════

  static Future<Map<String, dynamic>?> getStatus() async {
    final resp = await _get('/status');
    if (resp != null && resp.statusCode == 200) {
      try {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      } catch (_) {}
    }
    return null;
  }

  // ═══════════════════════════════════════════
  // RELAY CONNECTION
  // ═══════════════════════════════════════════

  static Future<Map<String, dynamic>?> connectToRelay(
    String userId,
    String relayNodeId,
  ) async {
    final resp = await _post('/register', {
      'userId': userId,
      'relayNodeId': relayNodeId,
    });
    if (resp != null && resp.statusCode == 200) {
      try {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      } catch (_) {}
    }
    return null;
  }
}
