/// V-SOL adapter.
///
/// V-SOL ONU/ONT web UIs differ by model and firmware, but they share the
/// same shape: a login page at the gateway IP, then a status / DHCP-client
/// page listing connected devices.
///
/// Honest capability:
///  - Device list: YES (via the DHCP client list after login; the exact
///    page path varies by firmware, so this adapter tries the known paths
///    in order and reports which one worked). Login is tried two ways:
///    HTTP Basic Auth first, then a form POST (`/login.cgi`,
///    `/goform/login`) whose session cookie is reused for the page fetches.
///  - Bandwidth limit: NO. Most V-SOL ONU web UIs expose no per-device
///    bandwidth control at all. [setLimit] therefore returns an honest
///    unsupported result instead of pretending. Fallback is documented in
///    [limitations] and in the README.
///
/// Defaults (public knowledge, shown so the user can log in to their OWN
/// unit and change them): older ONUs 192.168.1.1 admin/stdONU101; newer
/// V-SOL routers 192.168.131.1 with no default password on first login.
library;

import 'dart:convert';
import 'dart:io';

import '../../devices/device_scan.dart';
import '../router_adapter.dart';

class VsolAdapter implements RouterAdapter {
  @override
  String get profileId => 'vsol';

  @override
  String get vendor => 'V-SOL';

  @override
  bool get supportsDeviceList => true;

  @override
  bool get supportsBandwidthLimit => false;

  @override
  String get limitMethodDescription =>
      'Not supported on V-SOL ONU web UI — no per-device limit control.';

  @override
  List<String> get limitations => const [
        'V-SOL ONU web UIs have no per-device bandwidth limit setting.',
        'Device list depends on firmware: the DHCP-client page path varies by model.',
        'To actually limit devices: put the V-SOL in bridge mode behind an OpenWrt router (then limit there with SSH), or use the router\'s own MAC-filter page to block a device outright — WiHisar cannot set a speed cap on the V-SOL itself.',
      ];

  /// Candidate DHCP-client page paths, tried in order. Firmware varies.
  static const List<String> dhcpPagePaths = [
    '/dhcp_clients.asp',
    '/lan_dhcp.asp',
    '/status_dhcp.asp',
    '/cgi-bin/dhcp_clients.cgi',
    '/cgi-bin/status_dhcp.cgi',
    '/lan_dhcp_clients.asp',
    '/status_lan.asp',
    '/dhcp_clients_list.asp',
    '/goform/dhcp_clients',
  ];

  /// Candidate form-login paths, tried in order.
  static const List<String> loginPaths = [
    '/login.cgi',
    '/goform/login',
  ];

  /// URL-encoded form body for the V-SOL login form.
  static String buildLoginFormBody(String user, String pass) =>
      'username=${Uri.encodeComponent(user)}'
      '&password=${Uri.encodeComponent(pass)}';

  /// Extract the `name=value` session cookie from a Set-Cookie header
  /// value (everything before the first `;`), or null when there is none.
  static String? parseSessionCookie(String? setCookieHeader) {
    if (setCookieHeader == null) return null;
    final first = setCookieHeader.split(';').first.trim();
    if (first.isEmpty || !first.contains('=')) return null;
    return first;
  }

  /// GET a page with the given headers. Returns the body on HTTP 200,
  /// null on anything else (including network errors).
  Future<String?> _getWithHeaders(
    String gatewayIp,
    String path,
    Map<String, String> headers,
  ) async {
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      final req = await client
          .getUrl(Uri.parse('http://$gatewayIp$path'))
          .timeout(const Duration(seconds: 5));
      headers.forEach(req.headers.set);
      final resp = await req.close().timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) {
        client.close();
        return null;
      }
      final body = await resp.transform(utf8.decoder).join();
      client.close();
      return body;
    } catch (_) {
      return null;
    }
  }

  /// Try the form login and return the session cookie, or null when the
  /// router does not set one. Tries each login path in order.
  Future<String?> _formLogin(
    String gatewayIp,
    RouterCredentials creds,
  ) async {
    for (final path in loginPaths) {
      try {
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 5);
        final req = await client
            .postUrl(Uri.parse('http://$gatewayIp$path'))
            .timeout(const Duration(seconds: 5));
        req.headers.contentType =
            ContentType('application', 'x-www-form-urlencoded');
        req.write(buildLoginFormBody(creds.username, creds.password));
        final resp = await req.close().timeout(const Duration(seconds: 5));
        final cookies = resp.headers['set-cookie'];
        client.close();
        for (final cookie in cookies ?? const <String>[]) {
          final session = parseSessionCookie(cookie);
          if (session != null) return session;
        }
      } catch (_) {
        // Try the next login path.
      }
    }
    return null;
  }

  /// Fetch a page from the router: HTTP Basic Auth first, then form login
  /// + session cookie. Returns null on failure.
  Future<String?> _fetchPage(
    String gatewayIp,
    String path,
    RouterCredentials creds,
  ) async {
    final auth =
        base64Encode(utf8.encode('${creds.username}:${creds.password}'));
    final basic = await _getWithHeaders(
      gatewayIp,
      path,
      {'Authorization': 'Basic $auth'},
    );
    if (basic != null) return basic;
    final cookie = await _formLogin(gatewayIp, creds);
    if (cookie == null) return null;
    return _getWithHeaders(gatewayIp, path, {'Cookie': cookie});
  }

  /// Extract IP/MAC pairs from a DHCP page.
  ///
  /// Tolerant by design: it finds all IPv4 addresses and all MAC addresses
  /// in the page independently and pairs them in document order (DHCP
  /// tables list one IP and one MAC per row). A single regex spanning the
  /// gap between them is fragile because HTML tags contain hex letters.
  static List<ConnectedDevice> parseDhcpPage(String html) {
    final ips = RegExp(r'\b\d+\.\d+\.\d+\.\d+\b')
        .allMatches(html)
        .map((m) => m.group(0)!)
        .toList();
    final macs = RegExp(r'([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}')
        .allMatches(html)
        .map((m) => m.group(0)!.replaceAll('-', ':'))
        .toList();
    final devices = <ConnectedDevice>[];
    final count = ips.length < macs.length ? ips.length : macs.length;
    for (var i = 0; i < count; i++) {
      devices.add(ConnectedDevice(ip: ips[i], mac: macs[i]).withVendor());
    }
    return dedupeByMac(devices);
  }

  @override
  Future<List<ConnectedDevice>> listDevices({
    required String gatewayIp,
    required RouterCredentials credentials,
  }) async {
    for (final path in dhcpPagePaths) {
      final body = await _fetchPage(gatewayIp, path, credentials);
      if (body != null) {
        final devices = parseDhcpPage(body);
        if (devices.isNotEmpty) return devices;
      }
    }
    // Fallback: the local subnet ARP table (devices the phone/PC can see).
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
    return LimitResult.unsupported(
      'V-SOL routers do not expose per-device bandwidth limiting in their '
      'web UI, so WiHisar cannot enforce a $downMbps Mbps limit for '
      '$deviceMac on this router. Exact fallback: put the V-SOL in bridge '
      'mode behind an OpenWrt router and limit the device there (OpenWrt '
      'SSH in the Limits tab), or block the device outright on the V-SOL '
      'MAC-filter page if your firmware has one.',
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
    return LimitResult.unsupported(
      'V-SOL routers have no limiter API to ask, so WiHisar cannot verify whether a limit is in force.',
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
    return LimitResult.unsupported(
      'No limit was ever applied by WiHisar on this V-SOL router, so there is nothing to clear.',
    );
  }
}
