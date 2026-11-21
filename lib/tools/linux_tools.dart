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
///   - `tshark` — protocol summary of a short capture you start, on your
///     own interface.
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
///
/// Runners come in two flavours: the old ones that return an empty list on
/// failure (kept for the existing UI), and the `Detailed` ones that return
/// a [ToolResult] whose `error` names the cause — 'not installed',
/// 'needs root', 'timed out', and so on — so the UI can tell the user what
/// to do instead of showing an empty list.
library;

import 'dart:async';
import 'dart:io';

/// The result of running an external tool: data on success, or a plain
/// human-readable error naming the cause on failure. Never throws.
class ToolResult<T> {
  const ToolResult({this.data, this.error});

  final T? data;
  final String? error;

  bool get ok => error == null;
}

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

/// The command that finds a binary on this OS: `where` on Windows,
/// `which` everywhere else. (`which` does not exist on Windows.)
String lookupCommandName() => Platform.isWindows ? 'where' : 'which';

/// How to install [toolCommand], per OS, or null for an unknown tool.
String? installCommandFor(String toolCommand) {
  switch (toolCommand) {
    case 'nmap':
      return 'sudo apt install nmap  (Debian/Ubuntu)  •  brew install nmap  (macOS)  •  choco install nmap  (Windows)';
    case 'arp-scan':
      return 'sudo apt install arp-scan  (Debian/Ubuntu)  •  brew install arp-scan  (macOS)';
    case 'iw':
      return 'sudo apt install iw  (Debian/Ubuntu)';
    case 'nmcli':
      return 'sudo apt install network-manager  (Debian/Ubuntu)';
    case 'iperf3':
      return 'sudo apt install iperf3  (Debian/Ubuntu)  •  brew install iperf3  (macOS)  •  choco install iperf3  (Windows)';
    case 'aircrack-ng':
      return 'sudo apt install aircrack-ng  (Debian/Ubuntu)  •  brew install aircrack-ng  (macOS)';
    case 'tshark':
      return 'sudo apt install tshark  (Debian/Ubuntu)  •  brew install wireshark  (macOS)  •  choco install wireshark  (Windows)';
    default:
      return null;
  }
}

/// Plain-English cause of a tool failure, for the UI. Names the fix
/// (install it / run as root / timed out) instead of a stack trace.
String describeToolFailure(String tool, Object e, {String stderr = '', int? exitCode}) {
  final combined = '$e\n$stderr';
  if (e is ProcessException ||
      combined.contains('No such file or directory')) {
    final hint = installCommandFor(tool);
    return '$tool is not installed.${hint == null ? '' : ' Install it: $hint'}';
  }
  if (combined.contains('Permission denied') ||
      combined.contains('Operation not permitted') ||
      combined.contains("don't have permission")) {
    return '$tool needs permission to run — try as root (sudo) or administrator.';
  }
  if (e is TimeoutException) return '$tool timed out.';
  final firstLine = stderr
      .split('\n')
      .map((l) => l.trim())
      .firstWhere((l) => l.isNotEmpty, orElse: () => '');
  if (firstLine.isNotEmpty) {
    return '$tool failed${exitCode == null ? '' : ' (exit $exitCode)'}: $firstLine';
  }
  if (exitCode != null) return '$tool failed (exit $exitCode).';
  return '$tool failed: $e';
}

