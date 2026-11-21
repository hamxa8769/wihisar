/// Connected-device discovery: subnet ARP/ping scan.
//
// Approach (same style as the `network_tools` Dart package): prime the
// neighbour cache by touching every address in the /24 subnet, then read
// the OS ARP/neighbour table once — one table read instead of a ping process
// per address, so a scan takes about a second and still finds hosts that
// ignore ICMP. On mobile the fallback is an ICMP sweep.
//
// The pure parsers in this file are unit-tested. The I/O (running `arp` /
// `ip neigh` / ping) lives in [SubnetScanner] and is kept behind a small
// interface so tests never touch the network.
library;

import 'dart:io';

import '../router/oui.dart';

/// One device seen on the local network.
class ConnectedDevice {
  const ConnectedDevice({
    required this.ip,
    required this.mac,
    this.hostname,
    this.vendor,
    this.isGateway = false,
  });

  final String ip;
  final String mac;
  final String? hostname;

  /// Vendor from the offline OUI table, if known.
  final String? vendor;
  final bool isGateway;

  ConnectedDevice withVendor() => ConnectedDevice(
        ip: ip,
        mac: mac,
        hostname: hostname,
        vendor: vendor ?? vendorForMac(mac),
        isGateway: isGateway,
      );

  Map<String, dynamic> toJson() => {
        'ip': ip,
        'mac': mac,
        'hostname': hostname,
        'vendor': vendor,
        'isGateway': isGateway,
      };
}

/// Parse Linux `ip neigh` / `arp -n` output.
/// Example line: `192.168.1.5 dev wlan0 lladdr aa:bb:cc:dd:ee:ff REACHABLE`
List<ConnectedDevice> parseLinuxNeigh(String output) {
  final devices = <ConnectedDevice>[];
  for (final line in output.split('\n')) {
    final m = RegExp(
            r'(\d+\.\d+\.\d+\.\d+).*?lladdr\s+([0-9a-fA-F:]{17})',
            caseSensitive: false)
        .firstMatch(line);
    if (m != null) {
      devices.add(ConnectedDevice(ip: m.group(1)!, mac: m.group(2)!).withVendor());
    }
  }
  return devices;
}

/// Parse Windows `arp -a` output.
/// Example line: `  192.168.1.5           aa-bb-cc-dd-ee-ff     dynamic`
List<ConnectedDevice> parseWindowsArp(String output) {
  final devices = <ConnectedDevice>[];
  for (final line in output.split('\n')) {
    final m = RegExp(
            r'(\d+\.\d+\.\d+\.\d+)\s+([0-9a-fA-F-]{17})\s+(dynamic|static)',
            caseSensitive: false)
        .firstMatch(line);
    if (m != null) {
      final mac = m.group(2)!.replaceAll('-', ':');
      devices.add(ConnectedDevice(ip: m.group(1)!, mac: mac).withVendor());
    }
  }
  return devices;
}

/// Parse macOS / BSD `arp -an` output.
/// Example line: `? (192.168.1.5) at aa:bb:cc:dd:ee:ff on en0 ifscope [ethernet]`
List<ConnectedDevice> parseBsdArp(String output) {
  final devices = <ConnectedDevice>[];
  for (final line in output.split('\n')) {
    final m = RegExp(
            r'\((\d+\.\d+\.\d+\.\d+)\) at ([0-9a-fA-F:]{17})')
        .firstMatch(line);
    if (m != null) {
      devices.add(ConnectedDevice(ip: m.group(1)!, mac: m.group(2)!).withVendor());
    }
  }
  return devices;
}

/// De-duplicate by MAC, keeping the first entry seen.
List<ConnectedDevice> dedupeByMac(List<ConnectedDevice> devices) {
  final seen = <String>{};
  return devices.where((d) {
    final key = d.mac.toUpperCase();
    if (seen.contains(key)) return false;
    seen.add(key);
    return true;
  }).toList();
}

/// /24 subnet prefix for an IPv4 address, e.g. `192.168.1.` for `192.168.1.5`.
String subnetPrefixOf(String ip) {
  final parts = ip.split('.');
  if (parts.length != 4) return '';
  return '${parts[0]}.${parts[1]}.${parts[2]}.';
}

/// Runs the neighbour-table scan on the current OS. Returns the devices
/// found in the ARP table (empty list — never an exception — on failure,
/// so the UI can show an honest empty state).
class SubnetScanner {
  /// Touch every host once (TCP connect to port 80, 150 ms) so the OS
  /// resolves and caches their MAC addresses before [readNeighbourTable].
  /// The point is the ARP traffic, not the connection — every error is
  /// ignored. Batches of 64 so we never open hundreds of sockets at once.
  /// Call this before [readNeighbourTable]; without it the table only
  /// holds hosts the OS happened to talk to already.
  Future<void> primeNeighbourCache(List<String> hosts) async {
    for (var i = 0; i < hosts.length; i += 64) {
      final batch = hosts.skip(i).take(64).map((ip) async {
        try {
          final socket = await Socket.connect(
            ip,
            80,
            timeout: const Duration(milliseconds: 150),
          );
          socket.destroy();
        } catch (_) {
          // Silent host — the ARP request still went out.
        }
      });
      await Future.wait(batch);
    }
  }

  /// Read the OS neighbour table and parse it for the current platform.
  Future<List<ConnectedDevice>> readNeighbourTable() async {
    try {
      if (Platform.isWindows) {
        final r = await Process.run('arp', ['-a']);
        return dedupeByMac(parseWindowsArp(r.stdout.toString()));
      }
      if (Platform.isLinux || Platform.isAndroid) {
        // `ip neigh` first; fall back to `arp -n`.
        var r = await Process.run('ip', ['neigh']);
        var devices = parseLinuxNeigh(r.stdout.toString());
        if (devices.isEmpty) {
          r = await Process.run('arp', ['-n']);
          devices = parseLinuxNeigh(r.stdout.toString());
        }
        return dedupeByMac(devices);
      }
      if (Platform.isMacOS || Platform.isIOS) {
        final r = await Process.run('arp', ['-an']);
        return dedupeByMac(parseBsdArp(r.stdout.toString()));
      }
    } catch (_) {
      // Honest empty result; the caller shows "no devices found / scan
      // not supported on this device" instead of crashing.
    }
    return const [];
  }
}
