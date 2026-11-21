import 'package:flutter_test/flutter_test.dart';
import 'package:wihisar/scan/host.dart';
import 'package:wihisar/scan/subnet.dart';
import 'package:wihisar/tools/linux_tools.dart';

void main() {
  group('subnet math', () {
    test('network / broadcast / host count for a /24', () {
      expect(networkAddressOf('192.168.1.5', 24), '192.168.1.0');
      expect(broadcastAddressOf('192.168.1.5', 24), '192.168.1.255');
      expect(hostCountOf(24), 254);
      expect(gatewayGuessOf('192.168.1.5', 24), '192.168.1.1');
    });

    test('host list starts at .1 and ends at .254', () {
      final hosts = hostAddressesOf('192.168.1.5', 24);
      expect(hosts.length, 254);
      expect(hosts.first, '192.168.1.1');
      expect(hosts.last, '192.168.1.254');
    });

    test('rejects bad input', () {
      expect(networkAddressOf('not-an-ip', 24), '');
      expect(networkAddressOf('192.168.1.5', 33), '');
      expect(hostAddressesOf('192.168.1.5', 24), isNotEmpty);
    });
  });

  group('gateway route parsers', () {
    test('linux ip route', () {
      expect(
        parseLinuxDefaultRoute(
          'default via 192.168.1.1 dev wlan0 proto dhcp metric 600\n'
          '192.168.1.0/24 dev wlan0 proto kernel scope link src 192.168.1.5',
        ),
        '192.168.1.1',
      );
      expect(parseLinuxDefaultRoute('192.168.1.0/24 dev wlan0'), isNull);
    });

    test('windows route print', () {
      expect(
        parseWindowsDefaultRoute(
          '  0.0.0.0          0.0.0.0      192.168.1.1     192.168.1.5     25\n'
          '  192.168.1.0    255.255.255.0         On-link      192.168.1.5    281',
        ),
        '192.168.1.1',
      );
    });

    test('bsd netstat', () {
      expect(
        parseBsdDefaultRoute(
          'default  192.168.1.1  UGSc  en0\n'
          '192.168.1  link#4  UCS  en0',
        ),
        '192.168.1.1',
      );
    });
  });

  group('ScannedHost', () {
    test('risky when Telnet or FTP is open', () {
      const risky = ScannedHost(
        ip: '192.168.1.9',
        openPorts: [OpenPort(port: 23, service: 'Telnet')],
      );
      const safe = ScannedHost(
        ip: '192.168.1.10',
        openPorts: [OpenPort(port: 443, service: 'HTTPS')],
      );
      expect(risky.looksRisky, isTrue);
      expect(safe.looksRisky, isFalse);
      expect(safe.displayName, '192.168.1.10');
    });

    test('common ports list covers the usual home services', () {
      expect(kCommonPorts[22], 'SSH');
      expect(kCommonPorts[80], 'HTTP');
      expect(kCommonPorts[445], 'SMB');
      expect(kCommonPorts.length, greaterThanOrEqualTo(10));
    });
  });

  group('linux tool parsers', () {
    test('nmap grepable hosts', () {
      const out = '''
# Nmap 7.94 scan initiated
Host: 192.168.1.1 ()  Status: Up
Host: 192.168.1.5 ()  Status: Up
Host: 192.168.1.99 ()  Status: Down
''';
      expect(
        parseNmapGreppableHosts(out),
        ['192.168.1.1', '192.168.1.5'],
      );
    });

    test('nmap service ports', () {
      const out = '''
PORT    STATE SERVICE VERSION
22/tcp  open  ssh     OpenSSH 8.9p1
80/tcp  open  http    nginx
443/tcp closed https
''';
      expect(
        parseNmapServicePorts(out),
        [
          (port: 22, service: 'ssh', version: 'OpenSSH 8.9p1'),
          (port: 80, service: 'http', version: 'nginx'),
        ],
      );
    });

    test('arp-scan rows', () {
      const out = '''
192.168.1.1  aa:bb:cc:dd:ee:ff  TP-LINK Technologies Co.,Ltd.
192.168.1.5  11:22:33:44:55:66  Samsung Electronics
''';
      final rows = parseArpScan(out);
      expect(rows.length, 2);
      expect(rows.first.$1, '192.168.1.1');
      expect(rows.first.$3, contains('TP-LINK'));
    });

    test('tool commands target the given subnet only', () {
      expect(
        nmapPingScanCommand('192.168.1.0/24'),
        'nmap -sn 192.168.1.0/24',
      );
      expect(arpScanCommand(), 'arp-scan --localnet');
    });

    test('aircrack-ng is detected-only with a cracking boundary', () {
      final tool = kKnownTools.firstWhere(
        (t) => t.command == 'aircrack-ng',
      );
      expect(tool.crackingNote, isNotNull);
      expect(tool.crackingNote, contains('not part of this app'));
    });
  });
}
