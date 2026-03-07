import 'dart:typed_data';

/// ════════════════════════════════════════════════════════════════
/// PacketCodec — Encodage/décodage des trames réseau
///
/// Protocole de multiplexage binaire pour le relay :
///
///   ┌──────────────────────────────────────────────┐
///   │ 1B type │ 2B channelId │ 2B length │ NB data │
///   └──────────────────────────────────────────────┘
///
///   Types :
///     0x01 — DATA      : Payload TCP/UDP
///     0x02 — CONNECT   : Demande de connexion (host:port en UTF-8)
///     0x03 — CONNECTED : Connexion établie
///     0x04 — CLOSE     : Fermeture de canal
///     0x05 — ERROR     : Erreur (message en UTF-8)
///     0x06 — PING      : Keepalive
///     0x07 — PONG      : Réponse keepalive
///     0x10 — DNS       : Requête DNS
///     0x11 — DNS_RESP  : Réponse DNS
///
/// Ce codec est indépendant du transport (WebSocket, TCP, etc).
/// Réutilisable dans tout projet nécessitant du multiplexage binaire.
///
/// Usage :
///   // Encoder un DATA frame :
///   final frame = PacketCodec.encodeData(channelId: 1, data: myBytes);
///
///   // Encoder un CONNECT :
///   final frame = PacketCodec.encodeConnect(channelId: 1, host: '1.1.1.1', port: 443);
///
///   // Décoder :
///   final packet = PacketCodec.decode(rawFrame);
///   if (packet.type == FrameType.data) {
///     handleTcpData(packet.channelId, packet.payload);
///   }
/// ════════════════════════════════════════════════════════════════

/// Types de trames.
enum FrameType {
  data(0x01),
  connect(0x02),
  connected(0x03),
  close(0x04),
  error(0x05),
  ping(0x06),
  pong(0x07),
  dns(0x10),
  dnsResp(0x11),
  unknown(0x00);

  final int code;
  const FrameType(this.code);

  static FrameType fromCode(int c) {
    for (final t in values) {
      if (t.code == c) return t;
    }
    return unknown;
  }
}

/// Trame décodée.
class PacketFrame {
  final FrameType type;
  final int channelId;
  final Uint8List payload;

  const PacketFrame({
    required this.type,
    required this.channelId,
    required this.payload,
  });

  /// Taille totale de la trame (header + payload).
  int get totalSize => 5 + payload.length;

  /// Payload interprété comme UTF-8 String.
  String get payloadString => String.fromCharCodes(payload);

  /// Pour les CONNECT frames : parse "host:port".
  ({String host, int port}) get connectTarget {
    final s = payloadString;
    final sep = s.lastIndexOf(':');
    if (sep == -1) return (host: s, port: 0);
    return (
      host: s.substring(0, sep),
      port: int.tryParse(s.substring(sep + 1)) ?? 0,
    );
  }

  @override
  String toString() =>
      'Frame(${type.name}, ch=$channelId, ${payload.length}B)';
}

/// Codec pour encoder/décoder les trames.
class PacketCodec {
  // Taille minimale d'une trame valide (header seulement).
  static const int headerSize = 5;

  // ═══════════════════════════════════════════
  // ENCODE
  // ═══════════════════════════════════════════

  /// Encode une trame DATA (payload TCP/UDP).
  static Uint8List encodeData({
    required int channelId,
    required Uint8List data,
  }) {
    return _encode(FrameType.data, channelId, data);
  }

  /// Encode une trame CONNECT (demande d'ouverture TCP).
  static Uint8List encodeConnect({
    required int channelId,
    required String host,
    required int port,
  }) {
    final addr = '$host:$port';
    return _encode(
      FrameType.connect,
      channelId,
      Uint8List.fromList(addr.codeUnits),
    );
  }

  /// Encode une trame CONNECTED (confirmation d'ouverture).
  static Uint8List encodeConnected({required int channelId}) {
    return _encode(FrameType.connected, channelId, Uint8List(0));
  }

  /// Encode une trame CLOSE (fermeture de canal).
  static Uint8List encodeClose({required int channelId}) {
    return _encode(FrameType.close, channelId, Uint8List(0));
  }

  /// Encode une trame ERROR.
  static Uint8List encodeError({
    required int channelId,
    required String message,
  }) {
    return _encode(
      FrameType.error,
      channelId,
      Uint8List.fromList(message.codeUnits),
    );
  }

  /// Encode un PING.
  static Uint8List encodePing() {
    return _encode(FrameType.ping, 0, Uint8List(0));
  }

  /// Encode un PONG.
  static Uint8List encodePong() {
    return _encode(FrameType.pong, 0, Uint8List(0));
  }

  /// Encode une requête DNS.
  static Uint8List encodeDns({
    required int channelId,
    required String hostname,
  }) {
    return _encode(
      FrameType.dns,
      channelId,
      Uint8List.fromList(hostname.codeUnits),
    );
  }

  /// Encode une réponse DNS.
  static Uint8List encodeDnsResp({
    required int channelId,
    required String ip,
  }) {
    return _encode(
      FrameType.dnsResp,
      channelId,
      Uint8List.fromList(ip.codeUnits),
    );
  }

  /// Encodage générique.
  static Uint8List _encode(FrameType type, int channelId, Uint8List payload) {
    final frame = Uint8List(headerSize + payload.length);
    frame[0] = type.code;
    frame[1] = (channelId >> 8) & 0xFF;
    frame[2] = channelId & 0xFF;
    frame[3] = (payload.length >> 8) & 0xFF;
    frame[4] = payload.length & 0xFF;
    if (payload.isNotEmpty) {
      frame.setRange(headerSize, headerSize + payload.length, payload);
    }
    return frame;
  }

  // ═══════════════════════════════════════════
  // DECODE
  // ═══════════════════════════════════════════

  /// Décode une trame à partir de données brutes.
  /// Retourne null si les données sont insuffisantes.
  static PacketFrame? decode(Uint8List data) {
    if (data.length < headerSize) return null;

    final type = FrameType.fromCode(data[0]);
    final channelId = (data[1] << 8) | data[2];
    final payloadLen = (data[3] << 8) | data[4];

    if (data.length < headerSize + payloadLen) return null;

    final payload = data.sublist(headerSize, headerSize + payloadLen);
    return PacketFrame(
      type: type,
      channelId: channelId,
      payload: payload,
    );
  }

  /// Décode toutes les trames d'un buffer (stream parsing).
  /// Retourne les trames décodées et les octets restants (incomplets).
  static ({List<PacketFrame> frames, Uint8List remaining}) decodeStream(
    Uint8List buffer,
  ) {
    final frames = <PacketFrame>[];
    int offset = 0;

    while (offset + headerSize <= buffer.length) {
      final payloadLen = (buffer[offset + 3] << 8) | buffer[offset + 4];
      final totalLen = headerSize + payloadLen;

      if (offset + totalLen > buffer.length) break;

      final frame = decode(buffer.sublist(offset, offset + totalLen));
      if (frame != null) frames.add(frame);
      offset += totalLen;
    }

    final remaining = offset < buffer.length
        ? buffer.sublist(offset)
        : Uint8List(0);

    return (frames: frames, remaining: remaining);
  }
}
