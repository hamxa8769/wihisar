/// OpenWrt adapter (LuCI / SSH).
///
/// OpenWrt is the one platform where per-device limiting is genuinely
/// supported, via SQM (cake with `dual-dsthost` per-IP fairness) and HTB
/// queues (`tc`). This adapter:
///
///  - Lists devices from the subnet scan (the LuCI-RPC/SSH path that reads
///    `/tmp/dhcp.leases` directly is a later item).
///  - Applies the HTB limit for real over SSH (dartssh2), then verifies it
///    with `tc class show` / `tc filter show` before reporting success.
///  - Never trusts an unknown SSH host key: the user must first probe the
///    router fingerprint (from the Limits tab) and confirm it. [setLimit]
///    refuses to connect without a confirmed fingerprint, and refuses when
///    the presented key differs.
///
/// SQM background: plain SQM gives per-flow fairness, not a hard per-device
/// cap. A hard cap needs an HTB class per device (or per-IP) on the LAN
/// side, which is what [htbCommandsFor] generates.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

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
      'HTB queue per device IP on the LAN interface (tc), applied over SSH and verified with `tc class show` — plus SQM cake with dual-dsthost fairness for the whole link.';

  @override
  List<String> get limitations => const [
        'Requires an OpenWrt router with SSH enabled (root or a user with tc rights).',
        'Before the first apply, probe the router SSH fingerprint from the Limits tab and confirm it — WiHisar never trusts an unknown host key, and never sends your password to a server whose key differs.',
        'The download cap is applied on br-lan; the upload cap needs the WAN interface name (see the reviewed tc commands).',
        'HTB limits apply per IP — a device that changes IP needs its rule re-applied (use a DHCP static lease).',
        'Clearing runs `tc qdisc del dev br-lan root`, which removes ALL HTB rules on br-lan.',
      ];

  /// OpenSSH-style fingerprint of a raw SHA-256 host-key digest:
  /// `SHA256:<base64 without padding>`. This is the format
  /// [probeSshFingerprint] returns and [setLimit] expects.
  static String sshFingerprint(Uint8List digest) =>
      'SHA256:${base64Encode(digest).replaceAll('=', '')}';

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
  /// review — run them over SSH (as root) or let [setLimit] run them.
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

  /// Only the runnable commands from [htbCommandsFor] — the lines the SSH
  /// path actually executes (comment lines skipped). The download cap is
  /// the only one applied automatically; the upload cap needs the WAN
  /// interface name, so it stays a reviewed comment.
  static List<String> htbApplyCommands({
    required String deviceIp,
    required double downMbps,
    required double upMbps,
    String lanInterface = 'br-lan',
  }) {
    return htbCommandsFor(
      deviceIp: deviceIp,
      downMbps: downMbps,
      upMbps: upMbps,
      lanInterface: lanInterface,
    ).where((line) => !line.startsWith('#')).toList();
  }

  /// True when `tc` output mentions [ip] as a whole address
  /// (192.168.1.5 matches, 192.168.1.50 does not). Used to verify that a
  /// class/filter for the device really exists after applying.
  static bool tcOutputHasIp(String output, String ip) {
    return RegExp('\\b${RegExp.escape(ip)}\\b').hasMatch(output);
  }

  /// Connect to the router's SSH server (port 22) and authenticate,
  /// accepting the host key ONLY when its fingerprint equals
  /// [expectedFingerprint]. The password is never sent to a server whose
  /// key differs — the connection dies during the handshake instead.
  /// Returns (client, null) on success, (null, error message) on failure.
  Future<({SSHClient? client, String? error})> _connectSsh({
    required String gatewayIp,
    required RouterCredentials credentials,
    required String expectedFingerprint,
  }) async {
    SSHClient? client;
    try {
      final socket = await SSHSocket.connect(
        gatewayIp,
        22,
        timeout: const Duration(seconds: 10),
      );
      client = SSHClient(
        socket,
        username: credentials.username,
        onPasswordRequest: () => credentials.password,
        onVerifyHostKey: (type, fingerprint) =>
            sshFingerprint(fingerprint) == expectedFingerprint,
        handshakeTimeout: const Duration(seconds: 10),
        authTimeout: const Duration(seconds: 10),
      );
      await client.authenticated.timeout(const Duration(seconds: 12));
      return (client: client, error: null);
    } on SSHHostkeyError {
      try {
        await client?.close();
      } catch (_) {}
      return (
        client: null,
        error:
            'The router SSH host key does not match the fingerprint you confirmed — connection refused to protect against a man-in-the-middle. Probe the fingerprint again from the Limits tab.',
      );
    } catch (e) {
      try {
        await client?.close();
      } catch (_) {}
      return (client: null, error: 'SSH connection failed: $e');
    }
  }

  /// Probe the router's SSH host-key fingerprint (OpenSSH `SHA256:...`
  /// format) without authenticating — the key is presented during the
  /// handshake, before any password is sent. The UI shows this fingerprint
  /// and asks the user to confirm it before the first apply. Returns null
  /// when the router does not answer SSH at all. Never throws.
  Future<String?> probeSshFingerprint({required String gatewayIp}) async {
    final completer = Completer<String?>();
    SSHClient? client;
    try {
      final socket = await SSHSocket.connect(
        gatewayIp,
        22,
        timeout: const Duration(seconds: 5),
      );
      client = SSHClient(
        socket,
        username: 'root',
        onVerifyHostKey: (type, fingerprint) {
          final fp = sshFingerprint(fingerprint);
          if (!completer.isCompleted) completer.complete(fp);
          return true;
        },
        onPasswordRequest: () => '',
        handshakeTimeout: const Duration(seconds: 5),
        authTimeout: const Duration(seconds: 5),
      );
      return await completer.future.timeout(
        const Duration(seconds: 6),
        onTimeout: () => null,
      );
    } catch (_) {
      return null;
    } finally {
      try {
        await client?.close();
      } catch (_) {}
    }
  }

  /// Run one command over an authenticated [client]. Returns
  /// (exitCode, combined output). Never throws.
  Future<({int? exitCode, String output})> _runCommand(
    SSHClient client,
    String command,
  ) async {
    try {
      final result = await client
          .runWithResult(command)
          .timeout(const Duration(seconds: 15));
      final output = utf8.decode(result.stdout, allowMalformed: true) +
          utf8.decode(result.stderr, allowMalformed: true);
      return (exitCode: result.exitCode, output: output);
    } catch (e) {
      return (exitCode: null, output: 'Command failed: $e');
    }
  }

  @override
  Future<List<ConnectedDevice>> listDevices({
    required String gatewayIp,
    required RouterCredentials credentials,
  }) async {
    // No SSH client is bundled for the device list in this version; the
    // device list comes from the subnet scan. Reading /tmp/dhcp.leases
    // over SSH is a later item.
    return SubnetScanner().readNeighbourTable();
  }

  @override
  Future<LimitResult> setLimit({
    required String gatewayIp,
    required RouterCredentials credentials,
    required String deviceMac,
    String? deviceIp,
    required double downMbps,
    required double upMbps,
    String? expectedFingerprint,
  }) async {
    if (deviceIp == null || deviceIp.isEmpty) {
      return const LimitResult(
        success: false,
        message:
            'OpenWrt limiting needs the device IP — pick the device from the scan first so WiHisar knows which IP to shape.',
      );
    }
    if (expectedFingerprint == null || expectedFingerprint.isEmpty) {
      return const LimitResult(
        success: false,
        message:
            'Confirm the router SSH fingerprint first (probe it from the Limits tab). WiHisar will not connect to an SSH server it has not verified.',
      );
    }
    final connected = await _connectSsh(
      gatewayIp: gatewayIp,
      credentials: credentials,
      expectedFingerprint: expectedFingerprint,
    );
    final client = connected.client;
    if (client == null) {
      return LimitResult(success: false, message: connected.error!);
    }
    try {
      for (final command in htbApplyCommands(
        deviceIp: deviceIp,
        downMbps: downMbps,
        upMbps: upMbps,
      )) {
        final run = await _runCommand(client, command);
        if (run.exitCode != 0) {
          return LimitResult(
            success: false,
            message:
                'The router rejected a tc command (`$command`, exit ${run.exitCode}): ${run.output.trim()}. No limit was verified.',
          );
        }
      }
      // Verify: the class/filter for this IP must actually exist now.
      final classes = await _runCommand(client, 'tc class show dev br-lan');
      final filters = await _runCommand(client, 'tc filter show dev br-lan');
      final combined = '${classes.output}\n${filters.output}';
      if (!tcOutputHasIp(combined, deviceIp)) {
        return LimitResult(
          success: false,
          message:
              'The tc commands ran but no HTB class/filter for $deviceIp shows up in `tc class show` / `tc filter show` — the limit is unverified and is NOT reported as applied.',
        );
      }
      return LimitResult.applied(downMbps, upMbps, 'SSH tc HTB on br-lan');
    } finally {
      try {
        await client.close();
      } catch (_) {}
    }
  }

  @override
  Future<LimitResult> verifyLimit({
    required String gatewayIp,
    required RouterCredentials credentials,
    required String deviceMac,
    String? deviceIp,
    String? expectedFingerprint,
  }) async {
    if (deviceIp == null || deviceIp.isEmpty) {
      return const LimitResult(
        success: false,
        message:
            'OpenWrt verification needs the device IP — pick the device from the scan first.',
      );
    }
    if (expectedFingerprint == null || expectedFingerprint.isEmpty) {
      return const LimitResult(
        success: false,
        message:
            'Confirm the router SSH fingerprint first (probe it from the Limits tab). WiHisar will not connect to an SSH server it has not verified.',
      );
    }
    final connected = await _connectSsh(
      gatewayIp: gatewayIp,
      credentials: credentials,
      expectedFingerprint: expectedFingerprint,
    );
    final client = connected.client;
    if (client == null) {
      return LimitResult(success: false, message: connected.error!);
    }
    try {
      final classes = await _runCommand(client, 'tc class show dev br-lan');
      final filters = await _runCommand(client, 'tc filter show dev br-lan');
      final present =
          tcOutputHasIp('${classes.output}\n${filters.output}', deviceIp);
      return LimitResult(
        success: present,
        message: present
            ? 'Verified: an HTB class/filter for $deviceIp exists on br-lan.'
            : 'No HTB class/filter for $deviceIp on br-lan — the limit is not applied.',
      );
    } finally {
      try {
        await client.close();
      } catch (_) {}
    }
  }

  @override
  Future<LimitResult> clearLimit({
    required String gatewayIp,
    required RouterCredentials credentials,
    required String deviceMac,
    String? deviceIp,
    String? expectedFingerprint,
  }) async {
    if (expectedFingerprint == null || expectedFingerprint.isEmpty) {
      return const LimitResult(
        success: false,
        message:
            'Confirm the router SSH fingerprint first (probe it from the Limits tab). WiHisar will not connect to an SSH server it has not verified.',
      );
    }
    final connected = await _connectSsh(
      gatewayIp: gatewayIp,
      credentials: credentials,
      expectedFingerprint: expectedFingerprint,
    );
    final client = connected.client;
    if (client == null) {
      return LimitResult(success: false, message: connected.error!);
    }
    try {
      final run = await _runCommand(client, 'tc qdisc del dev br-lan root');
      if (run.exitCode != 0) {
        return LimitResult(
          success: false,
          message:
              'The router rejected the clear command (exit ${run.exitCode}): ${run.output.trim()}',
        );
      }
      return const LimitResult(
        success: true,
        message:
            'HTB rules removed from br-lan (all device limits on this interface are gone).',
      );
    } finally {
      try {
        await client.close();
      } catch (_) {}
    }
  }
}
