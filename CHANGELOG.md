# Changelog — WiHisar

All notable changes, newest first. Versioning: **every update bumps the
version** and ships as a GitHub release; the in-app updater offers it from
inside the app (banner + Roadmap tab). No silent downloads, no silent installs.

## v0.3.0 — 2026-11-21

### Added — auto scan (no more manual entry)
- **Auto network detection**: the app finds your own IP, subnet and gateway
  from the OS (routing table, else the subnet `.1` as a labelled guess) and
  the WiFi name from the system — nothing to type.
- **One-tap network scan** (`lib/scan/`): ping sweep of every host in the
  subnet, ARP attach for MAC + vendor, reverse-DNS hostnames, and a TCP
  probe of the common ports (SSH/HTTP/SMB/RTSP…) with banner grab. Live
  progress bar, per-host open-port list, `[ROUTER]` / `[THIS DEVICE]` /
  `[CHECK]` (Telnet/FTP open) flags. Tap a host to limit it.
- **Linux tools layer** (`lib/tools/linux_tools.dart`): detects installed
  tools and runs the safe, own-network commands — `nmap -sn` ping scan,
  `nmap -sV` service scan, `arp-scan --localnet`, plus `iw` / `nmcli` /
  `iperf3` detection. Every command is shown before it runs; desktop only.
- **Aircrack-ng boundary**: the suite is detected and its safe check is
  offered, but handshake capture and password cracking are NOT built into
  WiHisar — the app says so on the card. Same own-network rule as v0.1.0.
- `network_info_plus` dependency (SSID auto-fill).

### Changed
- Devices tab rebuilt around the auto scan; router detection kept as an
  optional section (only needed for the limiter).
- Roadmap: v0.3.0 marked SHIPPED, v0.4.0 Vulnerability Lab is next up.

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
