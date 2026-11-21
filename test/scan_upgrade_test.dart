import 'package:flutter_test/flutter_test.dart';
import 'package:wihisar/devices/device_scan.dart';
import 'package:wihisar/scan/auto_scan.dart';
import 'package:wihisar/scan/host.dart';
import 'package:wihisar/scan/subnet.dart';

void main() {
  group('netmask to prefix', () {
    test('dotted masks', () {
      expect(netmaskToPrefix('255.255.255.0'), 24);
      expect(netmaskToPrefix('255.255.0.0'), 16);
      expect(netmaskToPrefix('255.255.255.128'), 25);
      expect(netmaskToPrefix('255.255.255.255'), 32);
      expect(netmaskToPrefix('0.0.0.0'), 0);
    });

    test('rejects bad masks', () {
      expect(netmaskToPrefix('255.0.255.0'), -1);
      expect(netmaskToPrefix('not-a-mask'), -1);
      expect(netmaskToPrefix('255.255.255'), -1);
    });

    test('hex masks', () {
      expect(hexNetmaskToPrefix('0xffffff00'), 24);
      expect(hexNetmaskToPrefix('0xffff0000'), 16);
      expect(hexNetmaskToPrefix('0xff000000'), 8);
      expect(hexNetmaskToPrefix('0xffffffff'), 32);
      expect(hexNetmaskToPrefix('0xff00ff00'), -1);
    });
  });

  group('prefix parsers', () {
    test('linux ip addr show', () {
      const out = '''
2: wlan0: <BROADCAST,MULTICAST,UP> mtu 1500
    inet 192.168.1.5/24 brd 192.168.1.255 scope global dynamic wlan0
    inet6 fe80::1/64 scope link
3: eth0: <BROADCAST,MULTICAST,UP> mtu 1500
    inet 10.0.0.7/16 brd 10.0.255.255 scope global eth0
''';
      final map = parseLinuxIpAddr(out);
      expect(map['192.168.1.5'], 24);
      expect(map['10.0.0.7'], 16);
      expect(map.containsKey('fe80::1'), isFalse);
    });

    test('windows ipconfig', () {
      const out = '''
Wireless LAN adapter Wi-Fi:

   IPv4 Address. . . . . . . . . . . : 192.168.1.5
   Subnet Mask . . . . . . . . . . . : 255.255.255.0
   Default Gateway . . . . . . . . . : 192.168.1.1

Ethernet adapter Ethernet:

   IPv4 Address. . . . . . . . . . . : 10.0.0.7
   Subnet Mask . . . . . . . . . . . : 255.255.0.0
''';
      final map = parseWindowsIpconfig(out);
      expect(map['192.168.1.5'], 24);
      expect(map['10.0.0.7'], 16);
    });

    test('macOS ifconfig', () {
      const out = '''
en0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
\tinet 192.168.1.5 netmask 0xffffff00 broadcast 192.168.1.255
\tinet6 fe80::1%en0 prefixlen 64 secured scopeid 0x6
lo0: flags=8049<UP,LOOPBACK,RUNNING,MULTICAST> mtu 16384
\tinet 127.0.0.1 netmask 0xff000000
''';
      final map = parseBsdIfconfig(out);
      expect(map['192.168.1.5'], 24);
      expect(map['127.0.0.1'], 8);
    });
  });

  group('detectNetworkPrefix', () {
    test('falls back to /24 for an address on no interface', () async {
      // 203.0.113.x is TEST-NET-3: never assigned to a real interface.
      expect(await AutoScanner().detectNetworkPrefix('203.0.113.5'), 24);
    });
  });

  group('compareIps', () {
    test('numeric order, not lexical', () {
      expect(compareIps('192.168.1.9', '192.168.1.10'), lessThan(0));
      expect(compareIps('192.168.1.10', '192.168.1.9'), greaterThan(0));
      expect(compareIps('192.168.1.5', '192.168.1.5'), 0);
    });
  });

  group('mergeHosts', () {
    test('fills missing fields, keeps flags, sorts by IP', () {
      final base = [
        const ScannedHost(
          ip: '192.168.1.10',
          mac: '',
          vendor: 'TP-Link',
          pingMs: 3,
        ),
        const ScannedHost(ip: '192.168.1.5', mac: 'AA:BB:CC:11:22:33'),
      ];
      final extra = [
        const ScannedHost(
          ip: '192.168.1.10',
          mac: '50:C7:BF:AA:BB:CC',
          hostname: 'router',
          isGateway: true,
          openPorts: [OpenPort(port: 80, service: 'HTTP')],
        ),
        const ScannedHost(ip: '192.168.1.20', mac: '11:22:33:44:55:66'),
      ];
      final merged = mergeHosts(base, extra);
      expect(merged.map((h) => h.ip).toList(),
          ['192.168.1.5', '192.168.1.10', '192.168.1.20']);
      final router = merged[1];
      expect(router.mac, '50:C7:BF:AA:BB:CC');
      expect(router.hostname, 'router');
      expect(router.vendor, 'TP-Link');
      expect(router.isGateway, isTrue);
      expect(router.pingMs, 3);
      expect(router.openPorts.length, 1);
    });

    test('base wins when both have a value', () {
      final merged = mergeHosts(
        [const ScannedHost(ip: '192.168.1.5', hostname: 'mine')],
        [const ScannedHost(ip: '192.168.1.5', hostname: 'theirs')],
      );
      expect(merged.single.hostname, 'mine');
    });
  });

  group('guessDeviceKind', () {
    test('gateway is a router', () {
      expect(
        guessDeviceKind(const ScannedHost(ip: '192.168.1.1', isGateway: true)),
        'Router',
      );
    });

    test('camera by vendor and by RTSP port', () {
      expect(
        guessDeviceKind(
          const ScannedHost(ip: '192.168.1.9', vendor: 'Hikvision'),
        ),
        'Camera',
      );
      expect(
        guessDeviceKind(
          const ScannedHost(
            ip: '192.168.1.9',
            openPorts: [OpenPort(port: 554, service: 'RTSP camera')],
          ),
        ),
        'Camera',
      );
    });

    test('printer by vendor and by IPP port', () {
      expect(
        guessDeviceKind(
          const ScannedHost(ip: '192.168.1.9', vendor: 'HP'),
        ),
        'Printer',
      );
      expect(
        guessDeviceKind(
          const ScannedHost(
            ip: '192.168.1.9',
            openPorts: [OpenPort(port: 631, service: 'Printer')],
          ),
        ),
        'Printer',
      );
    });

    test('phone by vendor and by hostname', () {
      expect(
        guessDeviceKind(
          const ScannedHost(ip: '192.168.1.9', vendor: 'Samsung'),
        ),
        'Phone',
      );
      expect(
        guessDeviceKind(
          const ScannedHost(ip: '192.168.1.9', hostname: 'iPhone-von-Hamza'),
        ),
        'Phone',
      );
    });

    test('computer by vendor and by SSH/SMB port', () {
      expect(
        guessDeviceKind(
          const ScannedHost(ip: '192.168.1.9', vendor: 'Intel'),
        ),
        'Computer',
      );
      expect(
        guessDeviceKind(
          const ScannedHost(
            ip: '192.168.1.9',
            openPorts: [OpenPort(port: 22, service: 'SSH')],
          ),
        ),
        'Computer',
      );
    });

    test('smart TV by vendor and hostname', () {
      expect(
        guessDeviceKind(
          const ScannedHost(ip: '192.168.1.9', vendor: 'LG'),
        ),
        'Smart TV',
      );
      expect(
        guessDeviceKind(
          const ScannedHost(ip: '192.168.1.9', hostname: 'Living-Room-TV'),
        ),
        'Smart TV',
      );
    });

    test('IoT by Espressif vendor', () {
      expect(
        guessDeviceKind(
          const ScannedHost(ip: '192.168.1.9', vendor: 'Espressif'),
        ),
        'IoT',
      );
    });

    test('unknown when nothing matches', () {
      expect(
        guessDeviceKind(const ScannedHost(ip: '192.168.1.9')),
        'Unknown',
      );
    });
  });

  group('looksRisky', () {
    test('RDP and VNC count as risky', () {
      const rdp = ScannedHost(
        ip: '192.168.1.9',
        openPorts: [OpenPort(port: 3389, service: 'RDP')],
      );
      const vnc = ScannedHost(
        ip: '192.168.1.10',
        openPorts: [OpenPort(port: 5900, service: 'VNC')],
      );
      const safe = ScannedHost(
        ip: '192.168.1.11',
        openPorts: [OpenPort(port: 443, service: 'HTTPS')],
      );
      expect(rdp.looksRisky, isTrue);
      expect(vnc.looksRisky, isTrue);
      expect(safe.looksRisky, isFalse);
    });
  });

  group('primeNeighbourCache', () {
    test('completes without throwing, even for silent hosts', () async {
      // 127.0.0.1 answers on port 80 only if something listens; either
      // way the prime must not throw.
      await SubnetScanner().primeNeighbourCache(['127.0.0.1']);
      await SubnetScanner().primeNeighbourCache([]);
    });
  });

  group('scan cancellation', () {
    test('cancelled before the first phase returns empty', () async {
      const network = LocalNetwork(localIp: '192.168.1.5', prefix: 30);
      final result = await AutoScanner().scan(
        network,
        scanPorts: false,
        isCancelled: () => true,
      );
      expect(result, isEmpty);
    });
  });
}
