/// Generic adapter: unknown router.
///
/// Lists devices only via the local subnet ARP scan. It never claims to
/// limit bandwidth — an unknown router has no limiter API WiHisar knows,
/// and faking a limit would be worse than saying so.
library;

import '../../devices/device_scan.dart';
import '../router_adapter.dart';
import 'openwrt_adapter.dart';
import 'tplink_adapter.dart';
import 'vsol_adapter.dart';

class GenericAdapter implements RouterAdapter {
  @override
  String get profileId => 'generic';

  @override
  String get vendor => 'Generic';

  @override
  bool get supportsDeviceList => true;

  @override
  bool get supportsBandwidthLimit => false;

  @override
  String get limitMethodDescription => 'Not supported — unknown router.';

  @override
  List<String> get limitations => const [
        'Unknown router: no limiter API is implemented for it.',
        'Device list comes from the subnet ARP scan only, so devices that are connected but silent may be missed.',
        'To get limiting, use an OpenWrt router, or a separate SSID with SQM.',
      ];

  @override
  Future<List<ConnectedDevice>> listDevices({
    required String gatewayIp,
    required RouterCredentials credentials,
  }) async {
    return SubnetScanner().readNeighbourTable();
  }

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
    return LimitResult.unsupported(
      'This router was not recognised, so WiHisar has no limiter API for it '
      'and cannot enforce a $downMbps Mbps limit for $deviceMac. '
      'It will not pretend the limit is applied.',
    );
  }

  @override
  Future<LimitResult> verifyLimit({
    required String gatewayIp,
    required RouterCredentials credentials,
    required String deviceMac,
    String? deviceIp,
    String? expectedFingerprint,
  }) async {
    return LimitResult.unsupported(
      'This router was not recognised, so WiHisar cannot verify whether a limit is in force.',
    );
  }

  @override
  Future<LimitResult> clearLimit({
    required String gatewayIp,
    required RouterCredentials credentials,
    required String deviceMac,
    String? deviceIp,
    String? expectedFingerprint,
  }) async {
    return LimitResult.unsupported(
      'No limit was applied by WiHisar on this router, so there is nothing to clear.',
    );
  }
}

/// Pick the adapter for a detected profile id.
RouterAdapter adapterForProfile(String profileId) {
  switch (profileId) {
    case 'vsol':
      return VsolAdapter();
    case 'tplink':
      return TpLinkAdapter();
    case 'openwrt':
      return OpenWrtAdapter();
    default:
      return GenericAdapter();
  }
}
