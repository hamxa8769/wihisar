/// Limiter service: holds the user's rules and applies them through the
/// router adapter that matches the detected router.
///
/// Honesty rule: [applyRule] returns exactly what the adapter reported.
/// A limit is only recorded as "applied" when the adapter confirms success.
/// If the adapter cannot enforce it, the rule stays as "wanted, not applied"
/// and the UI shows why.
library;

import '../router/router_adapter.dart';
import 'limit_rule.dart';

class LimiterService {
  LimiterService(this.adapter);

  final RouterAdapter adapter;

  final Map<String, LimitRule> _rules = {};
  final Map<String, bool> _applied = {};

  List<LimitRule> get rules => _rules.values.toList();

  bool isApplied(String mac) => _applied[mac.toUpperCase()] ?? false;

  /// Apply [rule] through the adapter. Returns the adapter's own result.
  Future<LimitResult> applyRule({
    required LimitRule rule,
    required String gatewayIp,
    required RouterCredentials credentials,
  }) async {
    final downError = LimitRule.validateMbps(rule.downMbps);
    final upError = LimitRule.validateMbps(rule.upMbps);
    if (downError != null) {
      return LimitResult(success: false, message: 'Download: $downError');
    }
    if (upError != null) {
      return LimitResult(success: false, message: 'Upload: $upError');
    }
    final result = await adapter.setLimit(
      gatewayIp: gatewayIp,
      credentials: credentials,
      deviceMac: rule.deviceMac,
      downMbps: rule.downMbps,
      upMbps: rule.upMbps,
    );
    _rules[rule.deviceMac.toUpperCase()] = rule;
    _applied[rule.deviceMac.toUpperCase()] = result.success;
    return result;
  }

  Future<LimitResult> removeRule({
    required String deviceMac,
    required String gatewayIp,
    required RouterCredentials credentials,
  }) async {
    final result = await adapter.clearLimit(
      gatewayIp: gatewayIp,
      credentials: credentials,
      deviceMac: deviceMac,
    );
    _rules.remove(deviceMac.toUpperCase());
    _applied.remove(deviceMac.toUpperCase());
    return result;
  }
}
