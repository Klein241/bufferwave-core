/// ════════════════════════════════════════════════════════════════
/// BUFFERWAVE CORE v12.0
///
/// Production VPN API — 5 piliers :
///   1. Tunnel VLESS (Cloudflare Worker stealth)
///   2. VPN Bridge (Flutter ↔ Android native)
///   3. Kill Switch (coupe internet si VPN tombe)
///   4. DoH Resolver (DNS chiffré via HTTPS)
///   5. Stealth Engine (obfuscation, fragment TLS, decoy)
///
/// Usage :
///   import 'package:bufferwave_core/bufferwave_core.dart';
///
///   final bw = BufferWave();
///   await bw.initialize();
///   bw.configure(
///     workerUrl: 'https://my-worker.example.com',
///     tunnelKey: 'generated-uuid-key',
///   );
///   await bw.connect(killSwitch: true, stealth: true, doh: true);
///   print(bw.status);
///   await bw.disconnect();
/// ════════════════════════════════════════════════════════════════
library bufferwave_core;

// ─── Core Engine ───
export 'src/bufferwave.dart';

// ─── VPN Bridge ───
export 'src/vpn/vpn_bridge.dart';

// ─── Kill Switch ───
export 'src/features/kill_switch.dart';

// ─── DoH Resolver ───
export 'src/features/doh_resolver.dart';

// ─── Tunnel Configuration & Stealth ───
export 'src/transport/tunnel_config.dart';

// ─── API Client ───
export 'src/api/bufferwave_api.dart';

// ─── WebSocket Transport ───
export 'src/transport/websocket_transport.dart';

// ─── Secure Transport (stealth + fragment) ───
export 'src/transport/secure_tunnel.dart';

// ─── Split Tunneling ───
export 'src/features/split_tunneling.dart';

// ─── Smart Servers ───
export 'src/features/smart_servers.dart';
