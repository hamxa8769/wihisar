/// RouterAdapter interface: one implementation per router vendor.
///
/// Every adapter must answer honestly about what it can do. If a router
/// cannot list devices or cannot enforce a limit, the adapter says so —
/// the UI then shows that honestly instead of pretending a limit is applied.
///
/// Credentials are supplied per call by the user and are never stored by
/// the adapters. Network access in this MVP is deliberately conservative:
/// adapters expose the exact HTTP endpoints / commands they use so they can
/// be reviewed and tested against a real router before being trusted.
library;

import '../devices/device_scan.dart';

/// Login credentials for the user's OWN router, supplied by the user.
class RouterCredentials {
  const RouterCredentials({required this.username, required this.password});

  final String username;
  final String password;
}

/// Result of applying (or failing to apply) a bandwidth limit.
class LimitResult {
  const LimitResult({
    required this.success,
    required this.message,
    this.appliedDownMbps,
    this.appliedUpMbps,
  });

  final bool success;
  final String message;
  final double? appliedDownMbps;
  final double? appliedUpMbps;

  factory LimitResult.unsupported(String reason) =>
      LimitResult(success: false, message: reason);

  factory LimitResult.applied(double down, double up, String how) =>
      LimitResult(
        success: true,
        message: 'Limit applied ($how): $down Mbps down / $up Mbps up.',
        appliedDownMbps: down,
        appliedUpMbps: up,
      );
}

abstract class RouterAdapter {
  /// Profile id this adapter implements, e.g. `vsol`.
  String get profileId;

  /// Human name, e.g. `V-SOL`.
  String get vendor;

  /// Can this adapter list connected devices from the router?
  bool get supportsDeviceList;

  /// Can this adapter actually enforce a per-device bandwidth limit?
  bool get supportsBandwidthLimit;

  /// How the limit is enforced, in plain words (shown in the UI).
  String get limitMethodDescription;

  /// Honest limitations of this adapter (shown in the UI).
  List<String> get limitations;

  /// List devices connected to the router.
  ///
  /// Implementations should prefer the router's own DHCP/association list
  /// and fall back to the subnet scan in `device_scan.dart` when the router
  /// does not expose one.
  Future<List<ConnectedDevice>> listDevices({
    required String gatewayIp,
    required RouterCredentials credentials,
  });

  /// Apply a per-device download/upload limit (Mbps).
  Future<LimitResult> setLimit({
    required String gatewayIp,
    required RouterCredentials credentials,
    required String deviceMac,
    required double downMbps,
    required double upMbps,
  });

  /// Remove a previously applied limit for a device.
  Future<LimitResult> clearLimit({
    required String gatewayIp,
    required RouterCredentials credentials,
    required String deviceMac,
  });
}