/// Find which known tools are installed (`which`/`where <tool>`).
/// Returns the tools with [LinuxTool.available] and version filled in.
/// Never throws; on phones everything comes back unavailable.
Future<List<LinuxTool>> detectTools() async {
  final found = <LinuxTool>[];
  final lookup = lookupCommandName();
  for (final tool in kKnownTools) {
    var available = false;
    String? version;
    try {
      final which = await Process.run(lookup, [tool.command]).timeout(
        const Duration(seconds: 5),
      );
      available = which.exitCode == 0;
      if (available) {
        try {
          // Best effort: `iw` has no stable --version, so its version
          // may stay null — the tool is still reported as available.
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

/// The exact iperf3 command WiHisar would run against [server].
/// Seconds are clamped to 1-60, matching the runner.
String iperf3Command(String server, {int seconds = 5}) =>
    'iperf3 -c $server -t ${seconds.clamp(1, 60)}';

/// The exact nmcli command for a WiFi scan.
String nmcliWifiScanCommand() =>
    'nmcli -t -f SSID,SIGNAL,SECURITY dev wifi list --rescan yes';

/// The exact tshark command for a protocol summary on [interfaceName].
/// Seconds are clamped to 1-30, matching the runner.
String tsharkSummaryCommand(String interfaceName, {int seconds = 10}) =>
    'tshark -i $interfaceName -a duration:${seconds.clamp(1, 30)} -q -z io,phs';

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

/// Parse `nmap -sV` port lines into (port, service, version) records.
/// Example: `22/tcp  open  ssh  OpenSSH 8.9p1`
List<({int port, String service, String version})> parseNmapServicePorts(
  String output,
) {
  final ports = <({int port, String service, String version})>[];
  for (final line in output.split('\n')) {
    final m = RegExp(r'^(\d+)/tcp\s+open\s+(\S+)(?:\s+(.*))?$')
        .firstMatch(line.trim());
    if (m != null) {
      ports.add((
        port: int.parse(m.group(1)!),
        service: m.group(2)!,
        version: (m.group(3) ?? '').trim(),
      ));
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

/// Parse iperf3 client output into sent/received speeds (Mbits/sec).
/// Reads the summary lines (`... Mbits/sec  sender` / `... receiver`);
/// a direction with no line reports null.
({double? sentMbps, double? receivedMbps}) parseIperf3(String output) {
  double? sent;
  double? received;
  for (final line in output.split('\n')) {
    final m = RegExp(r'([\d.]+)\s+Mbits/sec\s+(sender|receiver)')
        .firstMatch(line);
    if (m != null) {
      final value = double.tryParse(m.group(1)!);
      if (m.group(2) == 'sender') {
        sent = value;
      } else {
        received = value;
      }
    }
  }
  return (sentMbps: sent, receivedMbps: received);
}

/// Parse `nmcli -t -f SSID,SIGNAL,SECURITY dev wifi list` output into
/// (ssid, signal 0-100, security) rows. Hidden networks (empty SSID) are
/// skipped; an SSID containing ':' is kept as-is.
List<({String ssid, int signal, String security})> parseNmcliWifiList(
  String output,
) {
  final rows = <({String ssid, int signal, String security})>[];
  for (final line in output.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    final parts = trimmed.split(':');
    if (parts.length < 3) continue;
    final security = parts.last;
    final signal = int.tryParse(parts[parts.length - 2]) ?? 0;
    final ssid = parts.sublist(0, parts.length - 2).join(':');
    if (ssid.isEmpty) continue;
    rows.add((ssid: ssid, signal: signal, security: security));
  }
  return rows;
}

/// Parse `iw dev` output into the first interface's link info.
/// Example:
/// ```
/// Interface wlan0
///   ssid MyWiFi
///   channel 6 (2437 MHz), width: 20 MHz
///   txpower 20.00 dBm
/// ```
({String interface, String? ssid, String? channel, String? txPower})
    parseIwDev(String output) {
  var interface = '';
  String? ssid;
  String? channel;
  String? txPower;
  for (final line in output.split('\n')) {
    final trimmed = line.trim();
    var m = RegExp(r'^Interface\s+(\S+)').firstMatch(trimmed);
    if (m != null && interface.isEmpty) interface = m.group(1)!;
    m = RegExp(r'^ssid\s+(.+)$').firstMatch(trimmed);
    if (m != null) ssid = m.group(1)!.trim();
    m = RegExp(r'^channel\s+(\d+)').firstMatch(trimmed);
    if (m != null) channel = m.group(1);
    m = RegExp(r'^txpower\s+([\d.]+ dBm)').firstMatch(trimmed);
    if (m != null) txPower = m.group(1);
  }
  return (
    interface: interface,
    ssid: ssid,
    channel: channel,
    txPower: txPower,
  );
}

/// Parse `tshark -z io,phs` protocol-hierarchy output into
/// (protocol, frames, bytes) rows, one per line of the hierarchy.
/// Example line: `  tcp  frames:8 bytes:1000`
List<({String protocol, int frames, int bytes})> parseTsharkProtocolHierarchy(
  String output,
) {
  final rows = <({String protocol, int frames, int bytes})>[];
  for (final line in output.split('\n')) {
    final m = RegExp(r'^\s*(\S+)\s+frames:(\d+)\s+bytes:(\d+)')
        .firstMatch(line);
    if (m != null) {
      rows.add((
        protocol: m.group(1)!,
        frames: int.parse(m.group(2)!),
        bytes: int.parse(m.group(3)!),
      ));
    }
  }
  return rows;
}

/// Run `nmap -sn <subnet>` (host discovery on your own subnet).
/// Returns the live host IPs. Never throws — failures return an empty list.
Future<List<String>> runNmapPingScan(String subnetCidr) async {
  final result = await runNmapPingScanDetailed(subnetCidr);
  return result.data ?? const [];
}

/// Run `nmap -sn <subnet>` with a [ToolResult] that names the failure.
Future<ToolResult<List<String>>> runNmapPingScanDetailed(
  String subnetCidr,
) async {
  try {
    final r = await Process.run(
      'nmap',
      ['-sn', '-oG', '-', subnetCidr],
    ).timeout(const Duration(seconds: 120));
    if (r.exitCode != 0) {
      return ToolResult(
        error: describeToolFailure(
          'nmap',
          StateError('exit ${r.exitCode}'),
          stderr: r.stderr.toString(),
          exitCode: r.exitCode,
        ),
      );
    }
    return ToolResult(data: parseNmapGreppableHosts(r.stdout.toString()));
  } catch (e) {
    return ToolResult(error: describeToolFailure('nmap', e));
  }
}

/// Run `nmap -sV --top-ports 20 <target>` on one host of your own network.
Future<List<({int port, String service, String version})>>
    runNmapServiceScan(String target) async {
  final result = await runNmapServiceScanDetailed(target);
  return result.data ?? const [];
}

/// Run `nmap -sV --top-ports 20 <target>` with a [ToolResult] that names
/// the failure.
Future<ToolResult<List<({int port, String service, String version})>>>
    runNmapServiceScanDetailed(String target) async {
  try {
    final r = await Process.run(
      'nmap',
      ['-sV', '--top-ports', '20', target],
    ).timeout(const Duration(seconds: 120));
    if (r.exitCode != 0) {
      return ToolResult(
        error: describeToolFailure(
          'nmap',
          StateError('exit ${r.exitCode}'),
          stderr: r.stderr.toString(),
          exitCode: r.exitCode,
        ),
      );
    }
    return ToolResult(data: parseNmapServicePorts(r.stdout.toString()));
  } catch (e) {
    return ToolResult(error: describeToolFailure('nmap', e));
  }
}

/// Run `arp-scan --localnet` on your own network.
Future<List<(String, String, String)>> runArpScan() async {
  final result = await runArpScanDetailed();
  return result.data ?? const [];
}

/// Run `arp-scan --localnet` with a [ToolResult] that names the failure
/// (most commonly: arp-scan needs root).
Future<ToolResult<List<(String, String, String)>>> runArpScanDetailed() async {
  try {
    final r = await Process.run(
      'arp-scan',
      ['--localnet'],
    ).timeout(const Duration(seconds: 60));
    final stderr = r.stderr.toString();
    if (r.exitCode != 0) {
      if (stderr.toLowerCase().contains('root') ||
          stderr.contains('Permission denied')) {
        return const ToolResult(
          error:
              'arp-scan needs root — run WiHisar with sudo or as administrator.',
        );
      }
      return ToolResult(
        error: describeToolFailure(
          'arp-scan',
          StateError('exit ${r.exitCode}'),
          stderr: stderr,
          exitCode: r.exitCode,
        ),
      );
    }
    return ToolResult(data: parseArpScan(r.stdout.toString()));
  } catch (e) {
    return ToolResult(error: describeToolFailure('arp-scan', e));
  }
}

/// Run iperf3 against [server] for [seconds] (clamped to 1-60 s) and
/// return the sent/received speeds. The server address comes from the
/// user — WiHisar never picks one itself. A missing direction reports
/// 0.0; no speed at all is an error.
Future<ToolResult<({double sentMbps, double receivedMbps})>> runIperf3(
  String server, {
  int seconds = 5,
}) async {
  final host = server.trim();
  if (host.isEmpty) {
    return const ToolResult(
      error: 'Give an iperf3 server address to test against.',
    );
  }
  final secs = seconds.clamp(1, 60);
  try {
    final r = await Process.run(
      'iperf3',
      ['-c', host, '-t', '$secs', '-f', 'm'],
    ).timeout(Duration(seconds: secs + 15));
    final stderr = r.stderr.toString();
    if (r.exitCode != 0) {
      if (stderr.contains('unable to connect to server') ||
          stderr.contains('No route to host') ||
          stderr.contains('Connection refused')) {
        return ToolResult(
          error:
              'Could not reach iperf3 server $host — is iperf3 running there? ($stderr)',
        );
      }
      if (stderr.contains('Name or service not known') ||
          stderr.contains('Temporary failure in name resolution')) {
        return ToolResult(error: 'Unknown iperf3 server $host.');
      }
      return ToolResult(
        error: describeToolFailure(
          'iperf3',
          StateError('exit ${r.exitCode}'),
          stderr: stderr,
          exitCode: r.exitCode,
        ),
      );
    }
    final parsed = parseIperf3(r.stdout.toString());
    if (parsed.sentMbps == null && parsed.receivedMbps == null) {
      return const ToolResult(
        error: 'iperf3 ran but reported no speed.',
      );
    }
    return ToolResult(
      data: (
        sentMbps: parsed.sentMbps ?? 0.0,
        receivedMbps: parsed.receivedMbps ?? 0.0,
      ),
    );
  } catch (e) {
    return ToolResult(error: describeToolFailure('iperf3', e));
  }
}

/// Scan visible WiFi networks with nmcli (Linux only). Returns
/// (ssid, signal, security) rows.
Future<ToolResult<List<({String ssid, int signal, String security})>>>
    runNmcliWifiScan() async {
  if (!Platform.isLinux) {
    return const ToolResult(error: 'nmcli is Linux-only.');
  }
  try {
    final r = await Process.run('nmcli', [
      '-t',
      '-f',
      'SSID,SIGNAL,SECURITY',
      'dev',
      'wifi',
      'list',
      '--rescan',
      'yes',
    ]).timeout(const Duration(seconds: 30));
    final stderr = r.stderr.toString();
    if (r.exitCode != 0) {
      if (stderr.contains('No Wi-Fi device found')) {
        return const ToolResult(
          error: 'No Wi-Fi device found — nmcli cannot scan without one.',
        );
      }
      return ToolResult(
        error: describeToolFailure(
          'nmcli',
          StateError('exit ${r.exitCode}'),
          stderr: stderr,
          exitCode: r.exitCode,
        ),
      );
    }
    return ToolResult(data: parseNmcliWifiList(r.stdout.toString()));
  } catch (e) {
    return ToolResult(error: describeToolFailure('nmcli', e));
  }
}

/// Run `iw dev` (Linux only) and return its raw output, so the UI can
/// show the interface, SSID, channel and txpower.
Future<ToolResult<String>> runIwDev() async {
  if (!Platform.isLinux) {
    return const ToolResult(error: 'iw is Linux-only.');
  }
  try {
    final r = await Process.run('iw', ['dev']).timeout(
      const Duration(seconds: 10),
    );
    if (r.exitCode != 0) {
      return ToolResult(
        error: describeToolFailure(
          'iw',
          StateError('exit ${r.exitCode}'),
          stderr: r.stderr.toString(),
          exitCode: r.exitCode,
        ),
      );
    }
    return ToolResult(data: r.stdout.toString().trim());
  } catch (e) {
    return ToolResult(error: describeToolFailure('iw', e));
  }
}

/// Capture [seconds] (clamped to 1-30 s) on [interfaceName] with tshark
/// and return the protocol hierarchy summary (protocol, frames, bytes).
/// The capture runs only when the user starts it, on their own interface.
Future<ToolResult<List<({String protocol, int frames, int bytes})>>>
    runTsharkProtocolSummary({
  required String interfaceName,
  int seconds = 10,
}) async {
  final iface = interfaceName.trim();
  if (iface.isEmpty) {
    return const ToolResult(error: 'Give an interface name to capture on.');
  }
  final secs = seconds.clamp(1, 30);
  try {
    final r = await Process.run('tshark', [
      '-i',
      iface,
      '-a',
      'duration:$secs',
      '-q',
      '-z',
      'io,phs',
    ]).timeout(Duration(seconds: secs + 15));
    final stderr = r.stderr.toString();
    if (r.exitCode != 0) {
      if (stderr.contains("don't have permission") ||
          stderr.contains('Permission denied')) {
        return const ToolResult(
          error:
              'tshark needs permission to capture — run as root (sudo) or add your user to the wireshark group.',
        );
      }
      if (stderr.contains('No such device') ||
          stderr.contains('not found') ||
          stderr.contains('does not exist')) {
        return ToolResult(error: 'Interface $iface not found.');
      }
      return ToolResult(
        error: describeToolFailure(
          'tshark',
          StateError('exit ${r.exitCode}'),
          stderr: stderr,
          exitCode: r.exitCode,
        ),
      );
    }
    return ToolResult(
      data: parseTsharkProtocolHierarchy(r.stdout.toString()),
    );
  } catch (e) {
    return ToolResult(error: describeToolFailure('tshark', e));
  }
}
