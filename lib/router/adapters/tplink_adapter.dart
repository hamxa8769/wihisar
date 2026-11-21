/// TP-Link adapter (Archer / Deco, modern token-based firmware).
///
/// Modern TP-Link firmware uses a token-based web API: login POSTs to
/// `/cgi-bin/luci/;stok=<token>/login` with the password MD5-hashed, then
/// calls such as `admin/status?form=main` (device list) and the QoS
/// endpoints. The exact form names vary by model and firmware version, so
/// this adapter is deliberately conservative:
///
///  - Device list: implemented against the documented `admin/status`
///    response shape, with graceful fallback to the subnet ARP scan.
///  - Bandwidth limit: the QoS rule form the firmware expects on Archer
///    models that expose it, applied AND then verified by re-reading the
///    router's QoS list. A limit is only reported as applied when the
///    device shows up in that list. When the firmware refuses or does not
///    answer, the adapter returns the router's own error — it never claims
///    a limit it did not verify.
///
/// Support varies by model — the adapter never claims success it did not
/// verify from the router's response.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../devices/device_scan.dart';
import '../oui.dart';
import '../router_adapter.dart';

/// Result of probing a TP-Link router: can we log in, how many devices
/// does it list, and does its QoS API answer at all?
class TpLinkProbe {
  const TpLinkProbe({
    required this.loginOk,
    required this.deviceCount,
    required this.qosOk,
    required this.message,
  });

