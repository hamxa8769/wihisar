/// WiFi info service: what the app knows about the current connection.
///
/// PLATFORM HONESTY:
///  - Android / Windows / macOS / Linux: a WiFi scan and the current SSID
///    are available (via the `layrz_wifi` plugin — see README for the exact
///    integration; the plugin is an optional next step and this service
///    degrades gracefully without it).
///  - iOS: Apple exposes NO public WiFi scan API and no SSID API to third
///    party apps. `hasDiscovery()` / `hasCurrentSsid()` are false on iOS.
///    On iOS WiHisar therefore works through the router-login path only:
///    the user enters the SSID (or it comes from the router) and the
///    security test runs on the facts the user supplies. The UI says this.
///
/// This file is the seam: [WifiInfoService] is the interface the UI talks
/// to, and [ManualWifiInfoService] is the v0.1 implementation that asks the
/// user for the facts instead of pretending the platform gave them. A
/// plugin-backed implementation can replace it without touching the UI.
library;

import '../security/security_report.dart';

/// Facts about the currently connected WiFi network.
class WifiFacts {
  const WifiFacts({
    required this.ssid,
    required this.securityType,
    required this.wpsEnabled,
    this.signalDbm,
    this.channel,
    this.band,
    this.source,
  });

  final String ssid;
  final SecurityType securityType;
  final bool wpsEnabled;
  final int? signalDbm;
  final int? channel;
  final String? band;

  /// Where the facts came from, e.g. 'user entry' or 'layrz_wifi scan'.
  final String? source;
}

abstract class WifiInfoService {
  /// True when this platform can scan WiFi networks / read the SSID.
  bool get canScan;

  /// One-line explanation shown in the UI when [canScan] is false.
  String get scanLimitationNote;

  /// Current network facts, or null when the platform cannot provide them
  /// and the user has not entered them yet.
  Future<WifiFacts?> currentFacts();
}

/// v0.1 implementation: the user enters the facts. No fake scan data.
class ManualWifiInfoService implements WifiInfoService {
  ManualWifiInfoService({this.canScan = false});

  @override
  final bool canScan;

  @override
  String get scanLimitationNote =>
      'This device cannot scan WiFi networks from inside the app '
      '(on iOS Apple blocks it entirely). Enter your network details — '
      'WiHisar tests only the network you name.';

  WifiFacts? _facts;

  void setFacts(WifiFacts facts) => _facts = facts;

  @override
  Future<WifiFacts?> currentFacts() async => _facts;
}
