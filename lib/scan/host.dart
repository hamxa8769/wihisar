/// A host found by the auto scanner: IP, MAC, identity and open ports.
library;

import '../devices/device_scan.dart' show ConnectedDevice;

/// Well-known ports the scanner probes on every host, with what usually
/// listens there. Kept small on purpose: a full 65k-port scan is slow and
/// noisy; the top-ports list finds the services that matter on a home LAN.
const Map<int, String> kCommonPorts = {
  21: 'FTP',
  22: 'SSH',
  23: 'Telnet',
  53: 'DNS',
  80: 'HTTP',
  139: 'NetBIOS',
  443: 'HTTPS',
  445: 'SMB',
  554: 'RTSP camera',
  631: 'Printer',
  1883: 'MQTT',
  3389: 'RDP',
  5900: 'VNC',
  8080: 'HTTP alt',
  8443: 'HTTPS alt',
  9000: 'Web admin',
};

/// One open port found on a host.
class OpenPort {
  const OpenPort({required this.port, required this.service, this.banner});

  final int port;
  final String service;

  /// First bytes the service sent back, if any (e.g. `SSH-2.0-OpenSSH`).
  final String? banner;
}

/// A host on your own network, as found by the auto scanner.
class ScannedHost {
  const ScannedHost({
    required this.ip,
    this.mac,
    this.hostname,
    this.vendor,
    this.isGateway = false,
    this.isSelf = false,
    this.openPorts = const [],
    this.pingMs,
  });

  final String ip;
  final String? mac;
  final String? hostname;
  final String? vendor;
  final bool isGateway;
  final bool isSelf;

  /// Open ports found by the TCP probe (empty when the host was only seen
  /// in ARP, or when the port scan was skipped).
  final List<OpenPort> openPorts;

  /// Round-trip time of the liveness probe, when measured.
  final int? pingMs;

  /// A host with open Telnet/FTP or an old-looking banner is worth a look.
  bool get looksRisky => openPorts.any(
        (p) => p.port == 23 || p.port == 21,
      );

  /// Display name: hostname, else vendor, else IP.
  String get displayName => hostname ?? vendor ?? ip;

  factory ScannedHost.fromDevice(
    ConnectedDevice d, {
    bool isGateway = false,
    bool isSelf = false,
    List<OpenPort> openPorts = const [],
    int? pingMs,
  }) {
    return ScannedHost(
      ip: d.ip,
      mac: d.mac,
      hostname: d.hostname,
      vendor: d.vendor,
      isGateway: isGateway || d.isGateway,
      isSelf: isSelf,
      openPorts: openPorts,
      pingMs: pingMs,
    );
  }

  ScannedHost copyWith({List<OpenPort>? openPorts, String? hostname}) {
    return ScannedHost(
      ip: ip,
      mac: mac,
      hostname: hostname ?? this.hostname,
      vendor: vendor,
      isGateway: isGateway,
      isSelf: isSelf,
      openPorts: openPorts ?? this.openPorts,
      pingMs: pingMs,
    );
  }
}
