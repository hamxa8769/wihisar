import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wihisar/devices/device_scan.dart';
import 'package:wihisar/limiter/limit_rule.dart';
import 'package:wihisar/limiter/limiter_service.dart';
import 'package:wihisar/router/adapters/generic_adapter.dart';
import 'package:wihisar/router/adapters/vsol_adapter.dart';
import 'package:wihisar/router/router_adapter.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const rule = LimitRule(
    deviceMac: 'AA:BB:CC:11:22:33',
    deviceIp: '192.168.1.5',
    deviceLabel: 'phone',
    downMbps: 5,
    upMbps: 2,
  );
  const creds = RouterCredentials(username: 'admin', password: 'x');

  group('LimitRule.fromJson', () {
    test('round-trips through toJson', () {
      final restored = LimitRule.fromJson(rule.toJson());
      expect(restored.deviceMac, rule.deviceMac);
      expect(restored.deviceIp, rule.deviceIp);
      expect(restored.deviceLabel, rule.deviceLabel);
      expect(restored.downMbps, rule.downMbps);
      expect(restored.upMbps, rule.upMbps);
      expect(restored.enabled, rule.enabled);
    });

    test('tolerates missing fields', () {
      final restored = LimitRule.fromJson({'mac': 'AA:BB:CC:11:22:33'});
      expect(restored.deviceMac, 'AA:BB:CC:11:22:33');
      expect(restored.deviceIp, '');
      expect(restored.enabled, isTrue);
    });
  });

  group('LimiterService persistence', () {
    test('rules survive a new service instance', () async {
      final service = LimiterService(VsolAdapter());
      // V-SOL honestly refuses the limit, but the rule is still recorded.
      await service.applyRule(
        rule: rule,
        gatewayIp: '192.168.1.1',
        credentials: creds,
      );
      expect(service.rules.length, 1);
      expect(service.isApplied('AA:BB:CC:11:22:33'), isFalse);

      final reloaded = LimiterService(VsolAdapter());
      await reloaded.loadRules();
      expect(reloaded.rules.length, 1);
      expect(reloaded.rules.single.deviceLabel, 'phone');
      expect(reloaded.isApplied('AA:BB:CC:11:22:33'), isFalse);
    });

    test('applied flag persists for a successful rule', () async {
      final service = LimiterService(_AlwaysAppliedAdapter());
      final result = await service.applyRule(
        rule: rule,
        gatewayIp: '192.168.1.1',
        credentials: creds,
      );
      expect(result.success, isTrue);
      expect(service.isApplied('AA:BB:CC:11:22:33'), isTrue);

      final reloaded = LimiterService(VsolAdapter());
      await reloaded.loadRules();
      expect(reloaded.isApplied('AA:BB:CC:11:22:33'), isTrue);
    });

    test('removeRule deletes the persisted rule', () async {
      final service = LimiterService(VsolAdapter());
      await service.applyRule(
        rule: rule,
        gatewayIp: '192.168.1.1',
        credentials: creds,
      );
      await service.removeRule(
        deviceMac: 'AA:BB:CC:11:22:33',
        gatewayIp: '192.168.1.1',
        credentials: creds,
      );
      expect(service.rules, isEmpty);

      final reloaded = LimiterService(VsolAdapter());
      await reloaded.loadRules();
      expect(reloaded.rules, isEmpty);
    });

    test('loadRules tolerates corrupt storage', () async {
      SharedPreferences.setMockInitialValues({
        LimiterService.rulesKey: 'this is not json',
      });
      final service = LimiterService(VsolAdapter());
      await service.loadRules();
      expect(service.rules, isEmpty);
    });
  });

  group('verifyRule and messageFor', () {
    test('generic adapter honestly cannot verify', () async {
      final service = LimiterService(GenericAdapter());
      final result = await service.verifyRule(
        deviceMac: 'AA:BB:CC:11:22:33',
        deviceIp: '192.168.1.5',
        gatewayIp: '192.168.1.1',
        credentials: creds,
      );
      expect(result.success, isFalse);
      expect(result.message, contains('cannot verify'));
      expect(
        service.messageFor('AA:BB:CC:11:22:33'),
        contains('cannot verify'),
      );
    });

    test('messageFor returns the last apply message', () async {
      final service = LimiterService(VsolAdapter());
      await service.applyRule(
        rule: rule,
        gatewayIp: '192.168.1.1',
        credentials: creds,
      );
      expect(service.messageFor('AA:BB:CC:11:22:33'), contains('V-SOL'));
      expect(service.messageFor('00:00:00:00:00:00'), isNull);
    });

    test('applyRule passes the device IP to the adapter', () async {
      final adapter = _RecordingAdapter();
      final service = LimiterService(adapter);
      await service.applyRule(
        rule: rule,
        gatewayIp: '192.168.1.1',
        credentials: creds,
      );
      expect(adapter.lastDeviceIp, '192.168.1.5');
    });
  });
}

/// Test adapter that always reports success.
class _AlwaysAppliedAdapter implements RouterAdapter {
  @override
  String get profileId => 'test';

  @override
  String get vendor => 'Test';

  @override
  bool get supportsDeviceList => false;

  @override
  bool get supportsBandwidthLimit => true;

  @override
  String get limitMethodDescription => 'Test adapter.';

  @override
  List<String> get limitations => const [];

  @override
  Future<List<ConnectedDevice>> listDevices({
    required String gatewayIp,
    required RouterCredentials credentials,
  }) async =>
      const [];

  @override
  Future<LimitResult> setLimit({
    required String gatewayIp,
    required RouterCredentials credentials,
    required String deviceMac,
    String? deviceIp,
    required double downMbps,
    required double upMbps,
    String? expectedFingerprint,
  }) async =>
      LimitResult.applied(downMbps, upMbps, 'test');

  @override
  Future<LimitResult> verifyLimit({
    required String gatewayIp,
    required RouterCredentials credentials,
    required String deviceMac,
    String? deviceIp,
    String? expectedFingerprint,
  }) async =>
      const LimitResult(success: true, message: 'verified');

  @override
  Future<LimitResult> clearLimit({
    required String gatewayIp,
    required RouterCredentials credentials,
    required String deviceMac,
    String? deviceIp,
    String? expectedFingerprint,
  }) async =>
      const LimitResult(success: true, message: 'cleared');
}

/// Test adapter that records what it was asked to limit.
class _RecordingAdapter extends _AlwaysAppliedAdapter {
  String? lastDeviceIp;

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
    lastDeviceIp = deviceIp;
    return LimitResult.applied(downMbps, upMbps, 'test');
  }
}
