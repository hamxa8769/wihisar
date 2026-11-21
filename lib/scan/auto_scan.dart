/// Automatic network scanner: finds your own network, then scans it.
///
/// No manual input needed:
///   1. Local IP + prefix from the OS network interfaces.
///   2. Gateway from the OS routing table (or the subnet's `.1` as a
///      labelled guess when the table cannot be read).
///   3. Liveness sweep of every host in the subnet (ICMP ping on desktop,
///      TCP probes on mobile where raw ping is unavailable), then one ARP
///      table read to attach MAC addresses.
///   4. Reverse DNS for hostnames, and a TCP probe of the common ports on
///      each live host, with a short banner grab.
///
/// Everything runs against the network this device is connected to — your
/// own WiFi. Progress is reported through [onProgress] so the UI can show
/// a live bar; the scan never throws (failures come back as empty results
/// with a note).
library;

import 'dart:async';
import 'dart:io';

import '../devices/device_scan.dart';
import 'host.dart';
import 'subnet.dart';

/// What the scanner found about the local network itself.
class LocalNetwork {
  const LocalNetwork({
    required this.localIp,
    required this.prefix,
    this.gatewayIp,
    this.gatewayFromRoute = false,
    this.ssid,
    this.interfaceName,
  });

  final String localIp;

  /// CIDR prefix, e.g. 24 for a /24 home network.
  final int prefix;
  final String? gatewayIp;

  /// True when the gateway came from the OS routing table, false when it
  /// is the `.1` guess.
  final bool gatewayFromRoute;
  final String? ssid;
  final String? interfaceName;

  String get networkAddress => networkAddressOf(localIp, prefix);
  List<String> get hosts => hostAddressesOf(localIp, prefix);

  String get gatewayLabel {
    final gw = gatewayIp ?? gatewayGuessOf(localIp, prefix);
    return gatewayFromRoute ? gw : '$gw (guess)';
  }
}

typedef ScanProgress = void Function(int done, int total, String phase);

