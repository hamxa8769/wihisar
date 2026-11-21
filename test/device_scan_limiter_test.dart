import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wihisar/devices/device_scan.dart';
import 'package:wihisar/limiter/limit_rule.dart';
import 'package:wihisar/limiter/limiter_service.dart';
import 'package:wihisar/router/adapters/generic_adapter.dart';
import 'package:wihisar/router/adapters/openwrt_adapter.dart';
import 'package:wihisar/router/adapters/vsol_adapter.dart';
import 'package:wihisar/router/router_adapter.dart';

void main() {
  // LimiterService now persists rules with SharedPreferences.
  setUp(() => SharedPreferences.setMockInitialValues({}));
  group('ARP parsers', () {
    test('parses Linux ip neigh output', () {
      const out = '''
192.168.1.1 dev wlan0 lladdr 50:c7:bf:aa:bb:cc REACHABLE
192.168.1.5 dev wlan0 lladdr 34:4b:50:11:22:33 STALE
''';
      final devices = parseLinuxNeigh(out);
      expect(devices.length, 2);
      expect(devices[0].ip, '192.168.1.1');
      expect(devices[0].vendor, 'TP-Link');
      expect(devices[1].vendor, 'ZTE');
    });

    test('parses Windows arp -a output', () {
      const out = '''
  192.168.1.1           50-c7-bf-aa-bb-cc     dynamic
  192.168.1.5           34-4b-50-11-22-33     dynamic
''';
      final devices = parseWindowsArp(out);
      expect(devices.length, 2);
      expect(devices[0].mac, '50:c7:bf:aa:bb:cc');
    });

    test('parses BSD arp -an output', () {
      const out =
          '? (192.168.1.5) at 34:4b:50:11:22:33 on en0 ifscope [ethernet]';
      final devices = parseBsdArp(out);
      expect(devices.length, 1);
      expect(devices[0].ip, '192.168.1.5');
    });

    test('dedupeByMac keeps the first entry', () {
      final devices = dedupeByMac([
        const ConnectedDevice(ip: '192.168.1.5', mac: 'AA:BB:CC:11:22:33'),
        const ConnectedDevice(ip: '192.168.1.6', mac: 'aa:bb:cc:11:22:33'),
      ]);
      expect(devices.length, 1);
      expect(devices[0].ip, '192.168.1.5');
    });

    test('subnetPrefixOf', () {
      expect(subnetPrefixOf('192.168.5.42'), '192.168.5.');
      expect(subnetPrefixOf('not-an-ip'), '');
    });
  });

  group('V-SOL DHCP page parser', () {
    test('extracts IP/MAC pairs', () {
      const html =
          '<tr><td>192.168.1.5</td><td>AA:BB:CC:11:22:33</td></tr>';
      final devices = VsolAdapter.parseDhcpPage(html);
      expect(devices.length, 1);
      expect(devices[0].ip, '192.168.1.5');
    });
  });

  group('OpenWrt DHCP leases parser', () {
    test('parses /tmp/dhcp.leases', () {
      const leases = '1760000000 aa:bb:cc:11:22:33 192.168.1.5 phone *\n'
          '1760000001 50:c7:bf:aa:bb:cc 192.168.1.6 laptop *\n';
      final devices = OpenWrtAdapter.parseDhcpLeases(leases);
      expect(devices.length, 2);
      expect(devices[0].hostname, 'phone');
      expect(devices[1].vendor, 'TP-Link');
    });

    test('HTB commands cap the right IP at the right rate', () {
      final cmds = OpenWrtAdapter.htbCommandsFor(
        deviceIp: '192.168.1.5',
        downMbps: 5,
        upMbps: 2,
      );
      final joined = cmds.join('\n');
      expect(joined, contains('192.168.1.5'));
      expect(joined, contains('5000kbit'));
      expect(joined, contains('2000kbit'));
    });
  });

  group('LimitRule validation', () {
    test('rejects below minimum and above maximum', () {
      expect(LimitRule.validateMbps(0.1), isNotNull);
      expect(LimitRule.validateMbps(0.5), isNull);
      expect(LimitRule.validateMbps(1000), isNull);
      expect(LimitRule.validateMbps(1001), isNotNull);
    });
  });

  group('LimiterService honesty', () {
    test('V-SOL adapter never claims a limit was applied', () async {
      final service = LimiterService(VsolAdapter());
      final result = await service.applyRule(
        rule: const LimitRule(
          deviceMac: 'AA:BB:CC:11:22:33',
          deviceIp: '192.168.1.5',
          deviceLabel: 'phone',
          downMbps: 5,
          upMbps: 2,
        ),
        gatewayIp: '192.168.1.1',
        credentials: const RouterCredentials(username: 'admin', password: 'x'),
      );
      expect(result.success, isFalse);
      expect(service.isApplied('AA:BB:CC:11:22:33'), isFalse);
    });

    test('generic adapter never claims a limit was applied', () async {
      final service = LimiterService(GenericAdapter());
      final result = await service.applyRule(
        rule: const LimitRule(
          deviceMac: 'AA:BB:CC:11:22:33',
          deviceIp: '192.168.1.5',
          deviceLabel: 'phone',
          downMbps: 5,
          upMbps: 2,
        ),
        gatewayIp: '192.168.1.1',
        credentials: const RouterCredentials(username: 'admin', password: 'x'),
      );
      expect(result.success, isFalse);
    });

    test('invalid limit is rejected before touching the adapter', () async {
      final service = LimiterService(VsolAdapter());
      final result = await service.applyRule(
        rule: const LimitRule(
          deviceMac: 'AA:BB:CC:11:22:33',
          deviceIp: '192.168.1.5',
          deviceLabel: 'phone',
          downMbps: 0.1,
          upMbps: 2,
        ),
        gatewayIp: '192.168.1.1',
        credentials: const RouterCredentials(username: 'admin', password: 'x'),
      );
      expect(result.success, isFalse);
      expect(result.message, contains('Minimum'));
    });
  });
}
