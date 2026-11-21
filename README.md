# WiHisar — وائی حصار (WiFi Fortress)

**WiHisar v0.4.0** — a lightweight Flutter app for **Android, iOS and Windows** that tests the security of **your own WiFi** and limits bandwidth on **your own router**. Educational use only. Cyberpunk UI, true in-app update (download & install inside the app), versioned roadmap, one-tap auto network scan, Linux tools (nmap, arp-scan).

> **What WiHisar is NOT:** it is not a password cracker. There is no handshake capture, no dictionary or brute-force code, no aircrack-ng / hashcat / wifite, and no code that attacks other networks. The security tester estimates the strength of a password *you* type in for *your own* network, locally on your device, and never stores or sends it.

## What's new in v0.4.0 — true in-app update

- **Download & install inside the app** — no more manual downloads. When
  a new version is out, tap "Download & install" on the banner or the
  Roadmap tab: Android downloads the APK and opens the system installer,
  Windows downloads the zip and restarts on the new version. Live progress
  is shown while it downloads. (iOS opens the release page — Apple allows
  no sideload install from inside an app.)

## What's new in v0.3.0 — auto scan, no manual entry

- **Auto network detection** — the app finds your own IP, subnet, gateway
  and WiFi name itself. Nothing to type.
- **One-tap scan** — Devices tab → "Scan my network": sweeps every host,
  shows MAC + vendor, hostnames and open ports with a live progress bar.
- **Linux tools** — on the desktop build, WiHisar detects and runs `nmap`,
  `arp-scan`, `iw`, `nmcli`, `iperf3` on your own network (command shown
  before it runs). Aircrack-ng is detected only — handshake capture and
  password cracking are NOT in this app, by design.

## What's new in v0.2.0

- **Cyberpunk UI** — dark neon theme (cyan / magenta / lime on near-black),
  monospace headings, glowing panels. No new assets: the look is colour +
  borders only, so the app stays lightweight.
- **In-app updater** — checks GitHub Releases on startup. A new version
  shows a banner at the top of the app + an update button; tap to open the
  release and install. Nothing downloads or installs silently.
