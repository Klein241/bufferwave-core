import 'dart:async';
import 'dart:collection';

/// ════════════════════════════════════════════════════════════════
/// ConnectionTable — Suivi NAT-like des connexions TCP/UDP
///
/// Inspiré des tables NAT des réseaux overlay et des reverse proxies :
///   - Chaque connexion est identifiée par un tuple (proto, srcPort, dstIP, dstPort)
///   - ID court (16 bits) pour multiplexer sur un seul WebSocket
///   - Expiration automatique des connexions inactives
///   - Métriques de trafic par connexion
///
/// Utilisé quand des paquets IP bruts transitent par un relay :
///   le TUN capture les paquets, cette table mappe les flows
///   pour les reconstruire côté hôte.
///
/// Réutilisable dans tout projet nécessitant du tracking de connexion.
///
/// Usage :
///   final table = ConnectionTable();
///   final entry = table.getOrCreate(
///     protocol: 6,        // TCP
///     srcPort: 49123,
///     dstAddr: '142.250.185.14',
///     dstPort: 443,
///   );
///   print(entry.channelId);  // 1
///   table.recordActivity(entry.channelId, bytesIn: 1024);
///   table.cleanup(); // Retire les connexions expirées
/// ════════════════════════════════════════════════════════════════

/// Entrée dans la table de connexions.
class ConnectionEntry {
  /// ID court du canal (16 bits, unique dans la table).
  final int channelId;

  /// Protocole IP (6 = TCP, 17 = UDP).
  final int protocol;

  /// Port source local.
  final int srcPort;

  /// Adresse IP de destination.
  final String dstAddr;

  /// Port de destination.
  final int dstPort;

  /// Horodatage de création.
  final DateTime created;

  /// Dernier horodatage d'activité.
  DateTime lastActivity;

  /// Octets envoyés (upload).
  int bytesOut;

  /// Octets reçus (download).
  int bytesIn;

  /// État de la connexion.
  ConnectionState state;

  ConnectionEntry({
    required this.channelId,
    required this.protocol,
    required this.srcPort,
    required this.dstAddr,
    required this.dstPort,
  })  : created = DateTime.now(),
        lastActivity = DateTime.now(),
        bytesOut = 0,
        bytesIn = 0,
        state = ConnectionState.active;

  /// Clé unique pour dédupliquer.
  String get key => '$protocol:$srcPort→$dstAddr:$dstPort';

  /// Durée depuis la dernière activité.
  Duration get idleDuration => DateTime.now().difference(lastActivity);

  /// Durée totale de la connexion.
  Duration get totalDuration => DateTime.now().difference(created);

  /// Nom du protocole.
  String get protocolName {
    switch (protocol) {
      case 6:
        return 'TCP';
      case 17:
        return 'UDP';
      default:
        return 'IP:$protocol';
    }
  }

  @override
  String toString() =>
      'Conn#$channelId [$protocolName] :$srcPort → $dstAddr:$dstPort '
      '(↑${_formatBytes(bytesOut)} ↓${_formatBytes(bytesIn)})';

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / 1048576).toStringAsFixed(1)}MB';
  }
}

/// État d'une connexion.
enum ConnectionState { active, closing, closed }

/// Table de suivi de connexions (NAT-like).
class ConnectionTable {
  final Map<String, ConnectionEntry> _byKey = {};
  final Map<int, ConnectionEntry> _byChannel = {};
  int _nextChannelId = 1;
  Timer? _cleanupTimer;

  /// Durée d'inactivité avant expiration d'une connexion TCP.
  Duration tcpIdleTimeout;

  /// Durée d'inactivité avant expiration d'une connexion UDP.
  Duration udpIdleTimeout;

  /// Nombre max de connexions simultanées.
  int maxConnections;

  /// Callback quand une connexion est créée.
  void Function(ConnectionEntry entry)? onConnectionCreated;

  /// Callback quand une connexion est supprimée.
  void Function(ConnectionEntry entry)? onConnectionRemoved;

  ConnectionTable({
    this.tcpIdleTimeout = const Duration(minutes: 5),
    this.udpIdleTimeout = const Duration(seconds: 30),
    this.maxConnections = 4096,
  });

  // ─── Getters ───
  int get activeCount => _byKey.length;
  List<ConnectionEntry> get entries => List.unmodifiable(_byKey.values);
  bool get isFull => _byKey.length >= maxConnections;

