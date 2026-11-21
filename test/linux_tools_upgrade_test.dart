import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wihisar/tools/linux_tools.dart';

void main() {
  group('lookupCommandName', () {
    test('uses which on Linux/macOS and where on Windows', () {
      // This test runs on Linux in CI; the branch is platform-dependent.
      if (Platform.isWindows) {
        expect(lookupCommandName(), 'where');
      } else {
        expect(lookupCommandName(), 'which');
      }
    });
  });

  group('installCommandFor', () {
    test('covers every known tool', () {
      for (final tool in kKnownTools) {
        final cmd = installCommandFor(tool.command);
        expect(cmd, isNotNull, reason: tool.command);
        expect(cmd, isNotEmpty);
      }
      expect(installCommandFor('nmap'), contains('apt install nmap'));
      expect(installCommandFor('tshark'), contains('tshark'));
      expect(installCommandFor('aircrack-ng'), contains('aircrack-ng'));
      expect(installCommandFor('iw'), contains('apt install iw'));
      expect(installCommandFor('nmcli'), contains('network-manager'));
    });

    test('unknown tool returns null', () {
      expect(installCommandFor('not-a-tool'), isNull);
    });
  });

  group('describeToolFailure', () {
    test('missing binary names the install', () {
      final msg = describeToolFailure(
        'nmap',
        const ProcessException('nmap', ['--version'], 'No such file or directory', 2),
      );
      expect(msg, contains('nmap is not installed'));
      expect(msg, contains('apt install nmap'));
    });

    test('permission denied names the fix', () {
      final msg = describeToolFailure(
        'arp-scan',
        StateError('exit 1'),
        stderr: 'ERROR: Permission denied',
      );
      expect(msg, contains('needs permission'));
    });

    test('timeout is named', () {
      final msg = describeToolFailure('nmap', TimeoutException('timed out'));
      expect(msg, contains('timed out'));
    });
  });

  group('parseNmapServicePorts with versions', () {
    test('captures the version string', () {
      const out = '''
PORT    STATE SERVICE VERSION
22/tcp  open  ssh     OpenSSH 8.9p1
80/tcp  open  http    nginx 1.18.0
443/tcp closed https
53/udp  open  domain
''';
      final ports = parseNmapServicePorts(out);
      expect(ports.length, 2);
      expect(ports[0].port, 22);
      expect(ports[0].service, 'ssh');
      expect(ports[0].version, 'OpenSSH 8.9p1');
      expect(ports[1].version, 'nginx 1.18.0');
    });

    test('no version is an empty string, not a crash', () {
      const out = '8080/tcp open http-alt\n';
      final ports = parseNmapServicePorts(out);
      expect(ports.single.version, '');
    });
  });

  group('parseIperf3', () {
    test('reads sender and receiver speeds', () {
      const out = '''
[  5]   0.00-5.00   sec  5.50 MBytes  9.22 Mbits/sec                  sender
[  5]   0.00-5.00   sec  5.48 MBytes  9.19 Mbits/sec                  receiver
''';
      final parsed = parseIperf3(out);
      expect(parsed.sentMbps, 9.22);
      expect(parsed.receivedMbps, 9.19);
    });

    test('missing direction is null', () {
      const out = '[  5]   0.00-1.00   sec  1.10 MBytes  9.22 Mbits/sec                  sender\n';
      final parsed = parseIperf3(out);
      expect(parsed.sentMbps, 9.22);
      expect(parsed.receivedMbps, isNull);
    });

    test('empty output is nulls', () {
      final parsed = parseIperf3('');
      expect(parsed.sentMbps, isNull);
      expect(parsed.receivedMbps, isNull);
    });

    test('iperf3Command builds the command', () {
      expect(iperf3Command('192.168.1.10'), 'iperf3 -c 192.168.1.10 -t 5');
      expect(
        iperf3Command('192.168.1.10', seconds: 10),
        'iperf3 -c 192.168.1.10 -t 10',
      );
    });
  });

  group('parseNmcliWifiList', () {
    test('parses terse nmcli rows', () {
      const out = '''
MyWiFi:85:WPA2
NeighbourNet:42:WPA1 WPA2
OpenNet:70:--
''';
      final rows = parseNmcliWifiList(out);
      expect(rows.length, 3);
      expect(rows[0].ssid, 'MyWiFi');
      expect(rows[0].signal, 85);
      expect(rows[0].security, 'WPA2');
      expect(rows[2].security, '--');
    });

    test('skips hidden networks and blank lines', () {
      const out = ':60:WPA2\nVisible:50:WPA2\n\n';
      final rows = parseNmcliWifiList(out);
      expect(rows.length, 1);
      expect(rows.single.ssid, 'Visible');
    });
  });

  group('parseIwDev', () {
    test('reads interface, ssid, channel and txpower', () {
      const out = '''
phy#0
\tInterface wlan0
\t\tifindex 3
\t\twdev 0x1
\t\taddr 12:34:56:78:9a:bc
\t\tssid MyWiFi
\t\ttype managed
\t\tchannel 6 (2437 MHz), width: 20 MHz, center1: 2437 MHz
\t\ttxpower 20.00 dBm
''';
      final info = parseIwDev(out);
      expect(info.interface, 'wlan0');
      expect(info.ssid, 'MyWiFi');
      expect(info.channel, '6');
      expect(info.txPower, '20.00 dBm');
    });

    test('empty output is an empty record', () {
      final info = parseIwDev('');
      expect(info.interface, '');
      expect(info.ssid, isNull);
      expect(info.channel, isNull);
      expect(info.txPower, isNull);
    });
  });

  group('parseTsharkProtocolHierarchy', () {
    test('reads protocol rows at every depth', () {
      const out = '''
===================================================================
Protocol Hierarchy Statistics
Filter:
eth                                              frames:10 bytes:1234
  ip                                             frames:10 bytes:1234
    tcp                                          frames:8 bytes:1000
    udp                                          frames:2 bytes:234
===================================================================
''';
      final rows = parseTsharkProtocolHierarchy(out);
      expect(rows.length, 4);
      expect(rows[0].protocol, 'eth');
      expect(rows[0].frames, 10);
      expect(rows[0].bytes, 1234);
      expect(rows[2].protocol, 'tcp');
      expect(rows[2].frames, 8);
    });

    test('empty output is empty', () {
      expect(parseTsharkProtocolHierarchy(''), isEmpty);
    });

    test('tsharkSummaryCommand caps the duration at 30s', () {
      expect(
        tsharkSummaryCommand('wlan0', seconds: 99),
        contains('duration:30'),
      );
      expect(
        tsharkSummaryCommand('wlan0'),
        contains('duration:10'),
      );
    });
  });

  group('detailed runners', () {
    test('nmap ping scan detailed never throws and names failures', () async {
      // 203.0.113.0/30 is TEST-NET-3: no hosts, fast either way.
      final result = await runNmapPingScanDetailed('203.0.113.0/30');
      if (result.ok) {
        expect(result.data, isNotNull);
      } else {
        expect(result.error, isNotEmpty);
      }
    });

    test('arp-scan detailed returns a ToolResult', () async {
      final result = await runArpScanDetailed();
      expect(result, isA<ToolResult>());
      if (!result.ok) expect(result.error, isNotEmpty);
    });

    test('runIperf3 with no server is a plain error', () async {
      final result = await runIperf3('');
      expect(result.ok, isFalse);
      expect(result.error, contains('server address'));
    });

    test('runTsharkProtocolSummary with no interface is a plain error',
        () async {
      final result = await runTsharkProtocolSummary(interfaceName: '');
      expect(result.ok, isFalse);
      expect(result.error, contains('interface'));
    });
  });
}
