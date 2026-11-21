# Changelog — WiHisar

All notable changes, newest first. Versioning: **every update bumps the
version** and ships as a GitHub release; the in-app updater offers it from
inside the app (banner + Roadmap tab). No silent downloads, no silent installs.

## v0.5.0 — 2026-11-21

### Changed — professional robustness upgrade (scanning, limiter, Linux tools)
- **Scanning finds silent devices**: the ARP cache is now primed before reading (devices that ignore ping are found), the real subnet prefix is read from the OS instead of assuming /24, mobile gateway comes from the OS WiFi info, reverse-DNS and port probes run in parallel, and scans can be cancelled.
- **New-device alerts**: a MAC never seen before is flagged NEW; last-seen devices are remembered on the phone so the flag survives restarts.
- **Router auto-detect**: the gateway page title + Server header are read automatically after the network is found — no manual fields needed.
- **Real limiter**: OpenWrt limits are actually applied over SSH (fingerprint shown and confirmed first, `tc` result verified); TP-Link login fixed (MD5 password) and QoS rules are verified against the router before the app claims success; V-SOL form login added so its DHCP list works on more firmwares. Limit rules are saved on the device.
- **Linux tools completed**: nmap `-sV` deep scan wired into the results, arp-scan + nmap return real errors (not silent empty lists), iperf3 speed test, nmcli WiFi scan, tshark protocol summary, and install commands for every missing tool (Windows `where` lookup fixed).
- **Device identification**: much bigger offline vendor table, device-kind guessing (camera/printer/phone/computer) from vendor + open ports, wider risk flags (Telnet/FTP/RDP/VNC).
- **Verified live**: the new scan engine was run against a real network — it read the true /30 prefix (not the old /24 assumption), found a gateway that ignored ping via ARP priming, and finished in under half a second. Missing Linux tools now report a clear error with the install command instead of a silent empty list.
- Tests: flutter test 153/153 passed, flutter analyze clean (No issues found!).

## v0.4.1 — 2026-11-21

### Fixed — release signing (the "App not installed" fix)
- **Stable release keystore**: the APK is now signed with one permanent
  WiHisar release key (RSA 2048, valid until 2054) instead of Flutter's
  per-run debug key. That debug key changed on every CI build, so Android
  refused to install a new version over the old one ("App not installed").
- **One last uninstall**: moving from any build before v0.4.1 to v0.4.1
  still needs the old app uninstalled once (its signature is the old
  debug key). After v0.4.1, every update — including the in-app updater —
  installs over the old app with no uninstall, forever, because the key
  never changes again.
- The release workflow now verifies the APK signature in CI (fails the
  run if the certificate is not the WiHisar release key).
- No code changes to the app itself in this release — same features as
  v0.4.0, only the signature is different.

## v0.4.0 — 2026-11-21

### Added — true in-app update (no more manual downloads)
- **Download & install inside the app**: when a new version is out, the
  banner and the Roadmap tab offer "Download & install". Android downloads
  the APK into the app cache and opens the system installer (which always
  does the installing — the app never installs silently, and Android asks
  once for "install unknown apps"). Windows downloads the zip, extracts it
  and restarts the app on the new version via a small update script.
- **Live download progress** in the update banner and the Roadmap tab.
- iOS / macOS / Linux still open the release page — Apple and the desktop
  stores allow no sideload install from inside the app, and the UI says so.
- `path_provider` + `archive` dependencies; Android `REQUEST_INSTALL_PACKAGES`
  permission + FileProvider (MainActivity.kt channel `wihisar.app_update`).

### Changed
- Roadmap renumbered: v0.4.0 is the in-app update (shipped), v0.5.0
  Vulnerability Lab is next up, Linux companion v0.6.0, Smart limiter v2
  v0.7.0, Family profiles v0.8.0.

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
