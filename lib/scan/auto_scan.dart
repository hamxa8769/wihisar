/// Automatic network scanner: finds your own network, then scans it.
///
/// No manual input needed:
///   1. Local IP + prefix from the OS network interfaces (the prefix is
///      read from `ip addr` / `ipconfig` / `ifconfig`, not assumed).
///   2. Gateway from the OS routing table (or the subnet's `.1` as a
///      labelled guess when the table cannot be read).
///   3. Liveness sweep of every host in the subnet (ICMP ping on desktop,
///      TCP probes on mobile where raw ping is unavailable), then the
///      neighbour cache is primed and the ARP table read once to attach
///      MAC addresses — priming is what finds hosts that ignore ICMP and
///      that the OS has never talked to.
///   4. Reverse DNS for hostnames (parallel, batched) and a TCP probe of
///      the common ports on each live host (parallel hosts and ports),
///      with a short banner grab.
///
/// Everything runs against the network this device is connected to — your
/// own WiFi. Progress is reported through [onProgress] so the UI can show
/// a live bar; the scan never throws (failures come back as empty results
/// with a note). Pass [isCancelled] to stop between phases — the scan
/// returns what it found so far.
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

/// Compare two IPv4 addresses numerically ('192.168.1.9' < '192.168.1.10').
int compareIps(String a, String b) {
  final ao = parseIpv4(a);
  final bo = parseIpv4(b);
  if (ao.isEmpty || bo.isEmpty) return a.compareTo(b);
  for (var i = 0; i < 4; i++) {
    if (ao[i] != bo[i]) return ao[i].compareTo(bo[i]);
  }
  return 0;
}

