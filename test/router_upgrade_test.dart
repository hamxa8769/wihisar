import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wihisar/router/adapters/openwrt_adapter.dart';
import 'package:wihisar/router/adapters/tplink_adapter.dart';
import 'package:wihisar/router/adapters/vsol_adapter.dart';
import 'package:wihisar/router/oui.dart';
import 'package:wihisar/router/router_adapter.dart';
import 'package:wihisar/router/router_detect.dart';

void main() {
  group('OUI table', () {
    test('has at least 100 entries', () {
      expect(ouiVendors.length, greaterThanOrEqualTo(100));
    });

    test('spot checks for the vendors the app profiles', () {
      expect(vendorForMac('50:C7:BF:AA:BB:CC'), 'TP-Link');
      expect(vendorForMac('30:B5:C2:11:22:33'), 'TP-Link');
      expect(vendorForMac('00:03:93:11:22:33'), 'Apple');
      expect(vendorForMac('00:12:FB:11:22:33'), 'Samsung');
      expect(vendorForMac('00:02:B3:11:22:33'), 'Intel');
      expect(vendorForMac('24:0A:C4:11:22:33'), 'Espressif');
      expect(vendorForMac('00:BC:99:11:22:33'), 'Hikvision');
      expect(vendorForMac('4C:11:BF:11:22:33'), 'Dahua');
      expect(vendorForMac('B8:27:EB:11:22:33'), 'Raspberry Pi');
      expect(vendorForMac('00:0D:4B:11:22:33'), 'Roku');
      expect(vendorForMac('00:1B:78:11:22:33'), 'HP');
      expect(vendorForMac('00:00:85:11:22:33'), 'Canon');
    });
  });

  group('parseHtmlTitle', () {
    test('extracts and trims the title', () {
      expect(
        parseHtmlTitle('<html><head><title>  V-SOL GPON ONU  </title></head>'),
        'V-SOL GPON ONU',
      );
      expect(
        parseHtmlTitle('<TITLE>TP-LINK Archer C6</TITLE>'),
        'TP-LINK Archer C6',
      );
      expect(
        parseHtmlTitle('<title>\n  My Router\n  Admin\n</title>'),
        'My Router Admin',
      );
    });

    test('returns null without a title', () {
      expect(parseHtmlTitle('<html><body>no title</body></html>'), isNull);
      expect(parseHtmlTitle('<title>   </title>'), isNull);
      expect(parseHtmlTitle(''), isNull);
    });
  });

  group('detectRouterAutomatically', () {
    test('never throws and returns generic for a dead gateway', () async {
      // Localhost port 80 refuses fast in the test sandbox.
      final d = await detectRouterAutomatically(gatewayIp: '127.0.0.1');
      expect(d.profile.id, 'generic');
      expect(d.confidence, lessThan(40));
    });

    test('uses the gateway MAC vendor when given', () async {
      final d = await detectRouterAutomatically(
        gatewayIp: '127.0.0.1',
        gatewayMac: '50:C7:BF:AA:BB:CC',
      );
      expect(d.gatewayVendor, 'TP-Link');
    });
  });

  group('TP-Link md5Hex', () {
    test('known vector md5(admin)', () {
      expect(
        TpLinkAdapter.md5Hex('admin'),
        '21232f297a57a5a743894a0e4a801fc3',
      );
    });

    test('empty and case', () {
      expect(
        TpLinkAdapter.md5Hex(''),
        'd41d8cd98f00b204e9800998ecf8427e',
      );
      expect(TpLinkAdapter.md5Hex('Admin'), isNot('21232f297a57a5a743894a0e4a801fc3'));
    });
  });

  group('TP-Link QoS body', () {
    test('buildQosSetBody uses kbps and upper-case colon MAC', () {
      final body = TpLinkAdapter.buildQosSetBody('aa-bb-cc-11-22-33', 5, 2);
      expect(body['method'], 'set');
      final qos = body['qos'] as Map<String, dynamic>;
      expect(qos['enable'], 1);
      expect(qos['qos_type'], 'device');
      final device = (qos['device_list'] as List).single as Map;
      expect(device['mac'], 'AA:BB:CC:11:22:33');
      expect(device['down_limit'], 5000);
      expect(device['up_limit'], 2000);
    });

    test('buildQosSetBodyList keeps the remaining devices', () {
      final body = TpLinkAdapter.buildQosSetBodyList([
        {'mac': 'aa:bb:cc:11:22:33', 'up_limit': 1000, 'down_limit': 2000},
      ]);
      final qos = body['qos'] as Map<String, dynamic>;
      final device = (qos['device_list'] as List).single as Map;
      expect(device['mac'], 'AA:BB:CC:11:22:33');
      expect(device['up_limit'], 1000);
    });
  });

  group('TP-Link QoS response parsing', () {
    test('error_code 0 is ok', () {
      final r = TpLinkAdapter.parseQosSetResponse('{"error_code":0}');
      expect(r.ok, isTrue);
      expect(r.errorCode, 0);
    });

    test('non-zero error_code carries the router message', () {
      final r = TpLinkAdapter.parseQosSetResponse(
        '{"error_code":-20506,"msg":"no permission"}',
      );
      expect(r.ok, isFalse);
      expect(r.errorCode, -20506);
      expect(r.message, 'no permission');
    });

    test('garbage body is a failure, not a throw', () {
      final r = TpLinkAdapter.parseQosSetResponse('not json at all');
      expect(r.ok, isFalse);
      expect(r.errorCode, -1);
    });
  });

  group('TP-Link QoS list checks', () {
    test('qosListContainsMac finds the MAC at any depth', () {
      const body = '''
{"error_code":0,"result":{"qos":{"enable":1,"device_list":[
  {"mac":"AA:BB:CC:11:22:33","up_limit":2000,"down_limit":5000},
  {"mac":"11:22:33:44:55:66","up_limit":1000,"down_limit":1000}
]}}}''';
      expect(TpLinkAdapter.qosListContainsMac(body, 'aa-bb-cc-11-22-33'), isTrue);
      expect(TpLinkAdapter.qosListContainsMac(body, 'AA:BB:CC:99:88:77'), isFalse);
    });

    test('parseQosDeviceList returns the devices', () {
      const body = '''
{"result":{"qos":{"device_list":[
  {"mac":"AA:BB:CC:11:22:33","up_limit":2000,"down_limit":5000}
]}}}''';
      final devices = TpLinkAdapter.parseQosDeviceList(body);
      expect(devices.length, 1);
      expect(devices.single['down_limit'], 5000);
    });

    test('empty or garbage list is empty, not a throw', () {
      expect(TpLinkAdapter.parseQosDeviceList('garbage'), isEmpty);
      expect(TpLinkAdapter.qosListContainsMac('garbage', 'AA:BB:CC:11:22:33'), isFalse);
    });
  });

  group('TP-Link testConnection', () {
    test('never throws on a dead gateway', () async {
      final probe = await TpLinkAdapter().testConnection(
        gatewayIp: '127.0.0.1',
        credentials: const RouterCredentials(username: 'admin', password: 'x'),
      );
      expect(probe.loginOk, isFalse);
      expect(probe.message, isNotEmpty);
    });
  });

  group('V-SOL form login helpers', () {
    test('buildLoginFormBody url-encodes', () {
      expect(
        VsolAdapter.buildLoginFormBody('admin', 'p@ss word&1'),
        'username=admin&password=p%40ss%20word%261',
      );
    });

    test('parseSessionCookie takes the first name=value pair', () {
      expect(
        VsolAdapter.parseSessionCookie(
          'session=abc123; Path=/; HttpOnly',
        ),
        'session=abc123',
      );
      expect(VsolAdapter.parseSessionCookie('session=abc123'), 'session=abc123');
      expect(VsolAdapter.parseSessionCookie(null), isNull);
      expect(VsolAdapter.parseSessionCookie(''), isNull);
      expect(VsolAdapter.parseSessionCookie('nonsense'), isNull);
    });

    test('DHCP page paths include the new ones', () {
      expect(VsolAdapter.dhcpPagePaths, contains('/cgi-bin/status_dhcp.cgi'));
      expect(VsolAdapter.dhcpPagePaths, contains('/lan_dhcp_clients.asp'));
      expect(VsolAdapter.dhcpPagePaths, contains('/status_lan.asp'));
      expect(VsolAdapter.dhcpPagePaths, contains('/dhcp_clients_list.asp'));
      expect(VsolAdapter.dhcpPagePaths, contains('/goform/dhcp_clients'));
      expect(VsolAdapter.dhcpPagePaths.length, greaterThanOrEqualTo(9));
    });
  });

  group('OpenWrt SSH helpers', () {
    test('sshFingerprint is OpenSSH format', () {
      // SHA-256 of the empty string, a well-known 32-byte digest.
      final digest =
          base64Decode('47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=');
      // A 32-byte digest renders as SHA256:<43 base64 chars, no padding>.
      final fp = OpenWrtAdapter.sshFingerprint(digest);
      expect(fp.startsWith('SHA256:'), isTrue);
      expect(fp.contains('='), isFalse);
      expect(fp.length, 'SHA256:'.length + 43);
    });

    test('htbApplyCommands returns only runnable lines', () {
      final cmds = OpenWrtAdapter.htbApplyCommands(
        deviceIp: '192.168.1.5',
        downMbps: 5,
        upMbps: 2,
      );
      expect(cmds.length, 3);
      expect(cmds.every((c) => !c.startsWith('#')), isTrue);
      final joined = cmds.join('\n');
      expect(joined, contains('192.168.1.5'));
      expect(joined, contains('5000kbit'));
      expect(joined, contains('tc qdisc add dev br-lan root handle 1: htb'));
      expect(joined, contains('tc class add dev br-lan'));
      expect(joined, contains('tc filter add dev br-lan'));
    });

    test('htbApplyCommands matches htbCommandsFor minus comments', () {
      final runnable = OpenWrtAdapter.htbApplyCommands(
        deviceIp: '192.168.1.5',
        downMbps: 5,
        upMbps: 2,
      );
      final all = OpenWrtAdapter.htbCommandsFor(
        deviceIp: '192.168.1.5',
        downMbps: 5,
        upMbps: 2,
      );
      expect(
        runnable,
        all.where((c) => !c.startsWith('#')).toList(),
      );
    });

    test('tcOutputHasIp matches whole addresses only', () {
      const out = '''
class htb 1:5 parent 1: root prio 0 rate 5000Kbit
filter parent 1: protocol ip pref 1 u32 fh 800::800 order 2048 key ht 800 bkt 0 flowid 1:5
  match 192.168.1.5/32 at 16
''';
      expect(OpenWrtAdapter.tcOutputHasIp(out, '192.168.1.5'), isTrue);
      expect(OpenWrtAdapter.tcOutputHasIp(out, '192.168.1.50'), isFalse);
      expect(OpenWrtAdapter.tcOutputHasIp(out, '192.168.1.6'), isFalse);
      expect(OpenWrtAdapter.tcOutputHasIp('', '192.168.1.5'), isFalse);
    });

    test('setLimit without a fingerprint refuses without connecting', () async {
      final result = await OpenWrtAdapter().setLimit(
        gatewayIp: '127.0.0.1',
        credentials: const RouterCredentials(username: 'admin', password: 'x'),
        deviceMac: 'AA:BB:CC:11:22:33',
        deviceIp: '192.168.1.5',
        downMbps: 5,
        upMbps: 2,
      );
      expect(result.success, isFalse);
      expect(result.message, contains('fingerprint'));
    });

    test('setLimit without a device IP refuses', () async {
      final result = await OpenWrtAdapter().setLimit(
        gatewayIp: '127.0.0.1',
        credentials: const RouterCredentials(username: 'admin', password: 'x'),
        deviceMac: 'AA:BB:CC:11:22:33',
        downMbps: 5,
        upMbps: 2,
        expectedFingerprint: 'SHA256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
      );
      expect(result.success, isFalse);
      expect(result.message, contains('device IP'));
    });

    test('probeSshFingerprint returns null for a dead host', () async {
      // 192.0.2.1 is TEST-NET-1 — reserved, never assigned to a real
      // host. (127.0.0.1 is NOT dead on CI runners: they run an SSH
      // server on port 22, which is how this test failed in CI.)
      final fp = await OpenWrtAdapter()
          .probeSshFingerprint(gatewayIp: '192.0.2.1');
      expect(fp, isNull);
    });

    test('decodeHostKeyFingerprint does not double-encode', () {
      // dartssh2 hands the callback bytes already encoded as UTF-8
      // 'SHA256:<base64>'. Decoding them is the whole job — encoding
      // again produced 'SHA256:U0hBMjU2...' in CI, which no router
      // fingerprint would ever match.
      const standard = 'SHA256:1s+RaBj8H8psWY9QU2XNy9Ficc/1VNHZedVp/2JWT3P2mNQWs';
      final callbackBytes =
          Uint8List.fromList(utf8.encode(standard));
      expect(
        OpenWrtAdapter.decodeHostKeyFingerprint(callbackBytes),
        standard,
      );
      expect(
        OpenWrtAdapter.decodeHostKeyFingerprint(callbackBytes),
        isNot(startsWith('SHA256:U0hB')),
      );
    });
  });
}
