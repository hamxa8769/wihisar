/// Automatic router detection.
///
/// Detection runs in order, cheapest and most reliable first, and every
/// piece of evidence adds to a confidence score (0-100) that the UI shows.
/// Nothing here guesses: a low score is reported as a low score.
///
/// Order:
///  1. Gateway IP — from the OS routing table (or the subnet's `.1` address
///     as a heuristic when the platform does not expose the gateway).
///  2. Gateway MAC + IEEE OUI vendor lookup (offline table in `oui.dart`).
///  3. UPnP/SSDP + mDNS discovery (server/model strings).
///  4. HTTP fingerprint of the admin page (Server header, page title).
///  5. SNMP sysDescr, when the router answers SNMP.
///  6. DHCP vendor / hostname hints.
///
/// The fingerprint scorer is pure Dart so it is unit-testable without any
/// network access.
library;

import 'oui.dart';
import 'router_profile.dart';

/// One piece of detection evidence.
class DetectionEvidence {
  const DetectionEvidence(this.source, this.detail, this.points);

  /// e.g. 'OUI', 'HTTP title', 'SSDP', 'SNMP', 'Gateway IP'.
  final String source;
  final String detail;

  /// Points this evidence contributed to the confidence score.
  final int points;
}

/// Result of detecting the gateway router.
class RouterDetection {
  const RouterDetection({
    required this.gatewayIp,
    required this.profile,
    required this.confidence,
    required this.evidence,
    this.gatewayMac,
    this.gatewayVendor,
  });

  final String gatewayIp;
  final RouterProfile profile;

  /// 0-100. <40 = weak guess, 40-69 = likely, >=70 = confident.
  final int confidence;
  final List<DetectionEvidence> evidence;
  final String? gatewayMac;

  /// Vendor from the OUI table, if known.
  final String? gatewayVendor;

  String get confidenceLabel {
    if (confidence >= 70) return 'Confident';
    if (confidence >= 40) return 'Likely';
    return 'Weak guess';
  }

  bool get isConfident => confidence >= 70;
}

/// Inputs to the pure fingerprint scorer. Any field may be null when that
/// source was unavailable — missing evidence simply adds no points.
class Fingerprint {
  const Fingerprint({
    this.serverHeader,
    this.pageTitle,
    this.ssdpServer,
    this.mdnsModel,
    this.snmpSysDescr,
    this.ouiVendor,
    this.dhcpVendor,
    this.gatewayIp,
  });

  final String? serverHeader;
  final String? pageTitle;
  final String? ssdpServer;
  final String? mdnsModel;
  final String? snmpSysDescr;
  final String? ouiVendor;
  final String? dhcpVendor;
  final String? gatewayIp;
}

/// Score one profile against a fingerprint. Pure function, unit-tested.
int scoreProfile(RouterProfile profile, Fingerprint fp) {
  var score = 0;
  // Keyword hits: strongest signal is the admin-page title.
  for (final keyword in profile.keywords) {
    final kw = keyword.toLowerCase();
    if ((fp.pageTitle ?? '').toLowerCase().contains(kw)) score += 35;
    if ((fp.serverHeader ?? '').toLowerCase().contains(kw)) score += 20;
    if ((fp.ssdpServer ?? '').toLowerCase().contains(kw)) score += 20;
    if ((fp.mdnsModel ?? '').toLowerCase().contains(kw)) score += 20;
    if ((fp.snmpSysDescr ?? '').toLowerCase().contains(kw)) score += 25;
  }
  // OUI vendor match.
  if (fp.ouiVendor != null &&
      fp.ouiVendor!.toLowerCase() == profile.vendor.toLowerCase()) {
    score += 30;
  }
  // DHCP vendor hint.
  if (fp.dhcpVendor != null &&
      fp.dhcpVendor!.toLowerCase().contains(profile.vendor.toLowerCase())) {
    score += 15;
  }
  // Gateway IP is a weak hint on its own (many vendors share 192.168.1.1).
  if (fp.gatewayIp != null &&
      profile.commonGatewayIps.contains(fp.gatewayIp)) {
    score += 10;
  }
  return score.clamp(0, 100);
}

/// Pick the best-matching profile for a fingerprint, with evidence.
RouterDetection detectFromFingerprint({
  required String gatewayIp,
  required Fingerprint fingerprint,
  String? gatewayMac,
}) {
  RouterProfile best = profileById('generic');
  var bestScore = -1;
  for (final profile in routerProfiles) {
    if (profile.id == 'generic') continue;
    final s = scoreProfile(profile, fingerprint);
    if (s > bestScore) {
      bestScore = s;
      best = profile;
    }
  }
  // Evidence list, in detection order.
  final evidence = <DetectionEvidence>[];
  if (gatewayMac != null) {
    final vendor = vendorForMac(gatewayMac);
    evidence.add(DetectionEvidence(
        'Gateway MAC', '$gatewayMac → $vendor', vendor == 'Unknown vendor' ? 5 : 30));
  }
  if (fingerprint.pageTitle != null && fingerprint.pageTitle!.isNotEmpty) {
    evidence.add(DetectionEvidence(
        'HTTP title', fingerprint.pageTitle!, 35));
  }
  if (fingerprint.serverHeader != null && fingerprint.serverHeader!.isNotEmpty) {
    evidence.add(DetectionEvidence(
        'HTTP Server header', fingerprint.serverHeader!, 20));
  }
  if (fingerprint.ssdpServer != null && fingerprint.ssdpServer!.isNotEmpty) {
    evidence.add(DetectionEvidence('SSDP/UPnP', fingerprint.ssdpServer!, 20));
  }
  if (fingerprint.mdnsModel != null && fingerprint.mdnsModel!.isNotEmpty) {
    evidence.add(DetectionEvidence('mDNS', fingerprint.mdnsModel!, 20));
  }
  if (fingerprint.snmpSysDescr != null && fingerprint.snmpSysDescr!.isNotEmpty) {
    evidence.add(DetectionEvidence('SNMP', fingerprint.snmpSysDescr!, 25));
  }
  evidence.add(const DetectionEvidence('Gateway IP', 'gateway from OS routing', 10));

  // A gateway-IP match alone is worth 10 points and is shared by almost
  // every vendor, so it must never pick a vendor on its own. A profile
  // needs at least one real signal (score > 10) to be chosen.
  final confidence = bestScore <= 10 ? 10 : bestScore;
  return RouterDetection(
    gatewayIp: gatewayIp,
    profile: bestScore <= 10 ? profileById('generic') : best,
    confidence: confidence,
    evidence: evidence,
    gatewayMac: gatewayMac,
    gatewayVendor:
        gatewayMac == null ? null : vendorForMac(gatewayMac),
  );
}

/// Heuristic gateway for a local IPv4 address: the `.1` of its /24 subnet.
/// Used only when the platform does not expose the real gateway; the UI
/// labels it as a guess and lets the user correct it.
String likelyGatewayFor(String localIp) {
  final parts = localIp.split('.');
  if (parts.length != 4) return '192.168.1.1';
  return '${parts[0]}.${parts[1]}.${parts[2]}.1';
}

/// Common gateway IPs to probe when auto-detection finds nothing.
const List<String> commonGatewayIps = [
  '192.168.1.1',
  '192.168.0.1',
  '192.168.100.1',
  '192.168.131.1',
  '192.168.8.1',
  '10.0.0.1',
];
