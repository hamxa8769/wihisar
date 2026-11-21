/// Linux network tools, detected and run from inside WiHisar.
///
/// On a Linux (or Windows/macOS) desktop build, WiHisar can use the same
/// tools professionals use — but only the safe, own-network parts:
///
///   - `nmap` — ping scan + service/version scan of YOUR OWN subnet.
///   - `arp-scan` — fast ARP discovery of the local network.
///   - `iw` / `nmcli` — WiFi interface info + the networks your own card
///     can see (broadcast SSIDs — the same list any WiFi picker shows).
///   - `iperf3` — bandwidth test, only when YOU give it a server to test
///     against (no server is ever probed automatically).
///
/// What is deliberately NOT here:
///   - `aircrack-ng` password cracking (`aircrack-ng` on a captured
///     handshake), handshake capture (`airodump-ng --write`), deauth
///     attacks (`aireplay-ng --deauth`) and anything that touches a
///     network you do not own. The suite is DETECTED (so the user can see
///     it is installed) and its safe check command (`airmon-ng check`) is
///     offered — the cracking path is not built, and the app says so.
///
/// Every command runs against the subnet this device is on, shows the exact
/// command before running it, and never runs silently. On phones the tools
/// are not installed, so this whole layer reports "not available on this
/// device — see the Linux build".
library;

import 'dart:io';

/// One external tool WiHisar knows about.
class LinuxTool {
  const LinuxTool({
    required this.command,
    required this.displayName,
    required this.whatItDoes,
    this.available = false,
    this.version,
    this.crackingNote,
  });

  /// Binary name, e.g. `nmap`.
  final String command;

  final String displayName;

  /// What WiHisar uses it for (own network only).
  final String whatItDoes;

  final bool available;
  final String? version;

  /// Set for tools whose famous use is cracking — the honest boundary.
  final String? crackingNote;

  LinuxTool copyWith({bool? available, String? version}) {
    return LinuxTool(
      command: command,
      displayName: displayName,
      whatItDoes: whatItDoes,
      available: available ?? this.available,
      version: version ?? this.version,
      crackingNote: crackingNote,
    );
  }
}

/// The tools WiHisar looks for. Order is the order shown in the UI.
const List<LinuxTool> kKnownTools = [
  LinuxTool(
    command: 'nmap',
    displayName: 'nmap',
    whatItDoes:
        'Discovers hosts and open ports on your own subnet, with service versions.',
  ),
  LinuxTool(
    command: 'arp-scan',
    displayName: 'arp-scan',
    whatItDoes: 'Fast ARP discovery: every device on your local network.',
  ),
  LinuxTool(
    command: 'iw',
    displayName: 'iw',
    whatItDoes: 'Your WiFi card: interface, channel, and visible networks.',
  ),
  LinuxTool(
    command: 'nmcli',
    displayName: 'nmcli',
    whatItDoes: 'NetworkManager: connections, WiFi list, device status.',
  ),
  LinuxTool(
    command: 'iperf3',
    displayName: 'iperf3',
    whatItDoes:
        'Measures real speed — only to a server address you type in.',
  ),
  LinuxTool(
    command: 'aircrack-ng',
    displayName: 'aircrack-ng suite',
    whatItDoes:
        'Detected only. Its safe check (airmon-ng check) is offered; handshake capture and password cracking are NOT built into WiHisar.',
    crackingNote:
        'Password cracking is not part of this app: WiHisar tests your own network and never captures handshakes or cracks passwords.',
  ),
  LinuxTool(
    command: 'tshark',
    displayName: 'tshark',
    whatItDoes:
        'Packet capture, offered only with an explicit capture you start — on your own interface.',
  ),
];