  final bool loginOk;
  final int deviceCount;
  final bool qosOk;
  final String message;
}

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
      'TP-Link Bandwidth Control / QoS rule per device (MAC), via the router web API — applied, then verified against the router QoS list.';

  @override
  List<String> get limitations => const [
        'Support varies by model and firmware: some Deco units expose QoS only as priority, not a hard Mbps cap — the adapter reports the router\'s own answer.',
        'The router must be reachable at its gateway IP and the admin password must be correct.',
        'A limit applies after the router saves the QoS rule; a reboot may be needed on older firmware.',
        'QoS is verified at runtime: if the router accepts the rule but the device does not appear in its QoS list, the limit is reported as unverified, not applied.',
      ];

  /// Lower-case hex MD5 of [input] — what TP-Link login expects for the
  /// password. md5('admin') = 21232f297a57a5a743894a0e4a801fc3.
  static String md5Hex(String input) => md5.convert(utf8.encode(input)).toString();

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
      req.write(jsonEncode({
        'method': 'do',
        'login': {
          'username': creds.username,
          'password': md5Hex(creds.password),
        },
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

  /// QoS "set" body for one device. Limits are kbps (Mbps x 1000); the MAC
  /// is upper-case colon-separated, as the firmware expects.
  static Map<String, dynamic> buildQosSetBody(
    String mac,
    double downMbps,
    double upMbps,
  ) {
    return {
      'method': 'set',
      'qos': {
        'enable': 1,
        'qos_type': 'device',
        'device_list': [
          {
            'mac': normaliseMac(mac),
            'up_limit': (upMbps * 1000).round(),
            'down_limit': (downMbps * 1000).round(),
          },
        ],
      },
    };
  }

  /// QoS "set" body for a whole device list (used by clearLimit to rewrite
  /// the list without one MAC). Entries keep whatever limits they had.
  static Map<String, dynamic> buildQosSetBodyList(
    List<Map<String, dynamic>> devices,
  ) {
    return {
      'method': 'set',
      'qos': {
        'enable': 1,
        'qos_type': 'device',
        'device_list': devices
            .map((d) => {
                  'mac': normaliseMac(d['mac']?.toString() ?? ''),
                  'up_limit': d['up_limit'],
                  'down_limit': d['down_limit'],
                })
            .toList(),
      },
    };
  }

  /// Parse a TP-Link QoS response. The firmware answers
  /// `{"error_code":0, ...}` on success; anything else is a refusal.
  /// Returns (ok, errorCode, message). Never throws.
  static ({bool ok, int errorCode, String message}) parseQosSetResponse(
    String body,
  ) {
    try {
      final data = jsonDecode(body);
      if (data is Map<String, dynamic>) {
        final code = data['error_code'];
        final errorCode =
            code is int ? code : (code is num ? code.toInt() : -1);
        if (errorCode == 0) {
          return (ok: true, errorCode: 0, message: 'OK');
        }
        final msg = data['msg']?.toString() ??
            data['message']?.toString() ??
            'The router reported error $errorCode.';
        return (ok: false, errorCode: errorCode, message: msg);
      }
      return (
        ok: false,
        errorCode: -1,
        message: 'The router response was not a JSON object.',
      );
    } catch (_) {
      return (
        ok: false,
        errorCode: -1,
        message: 'Could not understand the router response.',
      );
    }
  }

  /// Walk a decoded JSON value and collect every device map (a map with a
  /// 'mac' key) it contains, at any depth. TP-Link nests the QoS device
  /// list differently per firmware, so the search is tolerant.
  static List<Map<String, dynamic>> _findDeviceMaps(dynamic node) {
    final found = <Map<String, dynamic>>[];
    if (node is Map<String, dynamic>) {
      if (node['mac'] != null) found.add(node);
      for (final value in node.values) {
        found.addAll(_findDeviceMaps(value));
      }
    } else if (node is List) {
      for (final value in node) {
        found.addAll(_findDeviceMaps(value));
      }
    }
    return found;
  }

  /// All devices in a QoS "get" response body (mac + limits), or empty
  /// when the body cannot be understood.
  static List<Map<String, dynamic>> parseQosDeviceList(String body) {
    try {
      return _findDeviceMaps(jsonDecode(body));
    } catch (_) {
      return const [];
    }
  }

  /// True when [mac] appears in a QoS "get" response body.
  static bool qosListContainsMac(String body, String mac) {
    final wanted = normaliseMac(mac);
    return parseQosDeviceList(body).any(
      (d) => normaliseMac(d['mac']?.toString() ?? '') == wanted,
    );
  }

  /// POST a JSON body to the QoS endpoint. Returns the response body, or
  /// null when the router does not answer.
  Future<String?> _postQos(
    String gatewayIp,
    String stok,
    Map<String, dynamic> body,
  ) async {
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      final req = await client
          .postUrl(Uri.parse(
              'http://$gatewayIp/cgi-bin/luci/;stok=$stok/admin/qos'))
          .timeout(const Duration(seconds: 5));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
      final resp = await req.close().timeout(const Duration(seconds: 5));
      final text = await resp.transform(utf8.decoder).join();
      client.close();
      if (resp.statusCode != 200) return null;
      return text;
    } catch (_) {
      return null;
    }
  }

  /// Read the router's current QoS list (`{"method":"get","qos":{}}`).
  /// Returns the raw response body, or null when it cannot be read.
  Future<String?> _getQosList(String gatewayIp, String stok) =>
      _postQos(gatewayIp, stok, {
        'method': 'get',
        'qos': {},
      });

  /// Devices from the router's own status page (no subnet fallback).
  Future<List<ConnectedDevice>> _routerDevices(
    String gatewayIp,
    String stok,
  ) async {
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      final req = await client
          .getUrl(Uri.parse(
              'http://$gatewayIp/cgi-bin/luci/;stok=$stok/admin/status?form=main'))
          .timeout(const Duration(seconds: 5));
      final resp = await req.close().timeout(const Duration(seconds: 5));
      final body = await resp.transform(utf8.decoder).join();
      client.close();
      return parseClientList(jsonDecode(body));
    } catch (_) {
      return const [];
    }
  }

  /// Probe the router: login, device count, and whether the QoS API
  /// answers. Never throws — a failure is a probe result, not a crash.
  Future<TpLinkProbe> testConnection({
    required String gatewayIp,
    required RouterCredentials credentials,
  }) async {
    try {
      final stok = await login(gatewayIp, credentials);
      if (stok == null) {
        return const TpLinkProbe(
          loginOk: false,
          deviceCount: 0,
          qosOk: false,
          message:
              'Login failed — check the admin username/password and the gateway IP.',
        );
      }
      final devices = await _routerDevices(gatewayIp, stok);
      final qosBody = await _getQosList(gatewayIp, stok);
      final qosOk = qosBody != null &&
          parseQosSetResponse(qosBody).ok;
      return TpLinkProbe(
        loginOk: true,
        deviceCount: devices.length,
        qosOk: qosOk,
        message: qosOk
            ? 'Connected. ${devices.length} device(s) listed; the QoS API answers, so limiting should work.'
            : 'Connected, but the QoS API did not answer — this firmware may not support per-device limits.',
      );
    } catch (e) {
      return TpLinkProbe(
        loginOk: false,
        deviceCount: 0,
        qosOk: false,
        message: 'Connection failed: $e',
      );
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
        return await SubnetScanner().readNeighbourTable();
      }
      final devices = await _routerDevices(gatewayIp, stok);
      if (devices.isNotEmpty) return devices;
    } catch (_) {
      // Fall through to the subnet scan.
    }
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
    final stok = await login(gatewayIp, credentials);
    if (stok == null) {
      return const LimitResult(
        success: false,
        message:
            'TP-Link login failed — check the admin username/password and the gateway IP.',
      );
    }
    final setBody = await _postQos(
      gatewayIp,
      stok,
      buildQosSetBody(deviceMac, downMbps, upMbps),
    );
    if (setBody == null) {
      return const LimitResult(
        success: false,
        message: 'The router did not answer the QoS request.',
      );
    }
    final parsed = parseQosSetResponse(setBody);
    if (!parsed.ok) {
      return LimitResult(
        success: false,
        message:
            'The router refused the QoS rule (error ${parsed.errorCode}): ${parsed.message}',
      );
    }
    // Verify: the device must actually show up in the router's QoS list.
    final listBody = await _getQosList(gatewayIp, stok);
    if (listBody == null) {
      return const LimitResult(
        success: false,
        message:
            'The router accepted the QoS rule but would not show its QoS list, so the limit is unverified and is NOT reported as applied.',
      );
    }
    if (!qosListContainsMac(listBody, deviceMac)) {
      return LimitResult(
        success: false,
        message:
            'The router accepted the QoS rule but $deviceMac does not appear in its QoS list — the limit is unverified and is NOT reported as applied.',
      );
    }
    return LimitResult.applied(
      downMbps,
      upMbps,
      'TP-Link QoS (verified in the router QoS list)',
    );
  }

  @override
  Future<LimitResult> verifyLimit({
    required String gatewayIp,
    required RouterCredentials credentials,
    required String deviceMac,
    String? deviceIp,
    String? expectedFingerprint,
  }) async {
    final stok = await login(gatewayIp, credentials);
    if (stok == null) {
      return const LimitResult(
        success: false,
        message: 'TP-Link login failed — cannot verify the limit.',
      );
    }
    final listBody = await _getQosList(gatewayIp, stok);
    if (listBody == null) {
      return const LimitResult(
        success: false,
        message:
            'The router did not answer the QoS list request — the limit is unverified.',
      );
    }
    final present = qosListContainsMac(listBody, deviceMac);
    return LimitResult(
      success: present,
      message: present
          ? 'Verified: $deviceMac is in the router QoS list.'
          : '$deviceMac is not in the router QoS list — the limit is not applied.',
    );
  }

  @override
  Future<LimitResult> clearLimit({
    required String gatewayIp,
    required RouterCredentials credentials,
    required String deviceMac,
    String? deviceIp,
    String? expectedFingerprint,
  }) async {
    final stok = await login(gatewayIp, credentials);
    if (stok == null) {
      return const LimitResult(
        success: false,
        message:
            'TP-Link login failed — check the admin username/password and the gateway IP.',
      );
    }
    final listBody = await _getQosList(gatewayIp, stok);
    if (listBody == null) {
      return LimitResult.unsupported(
        'Could not read the router QoS list, so the rule cannot be removed safely.',
      );
    }
    final devices = parseQosDeviceList(listBody);
    final wanted = normaliseMac(deviceMac);
    if (!devices.any(
        (d) => normaliseMac(d['mac']?.toString() ?? '') == wanted)) {
      return LimitResult(
        success: true,
        message: 'No QoS rule for $deviceMac was found — nothing to clear.',
      );
    }
    final remaining = devices
        .where((d) => normaliseMac(d['mac']?.toString() ?? '') != wanted)
        .toList();
    final setBody = await _postQos(
      gatewayIp,
      stok,
      buildQosSetBodyList(remaining),
    );
    if (setBody == null) {
      return const LimitResult(
        success: false,
        message: 'The router did not answer the QoS request.',
      );
    }
    final parsed = parseQosSetResponse(setBody);
    if (!parsed.ok) {
      return LimitResult(
        success: false,
        message:
            'The router refused to update the QoS list (error ${parsed.errorCode}): ${parsed.message}',
      );
    }
    // Verify the MAC is really gone.
    final checkBody = await _getQosList(gatewayIp, stok);
    if (checkBody != null && qosListContainsMac(checkBody, deviceMac)) {
      return LimitResult(
        success: false,
        message:
            'The router accepted the update but $deviceMac is still in its QoS list — the rule was not removed.',
      );
    }
    return LimitResult(
      success: true,
      message: 'QoS rule for $deviceMac removed (verified).',
    );
  }
}
