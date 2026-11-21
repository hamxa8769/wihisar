/// Subnet math + gateway parsing for the auto scanner.
///
/// Pure Dart, no I/O: given the device's own IPv4 address and prefix
/// length, this computes the network, the host range and the default
/// gateway guess. The OS-specific gateway lookups (ip route / route print /
/// netstat) are parsed by the functions at the bottom of this file; the
/// [AutoScanner] runs the commands.
library;

/// One IPv4 address as four octets.
List<int> parseIpv4(String ip) {
  final parts = ip.split('.');
  if (parts.length != 4) return const [];
  final octets = <int>[];
  for (final p in parts) {
    final n = int.tryParse(p);
    if (n == null || n < 0 || n > 255) return const [];
    octets.add(n);
  }
  return octets;
}

String ipv4ToString(List<int> octets) => octets.join('.');

int _octetsToInt(List<int> o) =>
    (o[0] << 24) | (o[1] << 16) | (o[2] << 8) | o[3];

List<int> _intToOctets(int v) =>
    [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];

/// Network address for [ip]/[prefix], e.g. 192.168.1.0 for 192.168.1.5/24.
String networkAddressOf(String ip, int prefix) {
  final o = parseIpv4(ip);
  if (o.isEmpty || prefix < 0 || prefix > 32) return '';
  final mask = prefix == 0 ? 0 : (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF;
  return ipv4ToString(_intToOctets(_octetsToInt(o) & mask));
}

/// Broadcast address for [ip]/[prefix].
String broadcastAddressOf(String ip, int prefix) {
  final o = parseIpv4(ip);
  if (o.isEmpty || prefix < 0 || prefix > 32) return '';
  final mask = prefix == 0 ? 0 : (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF;
  final bcast = _octetsToInt(o) | (~mask & 0xFFFFFFFF);
  return ipv4ToString(_intToOctets(bcast));
}

/// Number of usable host addresses in the subnet.
int hostCountOf(int prefix) {
  if (prefix < 0 || prefix > 32) return 0;
  final bits = 32 - prefix;
  if (bits <= 1) return 0;
  return (1 << bits) - 2;
}

/// All usable host IPs in the subnet, e.g. 192.168.1.1 … 192.168.1.254.
/// Capped at 1022 hosts so a /16 can never make the scanner loop forever;
/// bigger subnets are scanned in their first /24-sized window instead.
List<String> hostAddressesOf(String ip, int prefix) {
  final network = parseIpv4(networkAddressOf(ip, prefix));
  final bcast = parseIpv4(broadcastAddressOf(ip, prefix));
  if (network.isEmpty || bcast.isEmpty) return const [];
  final first = _octetsToInt(network) + 1;
  final last = _octetsToInt(bcast) - 1;
  final hosts = <String>[];
  for (var v = first; v <= last && hosts.length < 1022; v++) {
    hosts.add(ipv4ToString(_intToOctets(v)));
  }
  return hosts;
}

/// The `.1` address of the subnet — the usual home-router gateway.
/// Labelled a guess in the UI when no OS route was found.
String gatewayGuessOf(String ip, int prefix) {
  final hosts = hostAddressesOf(ip, prefix);
  return hosts.isEmpty ? '' : hosts.first;
}

/// Parse Linux `ip route` output for the default gateway.
/// Example: `default via 192.168.1.1 dev wlan0 proto dhcp metric 600`
String? parseLinuxDefaultRoute(String output) {
  for (final line in output.split('\n')) {
    final m = RegExp(r'^default via (\d+\.\d+\.\d+\.\d+)')
        .firstMatch(line.trim());
    if (m != null) return m.group(1);
  }
  return null;
}

/// Parse Windows `route print -4` output for the default gateway.
/// Looks for the `0.0.0.0  0.0.0.0  <gateway>` line.
String? parseWindowsDefaultRoute(String output) {
  for (final line in output.split('\n')) {
    final m = RegExp(r'^\s*0\.0\.0\.0\s+0\.0\.0\.0\s+(\d+\.\d+\.\d+\.\d+)')
        .firstMatch(line);
    if (m != null) return m.group(1);
  }
  return null;
}

/// Parse macOS/BSD `netstat -rn -f inet` output for the default gateway.
/// Example: `default  192.168.1.1  UGSc  en0`
String? parseBsdDefaultRoute(String output) {
  for (final line in output.split('\n')) {
    final m = RegExp(r'^default\s+(\d+\.\d+\.\d+\.\d+)\s')
        .firstMatch(line.trim());
    if (m != null) return m.group(1);
  }
  return null;
}
