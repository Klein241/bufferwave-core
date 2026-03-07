# BufferWave Core 🔌

**Moteur réseau réutilisable pour applications VPN et relay.**

Bibliothèque Dart contenant tous les composants réseau de bas niveau : relay distribué, forwarding TCP, sélection de chemin adaptatif, et protocole de multiplexage binaire.

## 📦 Modules

### 🌐 Relay Engine

| Module | Description |
|--------|-------------|
| **EdgeRelay** | Client relay WebSocket avec auto-reconnect, rate limiting (token bucket), health monitoring, graceful server restart, et bandwidth tracking |
| **PathSelector** | Sélection adaptative multi-chemin : WiFi Direct → LAN → Edge → Multi-hop. Probing de latence, scoring dynamique, shuffle de régions |
| **ConnectionTable** | Table NAT-like pour le suivi de connexions : channel IDs, métriques, idle timeout, cleanup automatique |

### 📡 TCP Forwarding

| Module | Description |
|--------|-------------|
| **TcpForwarder** | Forwarding TCP natif (host-side) : ouvre de vraies connexions Internet, relaye les données bidirectionnellement, supporte le multiplexage |
| **PacketCodec** | Protocole binaire de framing pour multiplexer DATA, CONNECT, CLOSE, PING, DNS sur un seul canal |

## ⚡ Caractéristiques

- **Rate limiting** : Token bucket configurable (inspiré des ServerInfo DERP)
- **Reconnexion** : Backoff exponentiel + jitter aléatoire (anti thundering herd)
- **Keepalive adaptatif** : Normal (15s) / Eco (45s) selon la qualité réseau
- **Health monitoring** : Healthy → Degraded → Restarting → Dead
- **Multi-endpoint** : Fallback automatique entre plusieurs serveurs relay
- **Region shuffle** : Randomisation des endpoints pour répartir la charge
- **Bandwidth tracking** : Mesure BPS glissante (fenêtre 5s)
- **Idle cleanup** : Fermeture automatique des connexions inactives
- **Null-safety** : 100% Dart null-safe
- **Zéro dépendances lourdes** : Uniquement `web_socket_channel`

## 🔧 Installation

```yaml
# pubspec.yaml
dependencies:
  bufferwave_core:
    git:
      url: https://github.com/Klein241/bufferwave-core.git
      ref: main
```

## 📖 Usage

### EdgeRelay — Connexion relay

```dart
import 'package:bufferwave_core/bufferwave_core.dart';

final relay = EdgeRelay(
  endpoints: ['wss://relay.example.com/tunnel'],
  localId: 'node-abc',
  peerId: 'node-xyz',
);

relay.onData = (bytes) => print('Received ${bytes.length} bytes');
relay.onPaired = () => print('Connected to peer!');
relay.onHealthChanged = (health, problem) => print('Health: $health');

// Rate limit: 1 MB/s
relay.setRateLimit(bytesPerSec: 1024 * 1024);

await relay.connect();
relay.sendBinary(myPacket);
await relay.disconnect();
```

### PathSelector — Meilleur chemin

```dart
final selector = PathSelector();
selector.addPaths([
  PathInfo(id: 'wifi', endpoint: 'ws://direct', type: PathType.wifiDirect),
  PathInfo(id: 'eu-1', endpoint: 'wss://eu.relay.com', type: PathType.edgeRelay),
  PathInfo(id: 'us-1', endpoint: 'wss://us.relay.com', type: PathType.edgeRelay),
]);

// Shuffle les endpoints du même type (anti thundering herd)
selector.shuffleSameType(PathType.edgeRelay);

selector.measureLatency = (url) async => measurePing(url);
final best = await selector.probeAll();
print('Best path: ${best?.id} (${best?.rttMs}ms)');
```

### PacketCodec — Framing binaire

```dart
// Encoder
final frame = PacketCodec.encodeData(channelId: 1, data: payload);

// Decoder
final packet = PacketCodec.decode(rawBytes);
print('Type: ${packet?.type}, Channel: ${packet?.channelId}');
```

## 🏗 Architecture

```
bufferwave_core/
├── lib/
│   ├── bufferwave_core.dart          # API publique
│   └── src/
│       ├── relay/
│       │   ├── edge_relay.dart       # Client relay distribué
│       │   ├── path_selector.dart    # Sélection de chemin
│       │   ├── connection_table.dart # Table de connexions NAT
│       │   ├── tcp_forwarder.dart    # Forwarding TCP
│       │   └── packet_codec.dart     # Protocole binaire
│       ├── api/                      # API REST BufferWave
│       ├── features/                 # DNS-over-HTTPS, Split tunneling
│       ├── transport/                # WebSocket, Secure tunnel
│       └── vpn/                      # VPN bridge
└── pubspec.yaml
```

## 📄 Licence

Projet privé — © SYGMA-TECH
