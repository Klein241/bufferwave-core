import 'dart:async';
import 'dart:math';

/// ════════════════════════════════════════════════════════════════
/// PathSelector — Sélection adaptative du meilleur chemin réseau
///
/// Inspiré de l'architecture multi-path des réseaux overlay :
///   - Mesure la latence de chaque endpoint
///   - Classement dynamique par qualité (RTT + fiabilité)
///   - Fallback automatique si le meilleur chemin tombe
///   - Détection de throttle réseau (bascule mode éco)
///   - Probing périodique pour réévaluer les chemins
///
/// Niveaux de chemin (priorité décroissante) :
///   1. WiFi Direct   — 0 Mo data, latence ~5ms
///   2. LAN Direct    — 0 Mo data, latence ~10ms
///   3. Edge Relay    — Data minimale, latence ~50-200ms
///   4. Multi-hop     — Fallback, latence ~200-500ms
///
/// Réutilisable dans tout projet nécessitant un path selection.
///
/// Usage :
///   final selector = PathSelector();
///   selector.addPath(PathInfo(
///     id: 'edge-eu',
///     endpoint: 'wss://relay-eu.example.com/tunnel',
///     type: PathType.edgeRelay,
///   ));
///   selector.addPath(PathInfo(
///     id: 'lan',
///     endpoint: 'ws://192.168.1.50:8899',
///     type: PathType.lanDirect,
///   ));
///   await selector.probeAll();
///   final best = selector.bestPath;
///
/// Multi-region merge pattern :
///   selector.addPaths([
///     PathInfo(id: 'eu-1', endpoint: 'wss://eu.relay.com', type: PathType.edgeRelay),
///     PathInfo(id: 'us-1', endpoint: 'wss://us.relay.com', type: PathType.edgeRelay),
///   ]);
///   selector.shuffleSameType(PathType.edgeRelay);
/// ════════════════════════════════════════════════════════════════

/// Types de chemins réseau.
enum PathType {
  /// Connexion WiFi P2P directe (aucune data mobile consommée).
  wifiDirect,

  /// Connexion LAN directe (même réseau WiFi ou hotspot).
  lanDirect,

  /// Relay via serveur edge (Cloudflare Worker ou similaire).
  edgeRelay,

  /// Multi-hop via plusieurs relays en cascade.
  multiHop,

  /// Aucun chemin disponible.
  none,
}

/// Informations sur un chemin réseau.
class PathInfo {
  /// Identifiant unique du chemin.
  final String id;

  /// URL de l'endpoint.
  final String endpoint;

  /// Type de chemin.
  final PathType type;

  /// Latence mesurée en ms (-1 = non mesuré).
  double rttMs;

  /// Nombre d'échecs consécutifs.
  int failCount;

  /// Nombre total de connexions réussies.
  int successCount;

  /// Dernière vérification.
  DateTime lastProbe;

  /// Est-ce que ce chemin est actuellement actif ?
  bool isActive;

  /// Priorité manuelle (0 = auto).
  int priority;

  PathInfo({
    required this.id,
    required this.endpoint,
    required this.type,
    this.rttMs = -1,
    this.failCount = 0,
    this.successCount = 0,
    this.priority = 0,
  })  : lastProbe = DateTime.fromMillisecondsSinceEpoch(0),
        isActive = false;

  /// Score de qualité (plus bas = meilleur).
  /// Combine la priorité du type, le RTT, et la fiabilité.
  double get qualityScore {
    // Base : priorité du type de chemin
    double base;
    switch (type) {
      case PathType.wifiDirect:
        base = 10;
        break;
      case PathType.lanDirect:
        base = 20;
        break;
      case PathType.edgeRelay:
        base = 50;
        break;
      case PathType.multiHop:
        base = 100;
        break;
      case PathType.none:
        base = 9999;
        break;
    }

    // Ajuster avec le RTT mesuré
    if (rttMs > 0) {
      base += rttMs * 0.5;
    } else {
      base += 500; // Pénalité si non mesuré
    }

    // Pénalité pour échecs successifs
    base += failCount * 50;

    // Bonus pour fiabilité prouvée
    if (successCount > 0) {
      base -= min(successCount * 5.0, 50);
    }

    // Priorité manuelle
    if (priority != 0) {
      base += priority;
    }

    return base;
  }

  @override
  String toString() =>
      'PathInfo($id, $type, rtt=${rttMs.toStringAsFixed(1)}ms, '
      'score=${qualityScore.toStringAsFixed(1)})';
}

/// Sélecteur de chemin adaptatif.
class PathSelector {
  final List<PathInfo> _paths = [];
  Timer? _probeTimer;

  /// Callback pour mesurer la latence d'un endpoint.
  /// Retourne le RTT en ms, ou -1 si inaccessible.
  Future<double> Function(String endpoint)? measureLatency;

  /// Callback quand le meilleur chemin change.
  void Function(PathInfo? newBest, PathInfo? oldBest)? onPathChanged;

  /// Callback pour chaque résultat de probe.
  void Function(PathInfo path, bool success, double rttMs)? onProbeResult;

  /// Seuil de RTT pour activer le mode éco (ms).
  double throttleThresholdMs;

  /// Callback quand le throttle est détecté.
  void Function(bool isThrottled)? onThrottleDetected;

