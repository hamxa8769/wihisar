import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wihisar/scan/host.dart';
import 'package:wihisar/scan/scan_history.dart';

ScannedHost host(String ip, String mac) =>
    ScannedHost(ip: ip, mac: mac, vendor: 'Test');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ScanHistory', () {
    test('empty history: every MAC is new', () async {
      SharedPreferences.setMockInitialValues({});
      final history = ScanHistory();
      await history.load();
      final fresh = history.newMacs([
        host('192.168.1.5', 'AA:BB:CC:DD:EE:01'),
        host('192.168.1.6', 'AA:BB:CC:DD:EE:02'),
      ]);
      expect(fresh, {
        'AA:BB:CC:DD:EE:01',
        'AA:BB:CC:DD:EE:02',
      });
    });

    test('recordScan makes the MAC known next time', () async {
      SharedPreferences.setMockInitialValues({});
      final history = ScanHistory();
      await history.load();
      await history.recordScan([host('192.168.1.5', 'AA:BB:CC:DD:EE:01')]);
      expect(
        history.newMacs([host('192.168.1.5', 'AA:BB:CC:DD:EE:01')]),
        isEmpty,
      );
      expect(
        history.newMacs([host('192.168.1.7', 'AA:BB:CC:DD:EE:03')]),
        {'AA:BB:CC:DD:EE:03'},
      );
    });

    test('history survives a reload (persistence)', () async {
      SharedPreferences.setMockInitialValues({});
      final first = ScanHistory();
      await first.load();
      await first.recordScan([host('192.168.1.5', 'AA:BB:CC:DD:EE:01')]);
      final second = ScanHistory();
      await second.load();
      expect(second.knownMacs, {'AA:BB:CC:DD:EE:01'});
    });

    test('hosts without a MAC are never flagged new', () async {
      SharedPreferences.setMockInitialValues({});
      final history = ScanHistory();
      await history.load();
      expect(history.newMacs([const ScannedHost(ip: '192.168.1.5')]), isEmpty);
    });

    test('corrupt stored history loads as empty, never throws', () async {
      SharedPreferences.setMockInitialValues({
        ScanHistory.historyKey: 'this is not json{{{',
      });
      final history = ScanHistory();
      await history.load();
      expect(history.knownMacs, isEmpty);
      expect(
        history.newMacs([host('192.168.1.5', 'AA:BB:CC:DD:EE:01')]),
        {'AA:BB:CC:DD:EE:01'},
      );
    });

    test('MAC matching is case-insensitive', () async {
      SharedPreferences.setMockInitialValues({});
      final history = ScanHistory();
      await history.load();
      await history.recordScan([host('192.168.1.5', 'aa:bb:cc:dd:ee:01')]);
      expect(
        history.newMacs([host('192.168.1.5', 'AA:BB:CC:DD:EE:01')]),
        isEmpty,
      );
    });
  });
}
