/// Versioned roadmap for WiHisar — what is coming, in which version.
///
/// "Coming soon" is a promise with a version number, not a vague list:
/// every entry names the version that will ship it and what it will do.
/// Nothing here is built yet; the UI shows these as locked cards so the
/// user can see the plan inside the app. All future tools are for the
/// user's OWN network only, same rule as v0.1.0.
library;

/// Status of one roadmap item.
enum RoadmapStatus {
  /// Already shipped — shown so the user can see what landed.
  shipped,

  /// Being built in the next version.
  nextUp,

  /// Planned for a later version.
  planned,

  /// Idea stage — listed so the user can ask for it sooner.
  idea,
}

/// One versioned future feature.
class RoadmapItem {
  const RoadmapItem({
    required this.version,
    required this.title,
    required this.summary,
    required this.features,
    required this.status,
    this.platforms = 'Android • iOS • Windows',
    this.honestNote,
  });

  /// Version that will ship it, e.g. `v0.3.0`.
  final String version;

  final String title;

  /// One-line summary shown on the card.
  final String summary;

  /// Bullet features inside that version.
  final List<String> features;

  final RoadmapStatus status;

  /// Which platforms get it.
  final String platforms;

  /// The honest limitation, shown on the card — same rule as v0.1.0:
  /// WiHisar never fakes a capability.
  final String? honestNote;
}

/// The full roadmap, newest version first in the UI (sorted by version).
const List<RoadmapItem> kRoadmap = [
  RoadmapItem(
    version: 'v0.3.0',
    title: 'IP Scanner & Port Sweep',
    summary:
        'See everything on your own network: every IP, open port and service. SHIPPED.',
    features: [
      'Full subnet sweep (all 254 addresses) with live host discovery',
      'Open-port scan per device with service names (HTTP, SSH, SMB…)',
      'Unknown-device alerts: a new MAC on your WiFi gets flagged',
      'Export scan results as a report',
    ],
    status: RoadmapStatus.shipped,
    honestNote:
        'Scans only the network this device is connected to — your own WiFi.',
  ),
  RoadmapItem(
    version: 'v0.4.0',
    title: 'True in-app update',
    summary:
        'No more manual downloads: tap update in the app and it downloads and installs itself. SHIPPED — this version.',
    features: [
      'Android: APK downloads in the app, system installer opens',
      'Windows: zip downloads, extracts, app restarts on the new version',
      'Live download progress in the update banner',
      'iOS opens the release page (Apple allows no sideload install)',
    ],
    status: RoadmapStatus.shipped,
    honestNote:
        'Android asks once for "install unknown apps" — the system installer always does the installing, never the app silently.',
  ),
  RoadmapItem(
    version: 'v0.5.0',
    title: 'Vulnerability Lab — Linux tools, inside the app',
    summary:
        'Own-network vulnerability checks powered by the Linux tools professionals use.',
    features: [
      'nmap integration: OS detection + vulnerability scripts on your own network',
      'Weak-service detector (old TLS, open Telnet/FTP, default credentials)',
      'Router firmware check: known CVEs for your detected router model',
      'One-tap hardening checklist generated from the findings',
    ],
    status: RoadmapStatus.nextUp,
    platforms: 'Linux • Windows • Android (via companion)',
    honestNote:
        'Desktop-first: nmap runs natively on Linux/Windows. On phones it runs through the WiHisar companion service, never against networks you do not own.',
  ),
  RoadmapItem(
    version: 'v0.6.0',
    title: 'Linux companion & CLI',
    summary: 'WiHisar as a Linux app and terminal tool — the full toolbox.',
    features: [
      'Native Linux desktop build (same cyberpunk UI)',
      'wihisar CLI: scan, test and limit from the terminal',
      'One-click install of the integrated tools (nmap, arp-scan, iperf3)',
      'Scheduled scans + history: how your network changed over time',
    ],
    status: RoadmapStatus.planned,
    platforms: 'Linux',
    honestNote:
        'Tools are installed only with your permission, from your distro\'s own packages.',
  ),
  RoadmapItem(
    version: 'v0.7.0',
    title: 'Smart limiter v2',
    summary: 'Limits that actually work on more routers, with schedules.',
    features: [
      'Verified TP-Link QoS profiles per exact model + firmware',
      'Time-based limits: kids\' devices slow down at bedtime, automatically',
      'Per-device usage history and data caps',
      'OpenWrt one-tap apply (SSH with your approval, shown before running)',
    ],
    status: RoadmapStatus.idea,
    honestNote:
        'V-SOL and most ONU web UIs expose no limiter API — v0.7.0 still will not fake it. Where the router cannot limit, the OpenWrt-bridge path is the answer.',
  ),
  RoadmapItem(
    version: 'v0.8.0',
    title: 'Family network profiles',
    summary: 'One profile per person: their devices, their limits, their time.',
    features: [
      'Profiles: link devices to a person, not just a MAC address',
      'Guest network QR: guests get limited internet, no LAN access',
      'Weekly security report, auto-generated',
    ],
    status: RoadmapStatus.idea,
  ),
];

/// The next version to ship: the first roadmap item that is not shipped yet.
String get nextVersion => kRoadmap
    .firstWhere(
      (i) => i.status != RoadmapStatus.shipped,
      orElse: () => kRoadmap.first,
    )
    .version;
