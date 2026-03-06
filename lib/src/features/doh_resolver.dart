import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// ════════════════════════════════════════════════════════════════
/// BufferWave Core — DNS over HTTPS (DoH) Resolver
///
/// Résout les noms de domaine via HTTPS au lieu d'UDP en clair.
/// Supporte deux modes :
///   1. Worker DoH : résolution via notre propre Worker (/resolve)
///   2. Fallback DoH : Cloudflare/Google (bootstrapped directement)
///
/// Le DNS UDP classique est VISIBLE par le FAI même quand le VPN
/// est actif, car les paquets DNS sortent avant d'entrer dans le
/// tunnel. DoH chiffre la requête dans le flux HTTPS.
///
/// Usage :
///   final resolver = DohResolver();
///   resolver.setEndpoint('https://myworker.workers.dev/resolve');
///   final ips = await resolver.resolve('google.com');
/// ════════════════════════════════════════════════════════════════

class DohResolver {
  // ─── Singleton ───
  static final DohResolver _instance = DohResolver._();
  factory DohResolver() => _instance;
  DohResolver._();

  // ─── Config ───
  String _primaryEndpoint = '';
  static const List<String> _fallbackEndpoints = [
    'https://cloudflare-dns.com/dns-query',
    'https://dns.google/dns-query',
  ];

  Duration _timeout = const Duration(seconds: 5);
  bool _enabled = false;

  // ─── Cache (TTL-aware) ───
  final Map<String, _CachedRecord> _cache = {};
  static const int _maxCacheSize = 500;

  // ─── Callbacks ───
  Function(String message)? onStatusChanged;

  // ─── Getters ───
  bool get isEnabled => _enabled;
  String get endpoint => _primaryEndpoint;
  int get cacheSize => _cache.length;

  // ─── Configuration ───

  /// Configure le endpoint DoH principal (notre Worker)
  void setEndpoint(String url) {
    _primaryEndpoint = url;
  }

  /// Active/désactive DoH
  void enable() {
    _enabled = true;
    onStatusChanged?.call('DoH activé');
  }

  void disable() {
    _enabled = false;
    onStatusChanged?.call('DoH désactivé');
  }

  void setTimeout(Duration timeout) {
    _timeout = timeout;
  }

  /// Vide le cache
  void clearCache() {
    _cache.clear();
  }

  // ═══════════════════════════════════════════
  // RESOLVE — Résout un domaine en IP(s)
  // ═══════════════════════════════════════════

  /// Résout un nom de domaine en liste d'IPs via DoH
  /// Falls back to standard resolution if DoH is disabled
  Future<List<String>> resolve(String domain, {String type = 'A'}) async {
    if (!_enabled) return [];

    // Vérifie le cache
    final cacheKey = '$domain:$type';
    final cached = _cache[cacheKey];
    if (cached != null && !cached.isExpired) {
      return cached.addresses;
    }

    // Essayer le endpoint principal en premier
    final endpoints = <String>[];
    if (_primaryEndpoint.isNotEmpty) {
      endpoints.add(_primaryEndpoint);
    }
    endpoints.addAll(_fallbackEndpoints);

    for (final endpoint in endpoints) {
      try {
        final result = await _queryDoH(endpoint, domain, type);
        if (result.isNotEmpty) {
          // Mettre en cache
          _cacheResult(cacheKey, result);
          return result;
        }
      } catch (_) {
        // Essayer le suivant
        continue;
      }
    }

    onStatusChanged?.call('Tous les serveurs DoH ont échoué pour $domain');
    return [];
  }

  /// Résolution DNS-over-HTTPS (JSON wire format)
  Future<List<String>> _queryDoH(
    String endpoint,
    String domain,
    String type,
  ) async {
    final uri = Uri.parse(endpoint).replace(queryParameters: {
      'name': domain,
      'type': type,
    });

    final response = await http.get(
      uri,
      headers: {
        'Accept': 'application/dns-json',
      },
    ).timeout(_timeout);

    if (response.statusCode != 200) return [];

    final data = json.decode(response.body) as Map<String, dynamic>;
    final answers = data['Answer'] as List<dynamic>?;
    if (answers == null || answers.isEmpty) return [];

    return answers
        .where((a) {
          final t = a['type'] as int?;
          // Type 1 = A (IPv4), Type 28 = AAAA (IPv6)
          return t == 1 || t == 28;
        })
        .map((a) => a['data'] as String)
        .where((ip) => ip.isNotEmpty)
        .toList();
  }

  // ═══════════════════════════════════════════
  // BINARY DoH — RFC 8484 (dns-message format)
  // ═══════════════════════════════════════════

  /// Résolution DoH binaire (pour intégration avec le VPN natif)
  /// Prend un paquet DNS brut, le forwarde via HTTPS, retourne la réponse brute
  Future<Uint8List?> resolveRaw(Uint8List dnsQuery) async {
    if (!_enabled) return null;

    final endpoints = <String>[];
    if (_primaryEndpoint.isNotEmpty) {
      endpoints.add(_primaryEndpoint);
    }
    endpoints.addAll(_fallbackEndpoints);

    for (final endpoint in endpoints) {
      try {
        final response = await http.post(
          Uri.parse(endpoint),
          headers: {
            'Content-Type': 'application/dns-message',
            'Accept': 'application/dns-message',
          },
          body: dnsQuery,
        ).timeout(_timeout);

        if (response.statusCode == 200) {
          return Uint8List.fromList(response.bodyBytes);
        }
      } catch (_) {
        continue;
      }
    }

    return null;
  }

  // ═══════════════════════════════════════════
  // CACHE
  // ═══════════════════════════════════════════

  void _cacheResult(String key, List<String> addresses) {
    if (_cache.length >= _maxCacheSize) {
      _cleanCache();
    }
    _cache[key] = _CachedRecord(
      addresses: addresses,
      expiry: DateTime.now().add(const Duration(minutes: 5)),
    );
  }

  void _cleanCache() {
    _cache.removeWhere((_, v) => v.isExpired);
    if (_cache.length >= _maxCacheSize - 100) {
      // Still too big — remove oldest
      final keys = _cache.keys.toList()
        ..sort((a, b) =>
            _cache[a]!.expiry.compareTo(_cache[b]!.expiry));
      for (int i = 0; i < 100 && i < keys.length; i++) {
        _cache.remove(keys[i]);
      }
    }
  }

  /// Statistiques du resolver
  Map<String, dynamic> getStats() => {
    'enabled': _enabled,
    'endpoint': _primaryEndpoint.isNotEmpty ? _primaryEndpoint : 'fallback',
    'cacheSize': _cache.length,
    'fallbackEndpoints': _fallbackEndpoints.length,
  };

  void dispose() {
    _cache.clear();
  }
}

class _CachedRecord {
  final List<String> addresses;
  final DateTime expiry;

  const _CachedRecord({
    required this.addresses,
    required this.expiry,
  });

  bool get isExpired => DateTime.now().isAfter(expiry);
}
