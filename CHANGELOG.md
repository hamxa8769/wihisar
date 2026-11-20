# Changelog — WiHisar

All notable changes, newest first. Versioning: **every update bumps the
version** and ships as a GitHub release; the in-app updater offers it from
inside the app (banner + Roadmap tab). No silent downloads, no silent installs.

## v0.2.0 — 2026-11-21

### Added
- **Cyberpunk UI/UX**: dark neon theme (cyan/magenta/lime on near-black),
  monospace display headings, glowing panel cards, neon chips. No new
  assets — the look comes from colour and borders only, so the app stays
  lightweight.
- **In-app updater**: checks GitHub Releases on startup (`lib/update/`).
  When a newer tag exists, a banner appears at the top of the app and an
  update button in the AppBar; tapping opens the release page (or the
  matching asset: APK on Android, zip/exe on Windows). Version comparison
  is pure and unit-tested; the check never throws — offline just means
  "could not check".
- **Roadmap tab ("Coming Soon")**: every future feature with its version
  number — v0.3.0 IP Scanner & Port Sweep, v0.4.0 Vulnerability Lab
  (Linux tools: nmap, weak-service detector, router CVE check),
  v0.5.0 Linux companion & CLI, v0.6.0 Smart limiter v2, v0.7.0 Family
  network profiles. Each card carries its honest limitation, same rule
  as v0.1.0: nothing is faked.
- `url_launcher` dependency (official plugin) for opening release pages.

### Changed
- Version 0.1.0 → 0.2.0. About dialog now shows the version, the update
  rule, and a "Check for updates" action.

## v0.1.0 — 2026-11-21

- First MVP: own-WiFi security tester (entropy + crack-time estimate,
  score/grade report, no cracking, password never stored), automatic
  router detection with confidence score (V-SOL / TP-Link / Huawei / ZTE /
  OpenWrt / generic), ARP device scan, per-device bandwidth limits via
  router adapters. Flutter, Android + iOS + Windows. Tests 40/40.
- Honest limits: V-SOL lists devices but cannot enforce a limit (no
  documented API); OpenWrt shows `tc` HTB commands for review only;
  iOS uses the router-login path (no public WiFi scan API).
