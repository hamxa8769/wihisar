/// WiHisar security tester — reusable module entry point.
///
/// Copy the whole `lib/security/` folder into another Dart/Flutter project
/// and import this file. It has zero Flutter and zero platform dependencies.
///
/// What it does (own WiFi only, educational):
///  1. Takes the network facts the app already knows (SSID, security type,
///     WPS on/off, signal/channel) — supplied by the caller, never probed
///     from other networks.
///  2. Analyses a password the user types in for THEIR OWN network, locally.
///  3. Returns a [SecurityReport] with a score, grade, crack-time estimate
///     and fixes.
///
/// What it deliberately does NOT do:
///  - No handshake capture, no monitor mode, no deauthentication.
///  - No dictionary, wordlist or brute-force code of any kind.
///  - No aircrack-ng / hashcat / wifite integration.
///  - The password is never stored, logged or sent anywhere.
library;

export 'entropy.dart';
export 'security_report.dart';

import 'entropy.dart';
import 'security_report.dart';

/// Run the full own-WiFi security test.
///
/// [password] is the user's OWN WiFi password, typed in by them. It is used
/// only to compute entropy inside [analysePassword] and is not retained in
/// the returned report (the report keeps only the analysis, never the
/// password itself).
SecurityReport testOwnWifi({
  required String ssid,
  required SecurityType securityType,
  required bool wpsEnabled,
  required String password,
  int? signalDbm,
  int? channel,
  String? band,
}) {
  return SecurityReport(
    ssid: ssid,
    securityType: securityType,
    wpsEnabled: wpsEnabled,
    passwordAnalysis: analysePassword(password),
    signalDbm: signalDbm,
    channel: channel,
    band: band,
  );
}