- **Roadmap tab ("Coming Soon")** — every future feature with its version
  number, inside the app. See [Roadmap](#roadmap) below.
- **Versioning rule**: every update bumps the version and ships as a GitHub
  release (v0.2.0 → v0.3.0 → …), so the updater always has something to find.

## Full feature list (v0.2.0)

| # | Feature | Status |
|---|---------|--------|
| 1 | Own-WiFi security tester — entropy, crack-time estimate, score/grade, fixes | ✅ Live |
| 2 | Automatic router detection — gateway IP, MAC OUI, UPnP/mDNS, HTTP fingerprint, SNMP, DHCP | ✅ Live |
| 3 | Router profiles — V-SOL, TP-Link, Huawei, ZTE, OpenWrt, generic | ✅ Live |
| 4 | Connected-device list — ARP subnet scan, vendor lookup | ✅ Live |
| 5 | Per-device bandwidth limits via router adapters | ✅ Live (where the router allows it) |
| 6 | Cyberpunk UI/UX — neon dark theme, 4 tabs | ✅ Live |
| 7 | In-app updater — GitHub Releases check, banner, one-tap open | ✅ Live |
| 8 | True in-app update — download & install inside the app (Android installer, Windows restart) | ✅ Live in v0.4.0 |
| 9 | Versioned roadmap inside the app | ✅ Live |
| 10 | IP scanner & port sweep — auto subnet sweep, open ports, live progress | ✅ Live in v0.3.0 |
| 11 | Linux tools — nmap, arp-scan, iw, nmcli, iperf3 detection + run | ✅ Live in v0.3.0 (desktop) |
| 12 | Vulnerability Lab — nmap vuln scripts, weak-service + router CVE checks | 🔜 v0.5.0 |
| 13 | Linux companion app + CLI, one-click tool install | 🔜 v0.6.0 |
| 14 | Smart limiter v2 — verified TP-Link QoS, schedules, usage history | 🔜 v0.7.0 |
| 15 | Family network profiles, guest QR, weekly report | 🔜 v0.8.0 |

## Roadmap

| Version | Feature | Platforms |
|---------|---------|-----------|
| v0.3.0 | IP Scanner & Port Sweep — full subnet sweep, open ports + services, unknown-device alerts, report export | Android • iOS • Windows | ✅ Shipped |
| v0.4.0 | True in-app update — download & install inside the app (Android system installer, Windows restart) | Android • Windows | ✅ Shipped |
| v0.5.0 | Vulnerability Lab — nmap OS detection + vuln scripts, weak-service detector, router firmware CVE check, hardening checklist | Linux • Windows • Android (via companion) |
| v0.6.0 | Linux companion & CLI — native Linux build, `wihisar` terminal tool, one-click install of nmap / arp-scan / iperf3, scheduled scans + history | Linux |
| v0.7.0 | Smart limiter v2 — verified TP-Link QoS per model, time-based limits, per-device usage + data caps, OpenWrt one-tap apply | Android • iOS • Windows |
| v0.8.0 | Family network profiles — devices per person, guest-network QR, weekly security report | Android • iOS • Windows |

All future tools are for **your own network only**, same rule as v0.1.0.
Desktop-first for the Linux tools: nmap runs natively on Linux/Windows;
on phones it runs through the WiHisar companion service.

## Features (v0.1.0)

### 1. Own-WiFi security tester — tab "Test"
- Enter your own SSID, security type (WPA3 / WPA2 / WPA / WEP / Open), WPS on/off, and your own WiFi password.
- The password is analysed **locally only** (entropy = length × log₂(pool size)) and the field is cleared right after the check. It is never stored, logged or sent anywhere.
- Report: score 0–100, grade A–F, verdict, entropy in bits, estimated offline crack time at three stated hash rates (laptop GPU ~100k/s, single GPU ~1M/s, 8-GPU rig ~10M/s), and concrete fixes (use WPA3, 16+ characters, turn WPS off, change the default admin password).
- The `lib/security/` folder has **no Flutter dependency** — copy it into another Dart/Flutter project to reuse the tester.

### 2. Router detection + device list + limiter — tabs "Devices" and "Limits"
- **Automatic router detection**, in order, with a confidence score shown in the UI:
  1. Gateway IP from the OS routing table (or the subnet's `.1` as a labelled guess)
  2. Gateway MAC + offline IEEE OUI vendor lookup (`lib/router/oui.dart`)
  3. UPnP/SSDP + mDNS discovery
  4. HTTP fingerprint of the admin page (Server header, page title)
  5. SNMP sysDescr, when available
  6. DHCP vendor hints
- **Profiles first:** V-SOL, TP-Link, Huawei, ZTE, OpenWrt, generic. Each profile carries its common gateway IPs, public default login, and an honest note about whether app-controlled limiting exists for it.
- **Device list:** subnet ARP/ping scan in the `network_tools` style — prime the neighbour cache, then read the OS ARP table once (`ip neigh` / `arp -a` / `arp -an`). Shows IP, MAC, vendor (OUI), hostname where available.
- **Limiter:** a `RouterAdapter` interface with V-SOL, TP-Link, OpenWrt (LuCI/SSH, SQM/HTB) and generic adapters. Per-device download/upload limit in Mbps (0.5–1000).
  - **Honest limits, v0.1:** V-SOL and most Huawei/ZTE ONU web UIs expose **no per-device bandwidth control**, so WiHisar says so instead of faking a limit. TP-Link QoS submission is firmware-specific and is only enabled once verified against the exact model (v0.2). OpenWrt generates the exact `tc` HTB commands for review; automatic SSH execution is v0.2.
  - Fallback when a router cannot limit: put it in bridge mode behind an OpenWrt router, or use a separate SSID with SQM.

## V-SOL login notes (your router)
- Older V-SOL ONUs: gateway `192.168.1.1`, username `admin`, password `stdONU101`.
- Newer V-SOL routers: gateway `192.168.131.1`, **no default password** — you set one on first login.
- Change the admin password after first login. WiHisar never stores it.

## iOS limitation (honest)
Apple exposes **no public WiFi scan API** and no SSID API to third-party apps. On iOS, WiHisar therefore works through the router-login path only: you enter the SSID (or it comes from the router) and the security test runs on the facts you supply. Android and Windows can scan; see `lib/wifi/wifi_info.dart`.

## Recommended next integration — `layrz_wifi`
For live SSID/scan on Android/Windows, the `layrz_wifi` Flutter plugin is the recommended next step (`pub.dev/packages/layrz_wifi`): `LayrzWifi.instance`, `hasDiscovery()`, `hasCurrentSsid()`. It is **not** bundled in v0.1.0 so the app stays lightweight and `flutter test` runs on a plain Linux VM with no Android SDK. Add it behind the `WifiInfoService` seam in `lib/wifi/wifi_info.dart` — the UI does not need to change.

## Setup

```bash
# Flutter 3.24+ required
flutter pub get
flutter analyze
flutter test

# Run (pick one)
flutter run -d android
flutter run -d ios
flutter run -d windows
```

Builds (need the platform SDKs — Android SDK / Xcode / Visual Studio):
```bash
flutter build apk --release        # Android
flutter build ipa --release        # iOS (macOS + Xcode)
flutter build windows --release    # Windows
```

## Project layout

```
lib/
  main.dart                  # 3-tab UI: Test / Devices / Limits
  security/                  # reusable, Flutter-free tester
    entropy.dart             # pool size, entropy, crack-time estimate
    security_report.dart     # score, grade, fixes
    security_tester.dart     # entry point: testOwnWifi()
  router/
    router_profile.dart      # V-SOL / TP-Link / Huawei / ZTE / OpenWrt / generic
    router_detect.dart       # fingerprint scorer + confidence
    oui.dart                 # small offline OUI table
    router_adapter.dart      # RouterAdapter interface + LimitResult
    adapters/
      vsol_adapter.dart      # device list yes, limit no (honest)
      tplink_adapter.dart    # device list + QoS (verify per firmware)
      openwrt_adapter.dart   # DHCP leases + tc HTB command generation
      generic_adapter.dart   # scan only, never fakes a limit
  devices/device_scan.dart   # ARP parsers (Linux/Windows/BSD) + scanner
  limiter/
    limit_rule.dart          # rule + 0.5–1000 Mbps validation
    limiter_service.dart     # applies rules, records only confirmed success
  wifi/wifi_info.dart        # WifiInfoService seam + iOS note
test/
  entropy_test.dart
  router_detect_test.dart
  device_scan_limiter_test.dart
```

## Verification on this VM (2026-11-21)
- Flutter 3.50.1 / Dart 3.14.0 (existing `~/flutter` SDK — no new SDK was installed).
- `flutter analyze`: clean except 1 info-level notice — Flutter 3.50 flags `package:flutter/material.dart` as deprecated in favour of `material_ui`, but no such package exists in this SDK, so `material.dart` is still the correct import.
- `flutter test`: **40/40 passed** (entropy/crack-time, fingerprint scoring, ARP parsers, limiter honesty).
- Native binary builds were **not** produced on this VM: Android needs the Android SDK, iOS needs macOS+Xcode, Windows needs Visual Studio, and even the bonus Linux build stops at CMake because this VM cannot install `libgtk-3-dev` (held `libzstd1` package conflict — a VM limitation, not a code problem). Run the builds on a machine with the platform SDK (commands above).

## What still needs the user's router login to test live
- V-SOL DHCP-client page path (varies by firmware — the adapter tries 4 known paths, then falls back to the ARP scan).
- TP-Link QoS form for the exact Archer/Deco model + firmware.
- OpenWrt LuCI RPC / SSH apply path (v0.2).
- Real-device scan on Android (needs `NEARBY_WIFI_DEVICES` / location permission) and on iOS (router path only).

## License
MIT — see `LICENSE` when the repo is created (repo: `wihisar`, to be created by the user on GitHub; this folder is the local code only).
