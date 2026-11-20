import 'package:flutter_test/flutter_test.dart';
import 'package:wihisar/router/oui.dart';
import 'package:wihisar/router/router_detect.dart';
import 'package:wihisar/router/router_profile.dart';

void main() {
  group('OUI lookup', () {
    test('TP-Link OUI resolves', () {
      expect(vendorForMac('50:C7:BF:AA:BB:CC'), 'TP-Link');
      expect(vendorForMac('50-c7-bf-aa-bb-cc'), 'TP-Link');
    });

    test('unknown OUI is honest', () {
      expect(vendorForMac('AA:BB:CC:11:22:33'), 'Unknown vendor');
    });

    test('normaliseMac handles dashes and lower case', () {
      expect(normaliseMac('50-c7-bf-aa-bb-cc'), '50:C7:BF:AA:BB:CC');
    });
  });

  group('scoreProfile', () {
    test('V-SOL title scores V-SOL highest', () {
      const fp = Fingerprint(
        pageTitle: 'V-SOL GPON ONU Web Management',
        gatewayIp: '192.168.1.1',
      );
      final vsol = scoreProfile(profileById('vsol'), fp);
      final tplink = scoreProfile(profileById('tplink'), fp);
      expect(vsol, greaterThan(tplink));
      expect(vsol, greaterThanOrEqualTo(35));
    });

    test('TP-Link title scores TP-Link highest', () {
      const fp = Fingerprint(
        pageTitle: 'TP-LINK Archer C6',
        gatewayIp: '192.168.0.1',
      );
      expect(scoreProfile(profileById('tplink'), fp),
          greaterThan(scoreProfile(profileById('vsol'), fp)));
    });

    test('Huawei SNMP sysDescr scores Huawei', () {
      const fp = Fingerprint(snmpSysDescr: 'Huawei OptiXstar HG8245H');
      expect(scoreProfile(profileById('huawei'), fp),
          greaterThan(scoreProfile(profileById('zte'), fp)));
    });

    test('empty fingerprint scores zero for every profile', () {
      const fp = Fingerprint();
      for (final p in routerProfiles) {
        expect(scoreProfile(p, fp), 0);
      }
    });

    test('gateway IP alone is only a weak hint', () {
      const fp = Fingerprint(gatewayIp: '192.168.1.1');
      expect(scoreProfile(profileById('vsol'), fp), 10);
    });

    test('OUI vendor match adds 30', () {
      const fp = Fingerprint(ouiVendor: 'TP-Link');
      expect(scoreProfile(profileById('tplink'), fp), greaterThanOrEqualTo(30));
    });
  });

  group('detectFromFingerprint', () {
    test('V-SOL fingerprint detects V-SOL', () {
      final d = detectFromFingerprint(
        gatewayIp: '192.168.131.1',
        fingerprint: const Fingerprint(
          pageTitle: 'V-SOL GPON ONU',
          gatewayIp: '192.168.131.1',
        ),
      );
      expect(d.profile.id, 'vsol');
      expect(d.confidence, greaterThanOrEqualTo(40));
      expect(d.evidence, isNotEmpty);
    });

    test('newer V-SOL gateway 192.168.131.1 is in the profile', () {
      expect(profileById('vsol').commonGatewayIps, contains('192.168.131.1'));
      expect(profileById('vsol').defaultPassword, 'stdONU101');
    });

    test('no evidence gives generic with low confidence', () {
      final d = detectFromFingerprint(
        gatewayIp: '192.168.1.1',
        fingerprint: const Fingerprint(gatewayIp: '192.168.1.1'),
      );
      expect(d.profile.id, 'generic');
      expect(d.confidence, lessThan(40));
      expect(d.confidenceLabel, 'Weak guess');
    });

    test('likelyGatewayFor uses the .1 of the subnet', () {
      expect(likelyGatewayFor('192.168.5.42'), '192.168.5.1');
      expect(likelyGatewayFor('10.0.0.7'), '10.0.0.1');
    });
  });
}