  /// Métriques agrégées.
  ({int totalBytesIn, int totalBytesOut, int connections}) get metrics {
    int bIn = 0, bOut = 0;
    for (final e in _byKey.values) {
      bIn += e.bytesIn;
      bOut += e.bytesOut;
    }
    return (
      totalBytesIn: bIn,
      totalBytesOut: bOut,
      connections: _byKey.length,
    );
  }

  // ═══════════════════════════════════════════
  // LOOKUP / CREATE
  // ═══════════════════════════════════════════

  /// Récupère ou crée une connexion pour le tuple donné.
  ConnectionEntry getOrCreate({
    required int protocol,
    required int srcPort,
    required String dstAddr,
    required int dstPort,
  }) {
    final key = '$protocol:$srcPort→$dstAddr:$dstPort';
    final existing = _byKey[key];
    if (existing != null) {
      existing.lastActivity = DateTime.now();
      return existing;
    }

    // Cleanup si plein
    if (isFull) cleanup();

    final channelId = _allocateChannelId();
    final entry = ConnectionEntry(
      channelId: channelId,
      protocol: protocol,
      srcPort: srcPort,
      dstAddr: dstAddr,
      dstPort: dstPort,
    );

    _byKey[key] = entry;
    _byChannel[channelId] = entry;
    onConnectionCreated?.call(entry);
    return entry;
  }

  /// Lookup par channel ID.
  ConnectionEntry? getByChannel(int channelId) => _byChannel[channelId];

  /// Lookup par clé.
  ConnectionEntry? getByKey(String key) => _byKey[key];

  // ═══════════════════════════════════════════
  // ACTIVITY RECORDING
  // ═══════════════════════════════════════════

  /// Enregistre de l'activité sur un canal.
  void recordActivity(int channelId, {int bytesIn = 0, int bytesOut = 0}) {
    final entry = _byChannel[channelId];
    if (entry == null) return;
    entry.lastActivity = DateTime.now();
    entry.bytesIn += bytesIn;
    entry.bytesOut += bytesOut;
  }

  // ═══════════════════════════════════════════
  // CLEANUP — Expiration des connexions inactives
  // ═══════════════════════════════════════════

  /// Supprime les connexions expirées.
  int cleanup() {
    final toRemove = <String>[];
    for (final entry in _byKey.entries) {
      final timeout = entry.value.protocol == 17
          ? udpIdleTimeout
          : tcpIdleTimeout;
      if (entry.value.idleDuration > timeout ||
          entry.value.state == ConnectionState.closed) {
        toRemove.add(entry.key);
      }
    }

    for (final key in toRemove) {
      final entry = _byKey.remove(key);
      if (entry != null) {
        _byChannel.remove(entry.channelId);
        onConnectionRemoved?.call(entry);
      }
    }
    return toRemove.length;
  }

  /// Ferme une connexion par canal.
  void close(int channelId) {
    final entry = _byChannel[channelId];
    if (entry == null) return;
    entry.state = ConnectionState.closed;
    _byKey.remove(entry.key);
    _byChannel.remove(channelId);
    onConnectionRemoved?.call(entry);
  }

  /// Ferme toutes les connexions.
  void closeAll() {
    for (final entry in _byKey.values.toList()) {
      onConnectionRemoved?.call(entry);
    }
    _byKey.clear();
    _byChannel.clear();
  }

  /// Démarre le nettoyage périodique.
  void startAutoCleanup({Duration interval = const Duration(seconds: 30)}) {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(interval, (_) => cleanup());
  }

  /// Arrête le nettoyage périodique.
  void stopAutoCleanup() {
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
  }

  // ═══════════════════════════════════════════
  // CHANNEL ID ALLOCATION
  // ═══════════════════════════════════════════

  int _allocateChannelId() {
    // Cherche un ID libre (16 bits, 1-65535)
    for (int i = 0; i < 65535; i++) {
      final id = ((_nextChannelId + i - 1) % 65535) + 1;
      if (!_byChannel.containsKey(id)) {
        _nextChannelId = id + 1;
        return id;
      }
    }
    // Fallback — ne devrait jamais arriver avec maxConnections < 65535
    return _nextChannelId++;
  }

  // ═══════════════════════════════════════════
  // DISPOSE
  // ═══════════════════════════════════════════

  void dispose() {
    _cleanupTimer?.cancel();
    closeAll();
    onConnectionCreated = null;
    onConnectionRemoved = null;
  }
}