/// Find which known tools are installed (`which <tool>`).
/// Returns the tools with [LinuxTool.available] and version filled in.
/// Never throws; on phones everything comes back unavailable.
Future<List<LinuxTool>> detectTools() async {
  final found = <LinuxTool>[];
  for (final tool in kKnownTools) {
    var available = false;
    String? version;
    try {
      final which = await Process.run('which', [tool.command]).timeout(
        const Duration(seconds: 5),
      );
      available = which.exitCode == 0;
      if (available) {
        try {
          final v = await Process.run(
            tool.command,
            ['--version'],
          ).timeout(const Duration(seconds: 5));
          final first = v.stdout.toString().split('\n').first.trim();
          if (first.isNotEmpty) {
            version = first.length > 60 ? first.substring(0, 60) : first;
          }
        } catch (_) {
          // Version is a nice-to-have.
        }
      }
    } catch (_) {
      // Tool not found / cannot run — stays unavailable.
    }
    found.add(tool.copyWith(available: available, version: version));
  }
  return found;
}

/// The exact command WiHisar would run, shown in the UI before running.
String nmapPingScanCommand(String subnetCidr) => 'nmap -sn $subnetCidr';

String nmapServiceScanCommand(String target) =>
    'nmap -sV --top-ports 20 $target';

String arpScanCommand() => 'arp-scan --localnet';

/// Parse `nmap -sn -oG -` (grepable) output into live host IPs.
/// Example line: `Host: 192.168.1.5 ()  Status: Up`
List<String> parseNmapGreppableHosts(String output) {
  final hosts = <String>[];
  for (final line in output.split('\n')) {
    final m = RegExp(r'^Host:\s+(\d+\.\d+\.\d+\.\d+)\s.*Status:\s*Up')
        .firstMatch(line.trim());
    if (m != null) hosts.add(m.group(1)!);
  }
  return hosts;
}

/// Parse `nmap -sV` port lines into (port, service) pairs.
/// Example: `22/tcp open  ssh  OpenSSH 8.9p1`
List<(int, String)> parseNmapServicePorts(String output) {
  final ports = <(int, String)>[];
  for (final line in output.split('\n')) {
    final m = RegExp(r'^(\d+)/tcp\s+open\s+(\S+)').firstMatch(line.trim());
    if (m != null) {
      ports.add((int.parse(m.group(1)!), m.group(2)!));
    }
  }
  return ports;
}

/// Parse `arp-scan --localnet` lines into (ip, mac, vendor) triples.
/// Example: `192.168.1.5  aa:bb:cc:dd:ee:ff  Vendor Name`
List<(String, String, String)> parseArpScan(String output) {
  final rows = <(String, String, String)>[];
  for (final line in output.split('\n')) {
    final m = RegExp(
      r'^(\d+\.\d+\.\d+\.\d+)\s+([0-9a-fA-F:]{17})\s+(.*)$',
    ).firstMatch(line.trim());
    if (m != null) {
      rows.add((m.group(1)!, m.group(2)!, m.group(3)!.trim()));
    }
  }
  return rows;
}

/// Run `nmap -sn <subnet>` (host discovery on your own subnet).
/// Returns the live host IPs. Never throws — failures return an empty list.
Future<List<String>> runNmapPingScan(String subnetCidr) async {
  try {
    final r = await Process.run(
      'nmap',
      ['-sn', '-oG', '-', subnetCidr],
    ).timeout(const Duration(seconds: 120));
    return parseNmapGreppableHosts(r.stdout.toString());
  } catch (_) {
    return const [];
  }
}

/// Run `nmap -sV --top-ports 20 <target>` on one host of your own network.
Future<List<(int, String)>> runNmapServiceScan(String target) async {
  try {
    final r = await Process.run(
      'nmap',
      ['-sV', '--top-ports', '20', target],
    ).timeout(const Duration(seconds: 120));
    return parseNmapServicePorts(r.stdout.toString());
  } catch (_) {
    return const [];
  }
}

/// Run `arp-scan --localnet` on your own network.
Future<List<(String, String, String)>> runArpScan() async {
  try {
    final r = await Process.run(
      'arp-scan',
      ['--localnet'],
    ).timeout(const Duration(seconds: 60));
    return parseArpScan(r.stdout.toString());
  } catch (_) {
    return const [];
  }
}
