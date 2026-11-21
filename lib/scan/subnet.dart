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

/// Dotted-decimal netmask (e.g. `255.255.255.0`) to CIDR prefix (24).
/// Returns -1 for an invalid or non-contiguous mask.
int netmaskToPrefix(String mask) {
  final octets = parseIpv4(mask);
  if (octets.isEmpty) return -1;
  var bits = 0;
  var seenZero = false;
  for (final o in octets) {
    for (var b = 7; b >= 0; b--) {
      if ((o >> b) & 1 == 1) {
        if (seenZero) return -1;
        bits++;
      } else {
        seenZero = true;
      }
    }
  }
  return bits;
}

/// Hex netmask as printed by macOS `ifconfig` (e.g. `0xffffff00`) to CIDR
/// prefix (24). Returns -1 for an invalid or non-contiguous mask.
int hexNetmaskToPrefix(String hex) {
  final digits = hex.startsWith('0x') ? hex.substring(2) : hex;
  final value = int.tryParse(digits, radix: 16);
  if (value == null || value < 0 || value > 0xFFFFFFFF) return -1;
  var bits = 0;
  var seenZero = false;
  for (var b = 31; b >= 0; b--) {
    if ((value >> b) & 1 == 1) {
      if (seenZero) return -1;
      bits++;
    } else {
      seenZero = true;
    }
  }
  return bits;
}

/// Parse Linux `ip addr show` output into {ip: prefix}.
/// Example line: `    inet 192.168.1.5/24 brd 192.168.1.255 scope global wlan0`
Map<String, int> parseLinuxIpAddr(String output) {
  final result = <String, int>{};
  for (final line in output.split('\n')) {
    final m = RegExp(r'inet\s+(\d+\.\d+\.\d+\.\d+)/(\d+)').firstMatch(line);
    if (m != null) {
      final prefix = int.tryParse(m.group(2)!);
      if (prefix != null && prefix >= 0 && prefix <= 32) {
        result[m.group(1)!] = prefix;
      }
    }
  }
  return result;
}

/// Parse Windows `ipconfig` output into {ip: prefix}.
/// Each adapter block has an `IPv4 Address` line followed by a
/// `Subnet Mask` line; the two are paired in order.
/// Example:
/// `   IPv4 Address. . . . . . . . . . . : 192.168.1.5`
/// `   Subnet Mask . . . . . . . . . . . : 255.255.255.0`
Map<String, int> parseWindowsIpconfig(String output) {
  final result = <String, int>{};
  String? pendingIp;
  for (final line in output.split('\n')) {
    final ipMatch =
        RegExp(r'IPv4 Address[^:]*:\s*(\d+\.\d+\.\d+\.\d+)').firstMatch(line);
    if (ipMatch != null) {
      pendingIp = ipMatch.group(1);
      continue;
    }
    final maskMatch =
        RegExp(r'Subnet Mask[^:]*:\s*(\d+\.\d+\.\d+\.\d+)').firstMatch(line);
    if (maskMatch != null && pendingIp != null) {
      final prefix = netmaskToPrefix(maskMatch.group(1)!);
      if (prefix >= 0) result[pendingIp] = prefix;
      pendingIp = null;
    }
  }
  return result;
}

/// Parse macOS/BSD `ifconfig` output into {ip: prefix}.
/// Example line: `	inet 192.168.1.5 netmask 0xffffff00 broadcast 192.168.1.255`
Map<String, int> parseBsdIfconfig(String output) {
  final result = <String, int>{};
  for (final line in output.split('\n')) {
    final m = RegExp(
      r'inet\s+(\d+\.\d+\.\d+\.\d+)\s+netmask\s+(0x[0-9a-fA-F]+|\d+\.\d+\.\d+\.\d+)',
    ).firstMatch(line);
    if (m != null) {
      final mask = m.group(2)!;
      final prefix = mask.startsWith('0x')
          ? hexNetmaskToPrefix(mask)
          : netmaskToPrefix(mask);
      if (prefix >= 0) result[m.group(1)!] = prefix;
    }
  }
  return result;
}
