/// Per-device bandwidth limit rule.
///
/// Rules live in memory only in v0.1 (no admin passwords, no rules are
/// written to disk by default). Export with [toJson] if the user wants a
/// record of what they set.
library;

/// Hard bounds for a per-device limit, in Mbps.
const double minLimitMbps = 0.5;
const double maxLimitMbps = 1000;

class LimitRule {
  const LimitRule({
    required this.deviceMac,
    required this.deviceIp,
    required this.deviceLabel,
    required this.downMbps,
    required this.upMbps,
    this.enabled = true,
  });

  final String deviceMac;
  final String deviceIp;
  final String deviceLabel;
  final double downMbps;
  final double upMbps;
  final bool enabled;

  /// Validate a limit value. Returns an error message, or null when valid.
  static String? validateMbps(double value) {
    if (value.isNaN || value.isInfinite) return 'Enter a number.';
    if (value < minLimitMbps) return 'Minimum is $minLimitMbps Mbps.';
    if (value > maxLimitMbps) return 'Maximum is $maxLimitMbps Mbps.';
    return null;
  }

  Map<String, dynamic> toJson() => {
        'mac': deviceMac,
        'ip': deviceIp,
        'label': deviceLabel,
        'downMbps': downMbps,
        'upMbps': upMbps,
        'enabled': enabled,
      };

  LimitRule copyWith({double? downMbps, double? upMbps, bool? enabled}) =>
      LimitRule(
        deviceMac: deviceMac,
        deviceIp: deviceIp,
        deviceLabel: deviceLabel,
        downMbps: downMbps ?? this.downMbps,
        upMbps: upMbps ?? this.upMbps,
        enabled: enabled ?? this.enabled,
      );
}
