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

  /// A host with Telnet/FTP/RDP/VNC open is worth a look: those are
  /// clear-text or remote-desktop services that should not be exposed on a
  /// home network without a reason.
  bool get looksRisky => openPorts.any(
        (p) => p.port == 23 || p.port == 21 || p.port == 3389 || p.port == 5900,
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

/// Best-effort guess at what kind of device [h] is, from its hostname,
/// vendor and open ports. A heuristic, not a fact — the UI labels it as a
/// guess. One of 'Router', 'Camera', 'Printer', 'Phone', 'Computer',
/// 'Smart TV', 'IoT', 'Unknown'.
String guessDeviceKind(ScannedHost h) {
  final vendor = (h.vendor ?? '').toLowerCase();
  final host = (h.hostname ?? '').toLowerCase();
  final ports = h.openPorts.map((p) => p.port).toSet();
  bool has(List<String> words) => words.any(host.contains);

  if (h.isGateway) return 'Router';
  // Hostname hints are the most specific signal, so they win.
  if (has(['router', 'gateway', 'access-point'])) return 'Router';
  if (has(['tv', 'bravia', 'roku', 'firetv', 'androidtv', 'appletv', 'chromecast'])) {
    return 'Smart TV';
  }
  if (has(['camera', 'cam-', 'cam_', 'nvr', 'dvr', 'doorbell'])) {
    return 'Camera';
  }
  if (has(['printer', 'print'])) return 'Printer';
  if (has(['iphone', 'ipad', 'android', 'pixel', 'galaxy', 'oneplus', 'phone', 'mobile'])) {
    return 'Phone';
  }
  if (has(['macbook', 'imac', 'desktop', 'laptop', 'pc-', 'windows', 'raspberry', 'server', 'nas'])) {
    return 'Computer';
  }
  if (has(['nest', 'echo', 'alexa', 'homepod'])) return 'IoT';
  // Open ports: RTSP is a camera, IPP is a printer, SSH/SMB is a computer.
  if (ports.contains(554)) return 'Camera';
  if (ports.contains(631)) return 'Printer';
  if (ports.contains(22) || ports.contains(445) || ports.contains(139)) {
    return 'Computer';
  }
  // Vendor keywords.
  if (vendor.contains('hikvision') ||
      vendor.contains('dahua') ||
      vendor.contains('axis') ||
      vendor.contains('reolink') ||
      vendor.contains('amcrest') ||
      vendor.contains('foscam') ||
      vendor.contains('wyze') ||
      vendor.contains('arlo') ||
      vendor.contains('uniview')) {
    return 'Camera';
  }
  if (vendor.contains('hp') ||
      vendor.contains('canon') ||
      vendor.contains('epson') ||
      vendor.contains('brother') ||
      vendor.contains('kyocera') ||
      vendor.contains('xerox') ||
      vendor.contains('lexmark') ||
      vendor.contains('ricoh')) {
    return 'Printer';
  }
  if (vendor.contains('espressif')) return 'IoT';
  if (vendor.contains('roku')) return 'Smart TV';
  if (vendor.contains('lg') ||
      vendor.contains('sony') ||
      vendor.contains('tcl') ||
      vendor.contains('hisense') ||
      vendor.contains('vizio')) {
    return 'Smart TV';
  }
  if (vendor.contains('amazon')) return 'IoT';
  if (vendor.contains('apple') ||
      vendor.contains('samsung') ||
      vendor.contains('xiaomi') ||
      vendor.contains('huawei') ||
      vendor.contains('oppo') ||
      vendor.contains('vivo') ||
      vendor.contains('oneplus') ||
      vendor.contains('realme') ||
      vendor.contains('nokia') ||
      vendor.contains('google')) {
    return 'Phone';
  }
  if (vendor.contains('intel') ||
      vendor.contains('realtek') ||
      vendor.contains('dell') ||
      vendor.contains('lenovo') ||
      vendor.contains('asus') ||
      vendor.contains('acer') ||
      vendor.contains('msi') ||
      vendor.contains('microsoft') ||
      vendor.contains('raspberry') ||
      vendor.contains('qualcomm') ||
      vendor.contains('broadcom') ||
      vendor.contains('cisco')) {
    return 'Computer';
  }
  return 'Unknown';
}
