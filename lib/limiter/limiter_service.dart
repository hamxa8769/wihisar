/// Limiter service: holds the user's rules and applies them through the
/// router adapter that matches the detected router.
///
/// Honesty rule: [applyRule] returns exactly what the adapter reported.
/// A limit is only recorded as "applied" when the adapter confirms success.
/// If the adapter cannot enforce it, the rule stays as "wanted, not applied"
/// and the UI shows why.
///
/// Rules are persisted with shared_preferences (key `wihisar_limit_rules`)
/// as a JSON list of [LimitRule] objects plus an `applied` flag, so a
/// rule survives an app restart. Call [loadRules] once at startup; the
/// service saves after every change. Router passwords are never stored —
/// they arrive per call from the user.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../router/router_adapter.dart';
import 'limit_rule.dart';

class LimiterService {
  LimiterService(this.adapter);

  /// Mutable on purpose: the UI keeps one service (and its persisted
  /// rules) while the detected router — and therefore the adapter —
  /// changes underneath it.
  RouterAdapter adapter;

  /// SharedPreferences key for the persisted rule list.
  static const String rulesKey = 'wihisar_limit_rules';

  final Map<String, LimitRule> _rules = {};
  final Map<String, bool> _applied = {};

  /// Last message the adapter reported per device MAC (apply / verify /
  /// remove), so the UI can show why a rule is or is not in force.
  final Map<String, String> _messages = {};

  List<LimitRule> get rules => _rules.values.toList();

  bool isApplied(String mac) => _applied[mac.toUpperCase()] ?? false;

  /// Last adapter message for [mac], or null when nothing was attempted.
  String? messageFor(String mac) => _messages[mac.toUpperCase()];

  /// Load persisted rules (from [loadRules] / [saveRules]). Corrupt or
  /// missing data loads as no rules — never throws.
  Future<void> loadRules() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(rulesKey);
      if (raw == null || raw.isEmpty) return;
      final list = jsonDecode(raw) as List;
      _rules.clear();
      _applied.clear();
      for (final item in list) {
        if (item is! Map<String, dynamic>) continue;
        final rule = LimitRule.fromJson(item);
        if (rule.deviceMac.isEmpty) continue;
        final key = rule.deviceMac.toUpperCase();
        _rules[key] = rule;
        _applied[key] = item['applied'] as bool? ?? false;
      }
    } catch (_) {
      // Corrupt storage loads as no rules; the UI shows an empty list.
    }
  }

  /// Persist the current rules + applied flags.
  Future<void> saveRules() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _rules.values
        .map((r) => {
              ...r.toJson(),
              'applied': _applied[r.deviceMac.toUpperCase()] ?? false,
            })
        .toList();
    await prefs.setString(rulesKey, jsonEncode(list));
  }

  /// Apply [rule] through the adapter. Returns the adapter's own result.
  Future<LimitResult> applyRule({
    required LimitRule rule,
    required String gatewayIp,
    required RouterCredentials credentials,
    String? expectedFingerprint,
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
      deviceIp: rule.deviceIp,
      downMbps: rule.downMbps,
      upMbps: rule.upMbps,
      expectedFingerprint: expectedFingerprint,
    );
    final key = rule.deviceMac.toUpperCase();
    _rules[key] = rule;
    _applied[key] = result.success;
    _messages[key] = result.message;
    await saveRules();
    return result;
  }

  /// Re-check whether the limit for [deviceMac] is actually in force
  /// right now, by asking the router through the adapter. Returns the
  /// adapter's own answer (or an honest "cannot verify").
  Future<LimitResult> verifyRule({
    required String deviceMac,
    String? deviceIp,
    required String gatewayIp,
    required RouterCredentials credentials,
    String? expectedFingerprint,
  }) async {
    final result = await adapter.verifyLimit(
      gatewayIp: gatewayIp,
      credentials: credentials,
      deviceMac: deviceMac,
      deviceIp: deviceIp,
      expectedFingerprint: expectedFingerprint,
    );
    final key = deviceMac.toUpperCase();
    _messages[key] = result.message;
    if (_rules.containsKey(key)) {
      _applied[key] = result.success;
      await saveRules();
    }
    return result;
  }

  Future<LimitResult> removeRule({
    required String deviceMac,
    required String gatewayIp,
    required RouterCredentials credentials,
    String? expectedFingerprint,
  }) async {
    final rule = _rules[deviceMac.toUpperCase()];
    final result = await adapter.clearLimit(
      gatewayIp: gatewayIp,
      credentials: credentials,
      deviceMac: deviceMac,
      deviceIp: rule?.deviceIp,
      expectedFingerprint: expectedFingerprint,
    );
    final key = deviceMac.toUpperCase();
    _rules.remove(key);
    _applied.remove(key);
    _messages[key] = result.message;
    await saveRules();
    return result;
  }
}
