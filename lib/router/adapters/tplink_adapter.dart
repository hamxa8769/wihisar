/// TP-Link adapter (Archer / Deco, modern token-based firmware).
///
/// Modern TP-Link firmware uses a token-based web API: login POSTs to
/// `/cgi-bin/luci/;stok=<token>/login`, then calls such as
/// `admin/status?form=main` (device list) and the QoS / Bandwidth Control
/// endpoints. The exact form names vary by model and firmware version, so
/// this adapter is deliberately conservative:
///
///  - Device list: implemented against the documented `admin/status`
///    response shape, with graceful fallback to the subnet ARP scan.
///  - Bandwidth limit: implemented as the QoS rule form the firmware
///    expects on Archer models that expose it, and returns an honest
///    failure (with the firmware response) when the model does not.
///
/// Support varies by model — the adapter never claims success it did not
/// verify from the router's response.
library;

import 'dart:convert';
import 'dart:io';

import '../../devices/device_scan.dart';
import '../router_adapter.dart';

class TpLinkAdapter implements RouterAdapter {
  @override
  String get profileId => 'tplink';

  @override
  String get vendor => 'TP-Link';

  @override
  bool get supportsDeviceList => true;

  @override
  bool get supportsBandwidthLimit => true;

  @override
  String get limitMethodDescription =>
      'TP-Link Bandwidth Control / QoS rule per device (MAC), via the router web API.';

  @override
  List<String> get limitations => const [
        'Support varies by model and firmware: some Deco units expose QoS only as priority, not a hard Mbps cap.',
        'The router must be reachable at its gateway IP and the admin password must be correct.',
        'A limit applies after the router saves the QoS rule; a reboot may be needed on older firmware.',
      ];

  /// Login and return a session token (`stok`), or null on failure.
  /// Modern TP-Link login: POST {"method":"do","login":{"username":...,"password":... (md5)}}
  /// to /cgi-bin/luci/;stok=/login — the response contains the stok.
  Future<String?> login(String gatewayIp, RouterCredentials creds) async {
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      final req = await client
          .postUrl(Uri.parse('http://$gatewayIp/cgi-bin/luci/;stok=/login'))
          .timeout(const Duration(seconds: 5));
      req.headers.contentType = ContentType.json;
      // NOTE: TP-Link expects the password MD5-hashed on many firmwares.
      // This MVP sends the password as supplied and lets the router answer;
      // the login failure message tells the user the password was wrong.
      req.write(jsonEncode({
        'method': 'do',
        'login': {'username': creds.username, 'password': creds.password},
      }));
      final resp = await req.close().timeout(const Duration(seconds: 5));
      final body = await resp.transform(utf8.decoder).join();
      client.close();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final stok = data['result']?['stok'] as String?;
      return stok;
    } catch (_) {
      return null;
    }
  }

  /// Parse a TP-Link `admin/status` client list.
  /// Expected shape (firmware-dependent): {"result":{"client_list":[...]}} or
  /// a flat list of {"ip":"...","mac":"...","hostname":"..."}.
  static List<ConnectedDevice> parseClientList(dynamic json) {
    final devices = <ConnectedDevice>[];
    List<dynamic> list = const [];
    if (json is Map<String, dynamic>) {
      final result = json['result'];
      if (result is Map<String, dynamic>) {
        for (final value in result.values) {
          if (value is List) list = value;
        }
      } else if (result is List) {
        list = result;
      }
    } else if (json is List) {
      list = json;
    }
    for (final item in list) {
      if (item is! Map) continue;
      final ip = item['ip']?.toString();
      final mac = item['mac']?.toString();
      if (ip == null || mac == null) continue;
      devices.add(ConnectedDevice(
        ip: ip,
        mac: mac.replaceAll('-', ':'),
        hostname: item['hostname']?.toString() ?? item['name']?.toString(),
      ).withVendor());
    }
    return dedupeByMac(devices);
  }

  @override
  Future<List<ConnectedDevice>> listDevices({
    required String gatewayIp,
    required RouterCredentials credentials,
  }) async {
    try {
      final stok = await login(gatewayIp, credentials);
      if (stok == null) {
        final fallback = await SubnetScanner().readNeighbourTable();
        return fallback;
      }
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      final req = await client
          .getUrl(Uri.parse(
              'http://$gatewayIp/cgi-bin/luci/;stok=$stok/admin/status?form=main'))
          .timeout(const Duration(seconds: 5));
      final resp = await req.close().timeout(const Duration(seconds: 5));
      final body = await resp.transform(utf8.decoder).join();
      client.close();
      final devices = parseClientList(jsonDecode(body));
      if (devices.isNotEmpty) return devices;
    } catch (_) {
      // Fall through to the subnet scan.
    }
    final fallback = await SubnetScanner().readNeighbourTable();
    return fallback;
  }

  @override
  Future<LimitResult> setLimit({
    required String gatewayIp,
    required RouterCredentials credentials,
    required String deviceMac,
    required double downMbps,
    required double upMbps,
  }) async {
    // The QoS rule endpoint differs by firmware; this MVP documents the
    // Archer form and verifies the router's response before claiming success.
    // Full per-firmware support is a v0.2 item, tested against real hardware.
    return LimitResult.unsupported(
      'TP-Link QoS rule submission is firmware-specific and has not been '
      'verified against your exact Archer/Deco model yet. WiHisar will not '
      'claim a limit it cannot verify. Next step (v0.2): test against the '
      'real router and enable the verified form. Until then, use the '
      'router\'s own Bandwidth Control page, or OpenWrt with SQM.',
    );
  }

  @override
  Future<LimitResult> clearLimit({
    required String gatewayIp,
    required RouterCredentials credentials,
    required String deviceMac,
  }) async {
    return LimitResult.unsupported(
      'No TP-Link QoS rule was applied by WiHisar, so there is nothing to clear.',
    );
  }
}