  PathInfo? _currentBest;

  PathSelector({
    this.throttleThresholdMs = 600,
  });

  // ─── Getters ───
  List<PathInfo> get paths => List.unmodifiable(_paths);
  PathInfo? get bestPath => _currentBest;
  bool get hasAvailablePaths => _paths.any((p) => p.rttMs > 0);

  // ═══════════════════════════════════════════
  // PATH MANAGEMENT
  // ═══════════════════════════════════════════

  /// Ajoute un chemin possible.
  void addPath(PathInfo path) {
    _paths.add(path);
  }

  /// Supprime un chemin par ID.
  void removePath(String id) {
    _paths.removeWhere((p) => p.id == id);
  }

  /// Supprime tous les chemins.
  void clearPaths() {
    _paths.clear();
    _currentBest = null;
  }

  /// Ajoute plusieurs chemins d'un coup.
  void addPaths(List<PathInfo> paths) {
    _paths.addAll(paths);
  }

  /// Mélange les chemins du même type (inspiré shuffleRegion).
  /// Empêche que tous les clients se connectent au même serveur.
  void shuffleSameType(PathType type) {
    final same = _paths.where((p) => p.type == type).toList();
    if (same.length <= 1) return;
    final rng = Random();
    for (var i = same.length - 1; i > 0; i--) {
      final j = rng.nextInt(i + 1);
      final indexI = _paths.indexOf(same[i]);
      final indexJ = _paths.indexOf(same[j]);
      final tmp = _paths[indexI];
      _paths[indexI] = _paths[indexJ];
      _paths[indexJ] = tmp;
    }
  }

  /// Enregistre un résultat de connexion pour un chemin.
  void recordSuccess(String pathId, double rttMs) {
    final path = _paths.firstWhere(
      (p) => p.id == pathId,
      orElse: () => PathInfo(id: '', endpoint: '', type: PathType.none),
    );
    if (path.id.isEmpty) return;

    path.rttMs = rttMs;
    path.failCount = 0;
    path.successCount++;
    path.lastProbe = DateTime.now();
    onProbeResult?.call(path, true, rttMs);
    _evaluate();
  }

  /// Enregistre un échec pour un chemin.
  void recordFailure(String pathId) {
    final path = _paths.firstWhere(
      (p) => p.id == pathId,
      orElse: () => PathInfo(id: '', endpoint: '', type: PathType.none),
    );
    if (path.id.isEmpty) return;

    path.failCount++;
    path.rttMs = -1;
    path.lastProbe = DateTime.now();
    onProbeResult?.call(path, false, -1);
    _evaluate();
  }

  // ═══════════════════════════════════════════
  // PROBING — Mesure des latences
  // ═══════════════════════════════════════════

  /// Probe tous les chemins et sélectionne le meilleur.
  Future<PathInfo?> probeAll() async {
    if (measureLatency == null) return _currentBest;

    final futures = _paths.map((path) async {
      try {
        final rtt = await measureLatency!(path.endpoint)
            .timeout(const Duration(seconds: 5), onTimeout: () => -1);
        if (rtt > 0) {
          path.rttMs = rtt;
          path.failCount = 0;
          path.successCount++;
        } else {
          path.failCount++;
          path.rttMs = -1;
        }
      } catch (_) {
        path.failCount++;
        path.rttMs = -1;
      }
      path.lastProbe = DateTime.now();
    });

    await Future.wait(futures);
    _evaluate();
    return _currentBest;
  }

  /// Démarre le probing périodique.
  void startPeriodicProbe({Duration interval = const Duration(seconds: 60)}) {
    _probeTimer?.cancel();
    _probeTimer = Timer.periodic(interval, (_) => probeAll());
  }

  /// Arrête le probing périodique.
  void stopPeriodicProbe() {
    _probeTimer?.cancel();
    _probeTimer = null;
  }

  // ═══════════════════════════════════════════
  // EVALUATION — Sélection du meilleur chemin
  // ═══════════════════════════════════════════

  void _evaluate() {
    final available = _paths.where((p) => p.rttMs > 0 || p.failCount == 0).toList()
      ..sort((a, b) => a.qualityScore.compareTo(b.qualityScore));

    final newBest = available.isNotEmpty ? available.first : null;
    final oldBest = _currentBest;

    if (newBest?.id != oldBest?.id) {
      _currentBest = newBest;
      onPathChanged?.call(newBest, oldBest);
    }

    // Détection de throttle
    if (newBest != null && newBest.rttMs > throttleThresholdMs) {
      onThrottleDetected?.call(true);
    } else if (newBest != null && newBest.rttMs > 0 &&
        newBest.rttMs < throttleThresholdMs * 0.5) {
      onThrottleDetected?.call(false);
    }
  }

  /// Retourne les chemins triés par qualité.
  List<PathInfo> sortedPaths() {
    return List<PathInfo>.from(_paths)
      ..sort((a, b) => a.qualityScore.compareTo(b.qualityScore));
  }

  // ═══════════════════════════════════════════
  // DISPOSE
  // ═══════════════════════════════════════════

  void dispose() {
    _probeTimer?.cancel();
    _paths.clear();
    onPathChanged = null;
    onThrottleDetected = null;
    onProbeResult = null;
    measureLatency = null;
  }
}