class AutoScanner {
  /// Detect the local network. Returns null when no usable IPv4 interface
  /// is found (e.g. no WiFi / offline).
  Future<LocalNetwork?> detectLocalNetwork({String? ssidOverride}) async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.isLoopback || addr.isLinkLocal) continue;
          final ip = addr.address;
          final prefix = _prefixLength(addr);
          final gateway = await _detectGateway();
          return LocalNetwork(
            localIp: ip,
            prefix: prefix,
            gatewayIp: gateway ?? gatewayGuessOf(ip, prefix),
            gatewayFromRoute: gateway != null,
            ssid: ssidOverride,
            interfaceName: iface.name,
          );
        }
      }
    } catch (_) {
      // Fall through to null — the UI shows "connect to WiFi first".
    }
    return null;
  }

  /// Prefix length from the interface address (Dart does not expose the
  /// netmask directly; derive it from the raw address when possible, else
  /// assume /24 — correct for nearly every home network).
  int _prefixLength(InternetAddress addr) {
    final raw = addr.rawAddress;
    if (raw.length == 4) {
      // No netmask available through this API; /24 is the home default.
      return 24;
    }
    return 24;
  }

  Future<String?> _detectGateway() async {
    try {
      if (Platform.isLinux || Platform.isAndroid) {
        final r = await Process.run('ip', ['route']).timeout(
          const Duration(seconds: 5),
        );
        final gw = parseLinuxDefaultRoute(r.stdout.toString());
        if (gw != null) return gw;
      }
      if (Platform.isWindows) {
        final r = await Process.run('route', ['print', '-4']).timeout(
          const Duration(seconds: 5),
        );
        return parseWindowsDefaultRoute(r.stdout.toString());
      }
      if (Platform.isMacOS || Platform.isIOS) {
        final r = await Process.run('netstat', ['-rn', '-f', 'inet']).timeout(
          const Duration(seconds: 5),
        );
        return parseBsdDefaultRoute(r.stdout.toString());
      }
    } catch (_) {
      // Guess path in the caller.
    }
    return null;
  }

  /// Full scan of [network]: liveness sweep, ARP attach, hostnames, ports.
  /// Calls [onProgress] as hosts are probed. Never throws.
  Future<List<ScannedHost>> scan(
    LocalNetwork network, {
    bool scanPorts = true,
    ScanProgress? onProgress,
  }) async {
    final hosts = network.hosts;
    final total = hosts.length;
    var done = 0;
    final live = <String, int?>{};

    // Phase 1 — liveness: ping on desktop, TCP probe on mobile.
    Future<void> probe(String ip) async {
      final ms = await _probeHost(ip);
      if (ms != null) live[ip] = ms;
      done++;
      onProgress?.call(done, total, 'Finding devices…');
    }

    // Batches of 32 so we never open hundreds of sockets at once.
    for (var i = 0; i < hosts.length; i += 32) {
      final batch = hosts.skip(i).take(32).map(probe);
      await Future.wait(batch);
    }

    // Phase 2 — ARP table: attach MAC + vendor to live hosts.
    onProgress?.call(total, total, 'Reading device list…');
    final arpDevices = await SubnetScanner().readNeighbourTable();
    final byIp = {for (final d in arpDevices) d.ip: d};

    final found = <ScannedHost>[];
    for (final entry in live.entries) {
      final ip = entry.key;
      final dev = byIp[ip];
      found.add(
        ScannedHost.fromDevice(
          dev ??
              ConnectedDevice(ip: ip, mac: '', vendor: null),
          isGateway: ip == network.gatewayIp,
          isSelf: ip == network.localIp,
          pingMs: entry.value,
        ),
      );
    }
    // Hosts that are in ARP but ignored ICMP (some phones/printers) still
    // count as found — they answered ARP, so they are on the network.
    for (final d in arpDevices) {
      if (!live.containsKey(d.ip) && d.mac.isNotEmpty) {
        found.add(
          ScannedHost.fromDevice(
            d,
            isGateway: d.ip == network.gatewayIp,
            isSelf: d.ip == network.localIp,
          ),
        );
      }
    }
    found.sort((a, b) => _ipCompare(a.ip, b.ip));

    // Phase 3 — hostnames (reverse DNS, best effort, short timeout).
    onProgress?.call(total, total, 'Resolving names…');
    final named = <ScannedHost>[];
    for (final h in found) {
      String? name = h.hostname;
      try {
        final lookup = await InternetAddress(h.ip)
            .reverse()
            .timeout(const Duration(milliseconds: 400));
        final host = lookup.host;
        if (host.isNotEmpty && host != h.ip) name = host;
      } catch (_) {
        // No reverse DNS — keep the IP.
      }
      named.add(h.copyWith(hostname: name));
    }

    // Phase 4 — ports on each live host (TCP connect + banner grab).
    if (scanPorts) {
      onProgress?.call(total, total, 'Checking open ports…');
      final withPorts = <ScannedHost>[];
      for (final h in named) {
        final ports = await scanPortsOf(h.ip);
        withPorts.add(h.copyWith(openPorts: ports));
      }
      return withPorts;
    }
    return named;
  }

  /// Liveness probe: ICMP ping on desktop (one packet, 1s), TCP connect to
  /// port 80/443 on mobile. Returns round-trip ms, or null when silent.
  Future<int?> _probeHost(String ip) async {
    try {
      if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
        final args = Platform.isWindows
            ? ['-n', '1', '-w', '1000', ip]
            : ['-c', '1', '-W', '1', ip];
        final stopwatch = Stopwatch()..start();
        final r = await Process.run('ping', args).timeout(
          const Duration(seconds: 3),
        );
        stopwatch.stop();
        if (r.exitCode == 0) return stopwatch.elapsedMilliseconds;
        return null;
      }
      // Mobile: no raw ICMP — try the ports a live host usually answers.
      for (final port in [80, 443, 445]) {
        try {
          final stopwatch = Stopwatch()..start();
          final socket = await Socket.connect(
            ip,
            port,
            timeout: const Duration(milliseconds: 500),
          );
          stopwatch.stop();
          socket.destroy();
          return stopwatch.elapsedMilliseconds;
        } catch (_) {
          // Try the next port.
        }
      }
    } catch (_) {
      // Silent host.
    }
    return null;
  }

  /// TCP probe of the common ports on one host, with a short banner grab.
  /// Exposed for tests of the port list (the I/O itself is best-effort).
  Future<List<OpenPort>> scanPortsOf(String ip) async {
    final open = <OpenPort>[];
    for (final entry in kCommonPorts.entries) {
      try {
        final socket = await Socket.connect(
          ip,
          entry.key,
          timeout: const Duration(milliseconds: 400),
        );
        String? banner;
        try {
          final data = await socket.first.timeout(
            const Duration(milliseconds: 300),
          );
          final text = String.fromCharCodes(data).trim();
          if (text.isNotEmpty) {
            banner = text.split('\n').first.trim();
            if (banner.length > 80) banner = banner.substring(0, 80);
          }
        } catch (_) {
          // No banner — the open port is the finding.
        }
        socket.destroy();
        open.add(
          OpenPort(port: entry.key, service: entry.value, banner: banner),
        );
      } catch (_) {
        // Closed / filtered.
      }
    }
    return open;
  }

  int _ipCompare(String a, String b) {
    final ao = parseIpv4(a);
    final bo = parseIpv4(b);
    for (var i = 0; i < 4; i++) {
      if (ao[i] != bo[i]) return ao[i].compareTo(bo[i]);
    }
    return 0;
  }
}