/// Merge two host lists by IP. [extra] fills in whatever [base] is
/// missing — MAC, hostname, vendor, open ports, ping — and flags are
/// OR-ed. Hosts only in [extra] are appended. The result is sorted by IP.
List<ScannedHost> mergeHosts(List<ScannedHost> base, List<ScannedHost> extra) {
  final byIp = <String, ScannedHost>{for (final h in base) h.ip: h};
  for (final e in extra) {
    final existing = byIp[e.ip];
    if (existing == null) {
      byIp[e.ip] = e;
      continue;
    }
    byIp[e.ip] = ScannedHost(
      ip: existing.ip,
      mac: (existing.mac != null && existing.mac!.isNotEmpty)
          ? existing.mac
          : e.mac,
      hostname: existing.hostname ?? e.hostname,
      vendor: existing.vendor ?? e.vendor,
      isGateway: existing.isGateway || e.isGateway,
      isSelf: existing.isSelf || e.isSelf,
      openPorts:
          existing.openPorts.isNotEmpty ? existing.openPorts : e.openPorts,
      pingMs: existing.pingMs ?? e.pingMs,
    );
  }
  final merged = byIp.values.toList();
  merged.sort((a, b) => compareIps(a.ip, b.ip));
  return merged;
}

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
          final prefix = await detectNetworkPrefix(ip);
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

  /// The real CIDR prefix for [localIp], read from the OS
  /// (`ip addr` / `ipconfig` / `ifconfig`). Falls back to /24 — correct
  /// for nearly every home network — when the OS will not say.
  Future<int> detectNetworkPrefix(String localIp) async {
    try {
      if (Platform.isLinux || Platform.isAndroid) {
        final r = await Process.run('ip', ['addr', 'show']).timeout(
          const Duration(seconds: 5),
        );
        return parseLinuxIpAddr(r.stdout.toString())[localIp] ??
            _fallbackPrefix;
      }
      if (Platform.isWindows) {
        final r = await Process.run('ipconfig', []).timeout(
          const Duration(seconds: 5),
        );
        return parseWindowsIpconfig(r.stdout.toString())[localIp] ??
            _fallbackPrefix;
      }
      if (Platform.isMacOS || Platform.isIOS) {
        final r = await Process.run('ifconfig', []).timeout(
          const Duration(seconds: 5),
        );
        return parseBsdIfconfig(r.stdout.toString())[localIp] ??
            _fallbackPrefix;
      }
    } catch (_) {
      // Fall through to the default.
    }
    return _fallbackPrefix;
  }

  /// Last-resort prefix when the OS will not tell us the netmask.
  /// Dart's [NetworkInterface] does not expose it, and /24 is correct for
  /// nearly every home network.
  static const int _fallbackPrefix = 24;

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
  /// Calls [onProgress] as hosts are probed. Never throws. When
  /// [isCancelled] returns true between phases or batches, the scan stops
  /// and returns what it found so far.
  Future<List<ScannedHost>> scan(
    LocalNetwork network, {
    bool scanPorts = true,
    ScanProgress? onProgress,
    bool Function()? isCancelled,
  }) async {
    bool cancelled() => isCancelled?.call() ?? false;
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
      if (cancelled()) return const [];
      final batch = hosts.skip(i).take(32).map(probe);
      await Future.wait(batch);
    }
    if (cancelled()) return const [];

    // Phase 2 — prime the neighbour cache, then read the ARP table to
    // attach MAC + vendor to live hosts.
    onProgress?.call(total, total, 'Reading device list…');
    final scanner = SubnetScanner();
    await scanner.primeNeighbourCache(hosts);
    if (cancelled()) return const [];
    final arpDevices = await scanner.readNeighbourTable();
    final byIp = {for (final d in arpDevices) d.ip: d};

    final found = <ScannedHost>[];
    for (final entry in live.entries) {
      final ip = entry.key;
      final dev = byIp[ip];
      found.add(
        ScannedHost.fromDevice(
          dev ?? ConnectedDevice(ip: ip, mac: '', vendor: null),
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
    found.sort((a, b) => compareIps(a.ip, b.ip));
    if (cancelled()) return found;

    // Phase 3 — hostnames (reverse DNS, best effort, batched).
    onProgress?.call(total, total, 'Resolving names…');
    final named = <ScannedHost>[];
    for (var i = 0; i < found.length; i += 16) {
      if (cancelled()) return [...named, ...found.skip(named.length)];
      final batch = found.skip(i).take(16).map((h) async {
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
        return h.copyWith(hostname: name);
      });
      named.addAll(await Future.wait(batch));
    }
    if (cancelled()) return named;

    // Phase 4 — ports on each live host (TCP connect + banner grab),
    // 8 hosts at a time.
    if (scanPorts) {
      onProgress?.call(total, total, 'Checking open ports…');
      final withPorts = <ScannedHost>[];
      for (var i = 0; i < named.length; i += 8) {
        if (cancelled()) return [...withPorts, ...named.skip(withPorts.length)];
        final batch = named.skip(i).take(8).map((h) async {
          final ports = await scanPortsOf(h.ip);
          return h.copyWith(openPorts: ports);
        });
        withPorts.addAll(await Future.wait(batch));
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
  /// Ports are probed 8 at a time. Exposed for tests of the port list
  /// (the I/O itself is best-effort).
  Future<List<OpenPort>> scanPortsOf(String ip) async {
    final entries = kCommonPorts.entries.toList();
    final open = <OpenPort>[];
    for (var i = 0; i < entries.length; i += 8) {
      final results = await Future.wait(
        entries.skip(i).take(8).map(
              (entry) => _probePort(ip, entry.key, entry.value),
            ),
      );
      open.addAll(results.whereType<OpenPort>());
    }
    open.sort((a, b) => a.port.compareTo(b.port));
    return open;
  }

  /// Probe one port: connect, grab a banner line if the service sends one.
  Future<OpenPort?> _probePort(String ip, int port, String service) async {
    try {
      final socket = await Socket.connect(
        ip,
        port,
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
      return OpenPort(port: port, service: service, banner: banner);
    } catch (_) {
      // Closed / filtered.
      return null;
    }
  }
}
