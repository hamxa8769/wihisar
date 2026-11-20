/// OpenWrt adapter (LuCI / SSH).
///
/// OpenWrt is the one platform where per-device limiting is genuinely
/// supported, via SQM (cake with `dual-dsthost` per-IP fairness) and HTB
/// queues (`tc`). This adapter:
///
///  - Lists devices from the router's DHCP leases (`/tmp/dhcp.leases`)
///    and ARP table — via LuCI RPC or SSH, both of which the user must
///    explicitly enable with their own root credentials.
///  - Generates the exact `tc` HTB commands that enforce a per-device
///    limit, so the user (or a future SSH executor) can review them before
///    they run. This MVP does NOT execute SSH commands by itself: executing
///    remote shell commands from a phone app is a big trust step, so v0.1
///    shows the commands and applies them only through LuCI RPC where
///    available.
///
/// SQM background: plain SQM gives per-flow fairness, not a hard per-device
/// cap. A hard cap needs an HTB class per device (or per-IP) on the LAN
/// side, which is what [htbCommandsFor] generates.
library;

import '../../devices/device_scan.dart';
import '../router_adapter.dart';

class OpenWrtAdapter implements RouterAdapter {
  @override
  String get profileId => 'openwrt';

  @override
  String get vendor => 'OpenWrt';

  @override
  bool get supportsDeviceList => true;

  @override
  bool get supportsBandwidthLimit => true;

  @override
  String get limitMethodDescription =>
      'HTB queue per device IP on the LAN interface (tc), plus SQM cake with dual-dsthost fairness for the whole link.';

  @override
  List<String> get limitations => const [
        'Requires an OpenWrt router with SSH or LuCI RPC access (root credentials you set yourself).',
        'v0.1 generates the exact tc commands for review; automatic SSH execution is a v0.2 item.',
        'HTB limits apply per IP — a device that changes IP needs its rule re-applied (use a DHCP static lease).',
      ];

  /// Parse `/tmp/dhcp.leases` content.
  /// Format per line: `<expiry> <mac> <ip> <hostname> <client-id>`
  static List<ConnectedDevice> parseDhcpLeases(String content) {
    final devices = <ConnectedDevice>[];
    for (final line in content.split('\n')) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length < 3) continue;
      devices.add(ConnectedDevice(
        ip: parts[2],
        mac: parts[1],
        hostname: parts.length > 3 && parts[3] != '*' ? parts[3] : null,
      ).withVendor());
    }
    return dedupeByMac(devices);
  }

  /// HTB `tc` commands that cap one device IP at [downMbps] down /
  /// [upMbps] up on the LAN interface (default `br-lan`).
  /// Downstream shaping is applied on the LAN side (egress towards the
  /// device); upstream on the WAN side. These are returned as text for
  /// review — v0.1 does not run them.
  static List<String> htbCommandsFor({
    required String deviceIp,
    required double downMbps,
    required double upMbps,
    String lanInterface = 'br-lan',
  }) {
    final downKbit = (downMbps * 1000).round();
    final upKbit = (upMbps * 1000).round();
    // Precomputed so `tc` gets `5000kbit` (no space) without interpolation.
    final downRate = '${downKbit}kbit';
    final upRate = '${upKbit}kbit';
    final classId = deviceIp.split('.').last;
    return [
      '# Per-device limit for $deviceIp: $downMbps Mbps down / $upMbps Mbps up',
      '# Run on the OpenWrt router over SSH (as root).',
      'tc qdisc add dev $lanInterface root handle 1: htb default 30',
      'tc class add dev $lanInterface parent 1: classid 1:$classId htb rate $downRate ceil $downRate',
      'tc filter add dev $lanInterface protocol ip parent 1:0 prio 1 u32 match ip dst $deviceIp flowid 1:$classId',
      '# Upload cap (on the WAN interface, replace "wan" with your WAN device):',
      '# tc class add dev wan parent 1: classid 1:$classId htb rate $upRate ceil $upRate',
      '# tc filter add dev wan protocol ip parent 1:0 prio 1 u32 match ip src $deviceIp flowid 1:$classId',
    ];
  }

  @override
  Future<List<ConnectedDevice>> listDevices({
    required String gatewayIp,
    required RouterCredentials credentials,
  }) async {
    // v0.1: no SSH client is bundled (keeps the app lightweight). The
    // device list comes from the subnet scan; the LuCI-RPC/SSH path that
    // reads /tmp/dhcp.leases directly is a v0.2 item.
    return SubnetScanner().readNeighbourTable();
  }

  @override
  Future<LimitResult> setLimit({
    required String gatewayIp,
    required RouterCredentials credentials,
    required String deviceMac,
    required double downMbps,
    required double upMbps,
  }) async {
    // Without the device IP we cannot generate the HTB rule; the UI passes
    // the IP through the device list. This method is the honest boundary:
    // v0.1 returns the commands for the user to run, it does not pretend
    // to have applied them.
    return LimitResult.unsupported(
      'OpenWrt limiting is ready as reviewed commands, not as silent remote execution yet. '
      'Pick the device in the Devices tab to see its exact `tc` HTB commands, run them over SSH as root, '
      'and the limit will hold. Automatic SSH apply is planned for v0.2.',
    );
  }

  @override
  Future<LimitResult> clearLimit({
    required String gatewayIp,
    required RouterCredentials credentials,
    required String deviceMac,
  }) async {
    return LimitResult.unsupported(
      'Clear a limit with: `tc qdisc del dev br-lan root` (removes all HTB rules on br-lan) or delete the single class. Automatic clear is planned for v0.2.',
    );
  }
}
