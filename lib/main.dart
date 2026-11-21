// ignore_for_file: deprecated_member_use
/// WiHisar v0.5.0 — own-WiFi security tester + bandwidth limiter.
///
/// Educational, own-router only. No password cracking of any kind: the
/// security test estimates the strength of a password the user types in
/// for THEIR OWN network, locally, and never stores or sends it.
///
/// v0.5.0: professional robustness upgrade — scanning that finds silent
/// devices, a limiter that really enforces (OpenWrt SSH, TP-Link QoS
/// verified), Linux tools wired end-to-end, new-device alerts, router
/// auto-detect.
library;

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'devices/device_scan.dart';
import 'limiter/limit_rule.dart';
import 'limiter/limiter_service.dart';
import 'roadmap/roadmap.dart';
import 'router/adapters/generic_adapter.dart';
import 'router/adapters/openwrt_adapter.dart';
import 'router/adapters/tplink_adapter.dart';
import 'router/router_adapter.dart';
import 'router/router_detect.dart';
import 'scan/auto_scan.dart';
import 'scan/host.dart';
import 'scan/scan_history.dart';
import 'security/security_tester.dart';
import 'theme/cyberpunk_theme.dart';
import 'tools/linux_tools.dart';
import 'update/app_update.dart';
import 'update/installer.dart';
import 'widgets/cyber_widgets.dart';
import 'wifi/wifi_info.dart';

void main() => runApp(const WiHisarApp());

class WiHisarApp extends StatelessWidget {
  const WiHisarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WiHisar — وائی حصار',
      debugShowCheckedModeBanner: false,
      theme: CyberpunkTheme.dark,
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;

  // --- Test tab state ---
  final _ssidCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  SecurityType _security = SecurityType.wpa2;
  bool _wps = false;
  SecurityReport? _report;

  // --- Devices / auto-scan state ---
  final _gatewayCtrl = TextEditingController(text: '192.168.1.1');
  final _titleCtrl = TextEditingController();
  final _serverCtrl = TextEditingController();
  final _iperfServerCtrl = TextEditingController();
  final _tsharkIfaceCtrl = TextEditingController();
  RouterDetection? _detection;
  LocalNetwork? _network;
  List<ScannedHost> _hosts = [];
  bool _scanning = false;
  bool _cancelScan = false;
  double _scanProgress = 0;
  String _scanPhase = '';
  String _scanNote = '';
  final _scanHistory = ScanHistory();
  Set<String> _newMacs = {};
  List<LinuxTool> _tools = [];
  bool _toolsChecked = false;
  bool _toolsBusy = false;
  String _toolsNote = '';

  // --- In-app updater state ---
  UpdateCheckResult? _updateResult;
  bool _checkingUpdate = false;
  bool _downloading = false;
  double _downloadProgress = 0;
  String _downloadNote = '';

  @override
  void initState() {
    super.initState();
    _checkForUpdate(silent: true);
    _limiter.loadRules().then((_) {
      if (mounted) setState(() {});
    });
    _scanHistory.load();
    _detectNetwork();
  }

  Future<void> _checkForUpdate({bool silent = false}) async {
    if (_checkingUpdate) return;
    setState(() => _checkingUpdate = true);
    final result = await checkForUpdate();
    if (!mounted) return;
    setState(() {
      _updateResult = result;
      _checkingUpdate = false;
    });
    if (!silent && mounted) {
      final info = result.info;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.error ??
                (result.updateAvailable
                    ? 'Update available: v${info!.latestVersion} — open the Roadmap tab to install it.'
                    : 'You are on the latest version (v$kAppVersion).'),
          ),
        ),
      );
    }
  }

  /// True in-app update: download the new version and install it without
  /// leaving the app. Android downloads the APK and opens the system
  /// installer; Windows downloads the zip, extracts it and restarts the
  /// app on the new version. iOS/macOS/Linux have no sideload path, so
  /// the release page opens instead.
  Future<void> _openUpdate() async {
    final info = _updateResult?.info;
    if (info == null || _downloading) return;
    final platform = Theme.of(context).platform.name;
    final asset = info.assetFor(platform);
    if (asset == null || (!Platform.isAndroid && !Platform.isWindows)) {
      final uri = Uri.parse(info.releasePageUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Open this link to update: ${info.releasePageUrl}')),
        );
      }
      return;
    }
    setState(() {
      _downloading = true;
      _downloadProgress = 0;
      _downloadNote = 'Downloading v${info.latestVersion}…';
    });
    try {
      final updater = InAppUpdater();
      final file = await updater.downloadFile(
        asset.downloadUrl,
        fileName: asset.name,
        onProgress: (received, total) {
          if (!mounted) return;
          if (total != null && total > 0) {
            setState(() => _downloadProgress = received / total);
          }
        },
      );
      if (!mounted) return;
      if (Platform.isAndroid) {
        setState(() => _downloadNote = 'Download complete — opening installer…');
        final ok = await updater.installApk(file);
        if (!mounted) return;
        setState(() {
          _downloading = false;
          _downloadNote = ok
              ? 'Installer opened — follow the system prompt to install v${info.latestVersion}.'
              : 'Could not open the installer. Open the release page to install it manually.';
        });
      } else {
        // Windows: extract + restart on the new version (this exits).
        setState(() => _downloadNote = 'Download complete — restarting on the new version…');
        await applyWindowsUpdate(zipFile: file);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _downloadNote = 'Update failed: $e — check your connection and try again.';
      });
    }
  }
  ConnectedDevice? _selectedDevice;
  double _downMbps = 5;
  double _upMbps = 2;
  String _limitNote = '';
  final _routerUserCtrl = TextEditingController(text: 'admin');
  final _routerPassCtrl = TextEditingController();
  final _limiter = LimiterService(GenericAdapter());
  TpLinkProbe? _tplinkProbe;
  bool _probingTplink = false;
  String? _sshFingerprint;
  bool _sshFingerprintConfirmed = false;
  bool _probingSsh = false;
  String _sshNote = '';

  RouterAdapter get _adapter => _detection == null
      ? GenericAdapter()
      : adapterForProfile(_detection!.profile.id);

  @override
  void dispose() {
    // The WiFi password is never stored: clear it when the page is gone.
    _passwordCtrl.clear();
    _routerPassCtrl.clear();
    _ssidCtrl.dispose();
    _passwordCtrl.dispose();
    _gatewayCtrl.dispose();
    _titleCtrl.dispose();
    _serverCtrl.dispose();
    _iperfServerCtrl.dispose();
    _tsharkIfaceCtrl.dispose();
    _routerUserCtrl.dispose();
    _routerPassCtrl.dispose();
    super.dispose();
  }

  void _runTest() {
    final ssid = _ssidCtrl.text.trim();
    if (ssid.isEmpty) {
      setState(() => _report = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your own WiFi network name (SSID).')),
      );
      return;
    }
    final report = testOwnWifi(
      ssid: ssid,
      securityType: _security,
      wpsEnabled: _wps,
      password: _passwordCtrl.text,
    );
    setState(() => _report = report);
    // Clear the password field right after the (local, in-memory) analysis.
    _passwordCtrl.clear();
  }

  void _detectRouter() {
    final fp = Fingerprint(
      pageTitle: _titleCtrl.text.trim().isEmpty ? null : _titleCtrl.text.trim(),
      serverHeader:
          _serverCtrl.text.trim().isEmpty ? null : _serverCtrl.text.trim(),
      gatewayIp: _gatewayCtrl.text.trim(),
    );
    setState(() {
      _detection = detectFromFingerprint(
        gatewayIp: _gatewayCtrl.text.trim(),
        fingerprint: fp,
      );
      _limiter.adapter = _adapter;
    });
  }

  /// Find the network this device is on — no manual entry. Fills the SSID
  /// (Test tab) and gateway (Devices tab) automatically. Best effort: if
  /// the OS will not tell us, the fields stay editable by hand.
  /// On phones the gateway comes from the OS WiFi info (the routing
  /// table is often unreadable from an app sandbox); the router is then
  /// auto-detected from its own admin page.
  Future<void> _detectNetwork() async {
    String? ssid;
    String? wifiGateway;
    try {
      ssid = await NetworkInfo().getWifiName();
      if (ssid != null) ssid = ssid.replaceAll('"', '').trim();
    } catch (_) {
      // SSID unavailable on this device — user can type it.
    }
    try {
      wifiGateway = await NetworkInfo().getWifiGatewayIP();
    } catch (_) {
      // Gateway unavailable — the route-table path below covers it.
    }
    var network = await AutoScanner().detectLocalNetwork(
      ssidOverride: ssid,
    );
    if (network != null &&
        !network.gatewayFromRoute &&
        wifiGateway != null &&
        wifiGateway.isNotEmpty) {
      network = LocalNetwork(
        localIp: network.localIp,
        prefix: network.prefix,
        gatewayIp: wifiGateway,
        gatewayFromRoute: true,
        ssid: network.ssid,
        interfaceName: network.interfaceName,
      );
    }
    if (!mounted) return;
    setState(() {
      _network = network;
      if (network != null) {
        _gatewayCtrl.text = network.gatewayIp ?? _gatewayCtrl.text;
        if (ssid != null && ssid.isNotEmpty && _ssidCtrl.text.isEmpty) {
          _ssidCtrl.text = ssid;
        }
      }
    });
    await _autoDetectRouter();
  }

  /// Read the router's own admin page (title + Server header) and detect
  /// the vendor automatically — no manual fields needed. Never throws;
  /// on failure the previous detection (if any) stays.
  Future<void> _autoDetectRouter() async {
    final gw = _network?.gatewayIp ?? _gatewayCtrl.text.trim();
    if (gw.isEmpty) return;
    String? gwMac;
    for (final h in _hosts) {
      if (h.isGateway && h.mac != null && h.mac!.isNotEmpty) {
        gwMac = h.mac;
      }
    }
    final detection = await detectRouterAutomatically(
      gatewayIp: gw,
      gatewayMac: gwMac,
    );
    if (!mounted) return;
    setState(() {
      _detection = detection;
      _limiter.adapter = _adapter;
    });
  }

  /// One-tap scan: finds the network (if not found yet), sweeps every host,
  /// resolves names, probes ports, and checks the Linux tools. Cancellable,
  /// and flags devices never seen before as NEW.
  Future<void> _startScan() async {
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _cancelScan = false;
      _scanNote = '';
      _hosts = [];
      _newMacs = {};
    });
    var network = _network;
    network ??= await AutoScanner().detectLocalNetwork();
    if (!mounted) return;
    if (network == null) {
      setState(() {
        _scanning = false;
        _scanNote =
            'No WiFi network found. Connect to your WiFi first, then scan again.';
      });
      return;
    }
    setState(() {
      _network = network;
      _gatewayCtrl.text = network!.gatewayIp ?? _gatewayCtrl.text;
    });
    final scanner = AutoScanner();
    final hosts = await scanner.scan(
      network,
      onProgress: (done, total, phase) {
        if (!mounted) return;
        setState(() {
          _scanProgress = total == 0 ? 0 : done / total;
          _scanPhase = phase;
        });
      },
      isCancelled: () => _cancelScan,
    );
    if (!mounted) return;
    // New-device check BEFORE recording this scan, or nothing is ever new.
    final fresh = _scanHistory.newMacs(hosts);
    await _scanHistory.recordScan(hosts);
    final risky = hosts.where((h) => h.looksRisky).length;
    setState(() {
      _hosts = hosts;
      _newMacs = fresh;
      _scanning = false;
      _scanPhase = '';
      _scanNote = hosts.isEmpty
          ? 'No devices found. On this device the scan may need local-network permission — try the router DHCP list instead.'
          : 'Found ${hosts.length} device(s) on ${network!.networkAddress}/${network.prefix}'
              '${fresh.isNotEmpty ? ' • ${fresh.length} NEW' : ''}'
              '${risky > 0 ? ' • $risky need a check' : ''}'
              '${_cancelScan ? ' (cancelled)' : ''}.';
    });
    await _autoDetectRouter();
    await _detectTools();
  }

  Future<void> _detectTools() async {
    final tools = await detectTools();
    if (!mounted) return;
    setState(() {
      _tools = tools;
      _toolsChecked = true;
    });
  }

  /// Run nmap's ping scan on our own subnet (desktop only) and merge any
  /// hosts it finds that the built-in scan missed. Real errors are shown
  /// (not a silent empty list) with the install command when nmap is missing.
  Future<void> _runNmapScan() async {
    final network = _network;
    if (network == null || _toolsBusy) return;
    final cidr = '${network.networkAddress}/${network.prefix}';
    setState(() {
      _toolsBusy = true;
      _toolsNote = 'Running ${nmapPingScanCommand(cidr)} …';
    });
    final result = await runNmapPingScanDetailed(cidr);
    if (!mounted) return;
    if (result.error != null) {
      setState(() {
        _toolsBusy = false;
        _toolsNote = '${result.error} ${installCommandFor('nmap') ?? ''}';
      });
      return;
    }
    final ips = result.data ?? const [];
    final known = _hosts.map((h) => h.ip).toSet();
    final extra = ips.where((ip) => !known.contains(ip)).map(
          (ip) => ScannedHost(
            ip: ip,
            isGateway: ip == network.gatewayIp,
            isSelf: ip == network.localIp,
          ),
        );
    setState(() {
      _hosts = mergeHosts(_hosts, extra.toList());
      _toolsBusy = false;
      _toolsNote = ips.isEmpty
          ? 'nmap found no live hosts on $cidr.'
          : 'nmap found ${ips.length} live host(s).';
    });
  }

  /// Run arp-scan on the local network (desktop only) and merge results.
  Future<void> _runArpScan() async {
    if (_toolsBusy) return;
    setState(() {
      _toolsBusy = true;
      _toolsNote = 'Running ${arpScanCommand()} …';
    });
    final result = await runArpScanDetailed();
    if (!mounted) return;
    if (result.error != null) {
      setState(() {
        _toolsBusy = false;
        _toolsNote = '${result.error} ${installCommandFor('arp-scan') ?? ''}';
      });
      return;
    }
    final rows = result.data ?? const [];
    final extra = rows.map((row) {
      final (ip, mac, vendor) = row;
      final existing = _hosts.where((h) => h.ip == ip).firstOrNull;
      return ScannedHost(
        ip: ip,
        mac: mac,
        hostname: existing?.hostname,
        vendor: vendor.isEmpty ? existing?.vendor : vendor,
        isGateway: existing?.isGateway ?? ip == _network?.gatewayIp,
        isSelf: existing?.isSelf ?? ip == _network?.localIp,
        openPorts: existing?.openPorts ?? const [],
        pingMs: existing?.pingMs,
      );
    }).toList();
    setState(() {
      _hosts = mergeHosts(_hosts, extra);
      _toolsBusy = false;
      _toolsNote = rows.isEmpty
          ? 'arp-scan found nothing.'
          : 'arp-scan found ${rows.length} device(s).';
    });
  }

  /// Deep scan: nmap -sV on every found host (desktop only) — service
  /// names AND versions, merged into the host cards.
  Future<void> _runDeepScan() async {
    if (_hosts.isEmpty || _toolsBusy) return;
    setState(() {
      _toolsBusy = true;
      _toolsNote = 'Running nmap -sV on ${_hosts.length} host(s)…';
    });
    final extra = <ScannedHost>[];
    String? error;
    for (var i = 0; i < _hosts.length; i += 4) {
      final batch = _hosts.skip(i).take(4).map((h) async {
        final result = await runNmapServiceScanDetailed(h.ip);
        if (result.error != null) {
          error ??= result.error;
          return null;
        }
        final ports = (result.data ?? const [])
            .map(
              (p) => OpenPort(
                port: p.port,
                service: p.service,
                banner: p.version.isEmpty ? null : p.version,
              ),
            )
            .toList();
        return ScannedHost(
          ip: h.ip,
          mac: h.mac,
          hostname: h.hostname,
          vendor: h.vendor,
          isGateway: h.isGateway,
          isSelf: h.isSelf,
          openPorts: ports,
          pingMs: h.pingMs,
        );
      });
      final done = await Future.wait(batch);
      extra.addAll(done.whereType<ScannedHost>());
      if (!mounted) return;
      setState(() {
        _toolsNote =
            'Deep scan… ${extra.length}/${_hosts.length} host(s) done.';
      });
    }
    if (!mounted) return;
    setState(() {
      _hosts = mergeHosts(_hosts, extra);
      _toolsBusy = false;
      _toolsNote = error != null
          ? 'Deep scan: $error ${installCommandFor('nmap') ?? ''}'
          : 'Deep scan done — service versions are on the host cards.';
    });
  }

  /// iperf3 speed test to a server the user types in (e.g. a PC on the
  /// same LAN running `iperf3 -s`). Desktop only.
  Future<void> _runIperf3() async {
    final server = _iperfServerCtrl.text.trim();
    if (server.isEmpty || _toolsBusy) return;
    setState(() {
      _toolsBusy = true;
      _toolsNote = 'Running ${iperf3Command(server)} …';
    });
    final result = await runIperf3(server);
    if (!mounted) return;
    setState(() {
      _toolsBusy = false;
      _toolsNote = result.error != null
          ? 'iperf3: ${result.error} ${installCommandFor('iperf3') ?? ''}'
          : 'Speed to $server: ${result.data!.sentMbps.toStringAsFixed(1)} Mbps up / ${result.data!.receivedMbps.toStringAsFixed(1)} Mbps down.';
    });
  }

  /// nmcli WiFi scan + iw link info (Linux only) — the networks your own
  /// card can see, same list any WiFi picker shows.
  Future<void> _runNmcliScan() async {
    if (_toolsBusy) return;
    setState(() {
      _toolsBusy = true;
      _toolsNote = 'Running ${nmcliWifiScanCommand()} …';
    });
    final result = await runNmcliWifiScan();
    if (!mounted) return;
    if (result.error != null) {
      setState(() {
        _toolsBusy = false;
        _toolsNote = 'nmcli: ${result.error} ${installCommandFor('nmcli') ?? ''}';
      });
      return;
    }
    final rows = result.data ?? const [];
    final iw = await runIwDev();
    setState(() {
      _toolsBusy = false;
      _toolsNote = rows.isEmpty
          ? 'No WiFi networks found.'
          : 'WiFi networks nearby:\n${rows.map((r) => '• ${r.ssid} — ${r.signal}% — ${r.security}').join('\n')}'
              '${iw.data != null ? '\nLink: ${iw.data}' : ''}';
    });
  }

  /// tshark protocol summary on one interface (Linux only, bounded).
  Future<void> _runTshark() async {
    final iface =
        _tsharkIfaceCtrl.text.trim().isEmpty ? null : _tsharkIfaceCtrl.text.trim();
    if (iface == null || _toolsBusy) return;
    setState(() {
      _toolsBusy = true;
      _toolsNote = 'Capturing on $iface for 10s (protocol summary only)…';
    });
    final result = await runTsharkProtocolSummary(
      interfaceName: iface,
      seconds: 10,
    );
    if (!mounted) return;
    setState(() {
      _toolsBusy = false;
      _toolsNote = result.error != null
          ? 'tshark: ${result.error} ${installCommandFor('tshark') ?? ''}'
          : 'Traffic on $iface (10s):\n${(result.data ?? const []).take(8).map((p) => '• ${p.protocol}: ${p.frames} frames, ${p.bytes} bytes').join('\n')}';
    });
  }

  /// TP-Link: login + device list + QoS probe, step by step, so the user
  /// sees exactly what their router supports.
  Future<void> _testTplink() async {
    if (_probingTplink) return;
    setState(() {
      _probingTplink = true;
      _limitNote = 'Testing the TP-Link connection…';
    });
    final probe = await TpLinkAdapter().testConnection(
      gatewayIp: _gatewayCtrl.text.trim(),
      credentials: RouterCredentials(
        username: _routerUserCtrl.text.trim(),
        password: _routerPassCtrl.text,
      ),
    );
    if (!mounted) return;
    setState(() {
      _tplinkProbe = probe;
      _probingTplink = false;
      _limitNote = probe.message;
    });
    _routerPassCtrl.clear();
  }

  /// OpenWrt: read the router's SSH host-key fingerprint so the user can
  /// confirm it before the first limit is applied over SSH.
  Future<void> _probeSsh() async {
    if (_probingSsh) return;
    setState(() {
      _probingSsh = true;
      _sshNote = 'Reading the router SSH fingerprint…';
    });
    final fp = await OpenWrtAdapter().probeSshFingerprint(
      gatewayIp: _gatewayCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() {
      _probingSsh = false;
      if (fp == null) {
        _sshNote =
            'Could not read the SSH fingerprint. Is SSH enabled on the OpenWrt router (port 22)?';
      } else {
        _sshFingerprint = fp;
        _sshFingerprintConfirmed = false;
        _sshNote =
            'Router SSH fingerprint: $fp — check it matches the router, then confirm below.';
      }
    });
  }

  Future<void> _applyLimit() async {
    final device = _selectedDevice;
    if (device == null) return;
    final result = await _limiter.applyRule(
      rule: LimitRule(
        deviceMac: device.mac,
        deviceIp: device.ip,
        deviceLabel: device.hostname ?? device.ip,
        downMbps: _downMbps,
        upMbps: _upMbps,
      ),
      gatewayIp: _gatewayCtrl.text.trim(),
      credentials: RouterCredentials(
        username: _routerUserCtrl.text.trim(),
        password: _routerPassCtrl.text,
      ),
      expectedFingerprint:
          _adapter.profileId == 'openwrt' && _sshFingerprintConfirmed
              ? _sshFingerprint
              : null,
    );
    if (!mounted) return;
    setState(() => _limitNote = result.message);
    _routerPassCtrl.clear();
  }

  /// Re-check a saved rule against the router right now.
  Future<void> _verifySavedRule(LimitRule rule) async {
    final result = await _limiter.verifyRule(
      deviceMac: rule.deviceMac,
      deviceIp: rule.deviceIp,
      gatewayIp: _gatewayCtrl.text.trim(),
      credentials: RouterCredentials(
        username: _routerUserCtrl.text.trim(),
        password: _routerPassCtrl.text,
      ),
      expectedFingerprint:
          _adapter.profileId == 'openwrt' && _sshFingerprintConfirmed
              ? _sshFingerprint
              : null,
    );
    if (!mounted) return;
    setState(() => _limitNote = result.message);
    _routerPassCtrl.clear();
  }

  /// Remove a saved rule (and clear it on the router where supported).
  Future<void> _removeSavedRule(LimitRule rule) async {
    final result = await _limiter.removeRule(
      deviceMac: rule.deviceMac,
      gatewayIp: _gatewayCtrl.text.trim(),
      credentials: RouterCredentials(
        username: _routerUserCtrl.text.trim(),
        password: _routerPassCtrl.text,
      ),
      expectedFingerprint:
          _adapter.profileId == 'openwrt' && _sshFingerprintConfirmed
              ? _sshFingerprint
              : null,
    );
    if (!mounted) return;
    setState(() => _limitNote = result.message);
    _routerPassCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'WiHisar — وائی حصار',
          style: CyberpunkTheme.display,
        ),
        actions: [
          if (_updateResult?.updateAvailable == true)
            IconButton(
              icon: const Icon(Icons.system_update),
              color: CyberpunkTheme.neonLime,
              tooltip: 'Update available — v${_updateResult!.info!.latestVersion}',
              onPressed: _openUpdate,
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Check for updates',
            onPressed: () => _checkForUpdate(),
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'About',
            onPressed: () => showDialog<void>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('WiHisar v$kAppVersion'),
                content: const Text(
                  'Own-WiFi security tester and bandwidth limiter (educational).\n\n'
                  '• Tests ONLY your own WiFi.\n'
                  '• No password cracking, no handshake capture.\n'
                  '• Your password is analysed locally and never stored or sent.\n'
                  '• On iOS, WiFi scanning is blocked by Apple — use the router-login path.\n'
                  '• If your router has no limiter API, WiHisar says so instead of faking a limit.\n\n'
                  'Updates: the app checks GitHub Releases on startup. '
                  'When a new version is out, a banner appears at the top — '
                  'tap it and the app downloads and installs the update '
                  'itself (Android: system installer opens; Windows: the '
                  'app restarts on the new version). Nothing downloads '
                  'without you tapping.',
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(c).pop();
                      _checkForUpdate();
                    },
                    child: const Text('Check for updates'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(c).pop(),
                    child: const Text('OK'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_updateResult?.updateAvailable == true)
            InkWell(
              onTap: _openUpdate,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                color: CyberpunkTheme.neonLime.withValues(alpha: 0.15),
                child: Row(
                  children: [
                    const Icon(
                      Icons.system_update,
                      color: CyberpunkTheme.neonLime,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Update available: v${_updateResult!.info!.latestVersion} — tap to download & install in the app',
                        style: const TextStyle(
                          color: CyberpunkTheme.neonLime,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_downloading || _downloadNote.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 10,
              ),
              color: CyberpunkTheme.surfaceRaised,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_downloading)
                    LinearProgressIndicator(value: _downloadProgress),
                  if (_downloading) const SizedBox(height: 6),
                  Text(_downloadNote),
                ],
              ),
            ),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: [
                _testTab(),
                _devicesTab(),
                _limitsTab(),
                _roadmapTab(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.shield_outlined), label: 'Test'),
          NavigationDestination(icon: Icon(Icons.devices), label: 'Devices'),
          NavigationDestination(icon: Icon(Icons.speed), label: 'Limits'),
          NavigationDestination(icon: Icon(Icons.rocket_launch), label: 'Roadmap'),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- Roadmap tab
  Widget _roadmapTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const CyberHeading('Coming soon'),
        const SizedBox(height: 8),
        Text(
          'WiHisar v$kAppVersion — next up is $nextVersion. '
          'Every feature below has a version number: it ships in that '
          'version, and the in-app updater will offer it here when it lands.',
          style: const TextStyle(color: CyberpunkTheme.textMuted),
        ),
        const SizedBox(height: 16),
        for (final item in kRoadmap) ...[
          CyberCard(
            accent: item.status == RoadmapStatus.shipped ||
                    item.status == RoadmapStatus.nextUp
                ? CyberpunkTheme.neonLime
                : CyberpunkTheme.neonMagenta,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CyberChip(
                      item.version,
                      accent: CyberpunkTheme.neonCyan,
                    ),
                    const SizedBox(width: 8),
                    CyberChip(
                      item.status == RoadmapStatus.shipped
                          ? 'SHIPPED'
                          : item.status == RoadmapStatus.nextUp
                              ? 'NEXT UP'
                              : item.status == RoadmapStatus.planned
                                  ? 'PLANNED'
                                  : 'IDEA',
                      accent: item.status == RoadmapStatus.shipped ||
                              item.status == RoadmapStatus.nextUp
                          ? CyberpunkTheme.neonLime
                          : CyberpunkTheme.neonMagenta,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  item.title,
                  style: CyberpunkTheme.display.copyWith(fontSize: 16),
                ),
                const SizedBox(height: 4),
                Text(item.summary),
                const SizedBox(height: 8),
                for (final f in item.features)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text('▸ $f'),
                  ),
                const SizedBox(height: 8),
                Text(
                  item.platforms,
                  style: const TextStyle(
                    color: CyberpunkTheme.textMuted,
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
                if (item.honestNote != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    item.honestNote!,
                    style: const TextStyle(
                      color: CyberpunkTheme.warnAmber,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        CyberCard(
          accent: CyberpunkTheme.neonCyan,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'How updates work',
                style: CyberpunkTheme.display,
              ),
              const SizedBox(height: 6),
              const Text(
                'Every WiHisar update bumps the version (v0.3.0 → v0.4.0 …) '
                'and ships as a GitHub release. The app checks on startup; '
                'when a new version is out, a banner appears at the top — '
                'tap it and the app downloads and installs the update '
                'itself. No manual download, no browser. On iOS the '
                'release page opens instead (Apple does not allow '
                'in-app sideload installs).',
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => _checkForUpdate(),
                icon: const Icon(Icons.refresh),
                label: Text(
                  _checkingUpdate
                      ? 'Checking…'
                      : 'Check for updates now',
                ),
              ),
              if (_updateResult?.updateAvailable == true) ...[
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _downloading ? null : _openUpdate,
                  icon: const Icon(Icons.system_update),
                  label: Text(
                    _downloading
                        ? 'Downloading… ${(_downloadProgress * 100).toStringAsFixed(0)}%'
                        : 'Download & install v${_updateResult!.info!.latestVersion}',
                  ),
                ),
              ],
              if (_updateResult != null) ...[
                const SizedBox(height: 8),
                Text(
                  _updateResult!.error ??
                      (_updateResult!.updateAvailable
                          ? 'v${_updateResult!.info!.latestVersion} is available — tap the button above to download & install it in the app.'
                          : 'You are on the latest version (v$kAppVersion).'),
                  style: const TextStyle(
                    color: CyberpunkTheme.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- Test tab
  Widget _testTab() {
    final report = _report;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const CyberHeading('Test your own WiFi'),
        const SizedBox(height: 8),
        const Text(
          'Educational check of the network you own. Type your own WiFi password — it is analysed on this device only and never stored or sent anywhere.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _ssidCtrl,
          decoration: const InputDecoration(
            labelText: 'WiFi name (SSID) — your own network',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<SecurityType>(
          initialValue: _security,
          decoration: const InputDecoration(
            labelText: 'Security type',
            border: OutlineInputBorder(),
          ),
          items: SecurityType.values
              .map((t) => DropdownMenuItem(value: t, child: Text(t.label)))
              .toList(),
          onChanged: (v) => setState(() => _security = v ?? SecurityType.wpa2),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          title: const Text('WPS is turned on'),
          subtitle: const Text('WPS PIN can be brute-forced in hours.'),
          value: _wps,
          onChanged: (v) => setState(() => _wps = v),
        ),
        TextField(
          controller: _passwordCtrl,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Your own WiFi password (never stored)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _runTest,
          icon: const Icon(Icons.shield),
          label: const Text('Check my WiFi'),
        ),
        if (report != null) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Score ${report.score}/100 — Grade ${report.grade}',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(report.verdict),
                  const Divider(),
                  Text('Network: ${report.ssid}'),
                  Text('Security: ${report.securityType.label}'),
                  Text('WPS: ${report.wpsEnabled ? 'ON — turn it off' : 'Off'}'),
                  Text(
                      'Password entropy: ${report.passwordAnalysis.entropyBits.toStringAsFixed(1)} bits (${report.passwordAnalysis.strengthLabel})'),
                  const SizedBox(height: 8),
                  Text(report.crackTimeSummary()),
                  const Divider(),
                  const Text('How to fix it:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  for (final fix in report.fixes)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('• $fix'),
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ------------------------------------------------------------- Devices tab
  Widget _devicesTab() {
    final detection = _detection;
    final network = _network;
    final isDesktop =
        Platform.isLinux || Platform.isWindows || Platform.isMacOS;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const CyberHeading('Scan my network'),
        const SizedBox(height: 8),
        const Text(
          'One tap — WiHisar finds your network itself (no gateway or SSID to type), sweeps every address, resolves names and checks open ports.',
        ),
        const SizedBox(height: 16),
        CyberCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                network == null
                    ? 'Network: not detected yet — tap Scan below.'
                    : 'Network: ${network.networkAddress}/${network.prefix}',
                style: CyberpunkTheme.display,
              ),
              const SizedBox(height: 4),
              Text('This device: ${network?.localIp ?? '—'}'),
              Text('Gateway: ${network?.gatewayLabel ?? _gatewayCtrl.text}'),
              if (network?.ssid != null) Text('WiFi: ${network!.ssid}'),
              if (network?.interfaceName != null)
                Text('Interface: ${network!.interfaceName}'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _scanning ? null : _startScan,
                icon: const Icon(Icons.radar),
                label: Text(_scanning ? 'Scanning…' : 'Scan my network'),
              ),
            ),
            if (_scanning) ...[
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => setState(() => _cancelScan = true),
                icon: const Icon(Icons.cancel),
                label: const Text('Cancel'),
              ),
            ],
          ],
        ),
        if (_scanning) ...[
          const SizedBox(height: 12),
          LinearProgressIndicator(value: _scanProgress),
          const SizedBox(height: 6),
          Text(_scanPhase),
        ],
        if (_scanNote.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(_scanNote),
        ],
        const SizedBox(height: 8),
        for (final h in _hosts)
          Card(
            child: ListTile(
              leading: Icon(
                h.isGateway
                    ? Icons.router
                    : h.isSelf
                        ? Icons.smartphone
                        : Icons.devices_other,
                color: h.looksRisky
                    ? CyberpunkTheme.warnAmber
                    : CyberpunkTheme.neonCyan,
              ),
              title: Text(
                '${h.displayName}${h.isGateway ? '  [ROUTER]' : ''}${h.isSelf ? '  [THIS DEVICE]' : ''}${h.looksRisky ? '  [CHECK]' : ''}${_newMacs.contains((h.mac ?? '').toUpperCase()) ? '  [NEW]' : ''}',
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${guessDeviceKind(h)} • ${h.ip}${h.mac != null && h.mac!.isNotEmpty ? ' • ${h.mac}' : ''}${h.pingMs != null ? ' • ${h.pingMs}ms' : ''}',
                  ),
                  if (h.openPorts.isNotEmpty)
                    Text(
                      'Open: ${h.openPorts.map((p) => '${p.port} (${p.service})${p.banner != null ? ' ${p.banner}' : ''}').join(', ')}',
                      style: const TextStyle(
                        color: CyberpunkTheme.warnAmber,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
              isThreeLine: h.openPorts.isNotEmpty,
              onTap: () => setState(() {
                _selectedDevice = ConnectedDevice(
                  ip: h.ip,
                  mac: h.mac ?? '',
                  hostname: h.hostname,
                  vendor: h.vendor,
                  isGateway: h.isGateway,
                );
                _tab = 2;
              }),
            ),
          ),
        if (_hosts.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Text(
            'Tap a device to set its limit on the Limits tab. '
            '[NEW] means this device was never seen on your network before. '
            '[CHECK] means Telnet/FTP/RDP/VNC is open on that device — worth a look.',
            style: TextStyle(color: CyberpunkTheme.textMuted),
          ),
        ],
        const SizedBox(height: 24),
        const CyberHeading('Linux tools'),
        const SizedBox(height: 8),
        Text(
          isDesktop
              ? 'Tools found on this computer. Commands run only on your own network, and the exact command is shown before it runs. Missing tools show their install command.'
              : 'These tools live on the Linux / desktop build. On this phone they are not installed — use the Windows or Linux build for nmap, arp-scan, iperf3 and tshark.',
        ),
        const SizedBox(height: 12),
        if (!_toolsChecked)
          FilledButton.icon(
            onPressed: _detectTools,
            icon: const Icon(Icons.terminal),
            label: const Text('Detect installed tools'),
          )
        else ...[
          for (final tool in _tools)
            Card(
              child: ListTile(
                leading: Icon(
                  tool.available ? Icons.check_circle : Icons.cancel,
                  color: tool.available
                      ? CyberpunkTheme.neonLime
                      : CyberpunkTheme.textMuted,
                ),
                title: Text(tool.displayName),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tool.whatItDoes),
                    if (tool.version != null)
                      Text(
                        tool.version!,
                        style: const TextStyle(
                          color: CyberpunkTheme.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    if (!tool.available &&
                        installCommandFor(tool.command) != null)
                      Text(
                        'Install: ${installCommandFor(tool.command)}',
                        style: const TextStyle(
                          color: CyberpunkTheme.neonCyan,
                          fontSize: 12,
                        ),
                      ),
                    if (tool.crackingNote != null)
                      Text(
                        tool.crackingNote!,
                        style: const TextStyle(
                          color: CyberpunkTheme.warnAmber,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
                isThreeLine: true,
              ),
            ),
          if (isDesktop) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed:
                  (_network == null || _toolsBusy) ? null : _runNmapScan,
              icon: const Icon(Icons.radar),
              label: Text(
                'Run nmap ping scan (${network == null ? '…' : '${network.networkAddress}/${network.prefix}'})',
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _toolsBusy ? null : _runArpScan,
              icon: const Icon(Icons.hub),
              label: const Text('Run arp-scan --localnet'),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: (_hosts.isEmpty || _toolsBusy) ? null : _runDeepScan,
              icon: const Icon(Icons.search),
              label: const Text('Deep scan all hosts (nmap -sV)'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _iperfServerCtrl,
              decoration: const InputDecoration(
                labelText: 'iperf3 server (e.g. 192.168.1.10, running iperf3 -s)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _toolsBusy ? null : _runIperf3,
              icon: const Icon(Icons.speed),
              label: const Text('Test speed to server (iperf3)'),
            ),
            if (Platform.isLinux) ...[
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _toolsBusy ? null : _runNmcliScan,
                icon: const Icon(Icons.wifi),
                label: const Text('Scan nearby WiFi (nmcli)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _tsharkIfaceCtrl,
                decoration: InputDecoration(
                  labelText: 'tshark interface (e.g. ${network?.interfaceName ?? 'wlan0'})',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _toolsBusy ? null : _runTshark,
                icon: const Icon(Icons.analytics),
                label: const Text('Traffic summary, 10s (tshark)'),
              ),
            ],
            if (_toolsNote.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(_toolsNote),
            ],
          ],
        ],
        const SizedBox(height: 24),
        const CyberHeading('Router detect'),
        const SizedBox(height: 8),
        const Text(
          'Automatic: after the network is found, WiHisar reads the router admin page (title + Server header) and detects the vendor itself. The fields below are only an override if auto-detect gets it wrong.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _gatewayCtrl,
          decoration: const InputDecoration(
            labelText: 'Gateway IP (auto-filled)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _titleCtrl,
          decoration: const InputDecoration(
            labelText: 'Admin page title (optional, e.g. V-SOL GPON ONU)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _serverCtrl,
          decoration: const InputDecoration(
            labelText: 'HTTP Server header (optional)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _detectRouter,
          icon: const Icon(Icons.radar),
          label: const Text('Detect router'),
        ),
        if (detection != null) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${detection.profile.displayName} — ${detection.confidence}% (${detection.confidenceLabel})',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text('Gateway: ${detection.gatewayIp}'),
                  if (detection.gatewayVendor != null)
                    Text('MAC vendor: ${detection.gatewayVendor}'),
                  if (detection.profile.loginNote != null)
                    Text('Login: ${detection.profile.loginNote}'),
                  Text('Limit support: ${detection.profile.limitNote}'),
                  const Divider(),
                  for (final e in detection.evidence)
                    Text('• ${e.source}: ${e.detail} (+${e.points})'),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  // -------------------------------------------------------------- Limits tab
  Widget _limitsTab() {
    final adapter = _adapter;
    final device = _selectedDevice;
    final savedRules = _limiter.rules;
    final isTplink = _detection?.profile.id == 'tplink';
    final isOpenWrt = _detection?.profile.id == 'openwrt';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const CyberHeading('Bandwidth limits'),
        const SizedBox(height: 8),
        Text(
          'Router: ${_detection?.profile.displayName ?? 'Not detected yet — detect it on the Devices tab.'}',
        ),
        Text('Method: ${adapter.limitMethodDescription}'),
        if (!adapter.supportsBandwidthLimit) ...[
          const SizedBox(height: 8),
          Card(
            color: Colors.amber.shade50,
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'This router does not support app-controlled limiting. '
                'WiHisar will not fake a limit. Fallback: OpenWrt router with SQM, or a separate SSID.',
              ),
            ),
          ),
        ],
        if (isTplink) ...[
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _probingTplink ? null : _testTplink,
            icon: const Icon(Icons.network_check),
            label: Text(
              _probingTplink ? 'Testing…' : 'Test TP-Link connection',
            ),
          ),
          if (_tplinkProbe != null) ...[
            const SizedBox(height: 8),
            Text(
              'Login: ${_tplinkProbe!.loginOk ? 'OK' : 'FAILED'} • '
              'Devices on router: ${_tplinkProbe!.deviceCount} • '
              'QoS: ${_tplinkProbe!.qosOk ? 'supported' : 'not confirmed'}',
            ),
          ],
        ],
        if (isOpenWrt) ...[
          const SizedBox(height: 16),
          const Text(
            'OpenWrt limits are applied over SSH as root. First probe the router fingerprint, check it, then confirm — the app never applies to an unverified SSH key.',
            style: TextStyle(color: CyberpunkTheme.textMuted),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _probingSsh ? null : _probeSsh,
            icon: const Icon(Icons.key),
            label: Text(
              _probingSsh ? 'Reading…' : 'Probe SSH fingerprint',
            ),
          ),
          if (_sshNote.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(_sshNote),
          ],
          if (_sshFingerprint != null && !_sshFingerprintConfirmed) ...[
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () => setState(() {
                _sshFingerprintConfirmed = true;
                _sshNote =
                    'Fingerprint confirmed — limits will now apply over SSH.';
              }),
              icon: const Icon(Icons.verified),
              label: const Text('Confirm this fingerprint'),
            ),
          ],
          if (device != null) ...[
            const SizedBox(height: 12),
            const Text(
              'Commands that will run on the router:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              OpenWrtAdapter.htbCommandsFor(
                deviceIp: device.ip,
                downMbps: _downMbps,
                upMbps: _upMbps,
              ).join('\n'),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ],
        if (savedRules.isNotEmpty) ...[
          const SizedBox(height: 24),
          const CyberHeading('Saved limits'),
          const SizedBox(height: 8),
          for (final rule in savedRules)
            Card(
              child: ListTile(
                leading: Icon(
                  _limiter.isApplied(rule.deviceMac)
                      ? Icons.check_circle
                      : Icons.error_outline,
                  color: _limiter.isApplied(rule.deviceMac)
                      ? CyberpunkTheme.neonLime
                      : CyberpunkTheme.warnAmber,
                ),
                title: Text(
                  '${rule.deviceLabel} — ${rule.downMbps.toStringAsFixed(1)} down / ${rule.upMbps.toStringAsFixed(1)} up Mbps',
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${rule.deviceIp} • ${rule.deviceMac}'),
                    Text(
                      _limiter.isApplied(rule.deviceMac)
                          ? 'Applied'
                          : 'Wanted, not applied',
                    ),
                    if (_limiter.messageFor(rule.deviceMac) != null)
                      Text(
                        _limiter.messageFor(rule.deviceMac)!,
                        style: const TextStyle(
                          color: CyberpunkTheme.textMuted,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
                isThreeLine: true,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.verified),
                      tooltip: 'Verify on the router now',
                      onPressed: () => _verifySavedRule(rule),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete),
                      tooltip: 'Remove limit',
                      onPressed: () => _removeSavedRule(rule),
                    ),
                  ],
                ),
              ),
            ),
        ],
        const SizedBox(height: 16),
        if (device == null)
          const Text('No device selected — pick one on the Devices tab.')
        else ...[
          Text('Device: ${device.hostname ?? device.ip} (${device.mac})'),
          const SizedBox(height: 16),
          Text('Download limit: ${_downMbps.toStringAsFixed(1)} Mbps'),
          Slider(
            value: _downMbps,
            min: 0.5,
            max: 50,
            divisions: 99,
            label: '${_downMbps.toStringAsFixed(1)} Mbps',
            onChanged: (v) => setState(() => _downMbps = v),
          ),
          Text('Upload limit: ${_upMbps.toStringAsFixed(1)} Mbps'),
          Slider(
            value: _upMbps,
            min: 0.5,
            max: 20,
            divisions: 39,
            label: '${_upMbps.toStringAsFixed(1)} Mbps',
            onChanged: (v) => setState(() => _upMbps = v),
          ),
          TextField(
            controller: _routerUserCtrl,
            decoration: const InputDecoration(
              labelText: 'Router admin username (your own router)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _routerPassCtrl,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Router admin password (never stored)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _applyLimit,
            icon: const Icon(Icons.speed),
            label: const Text('Apply limit'),
          ),
        ],
        if (_limitNote.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(_limitNote),
        ],
        const SizedBox(height: 16),
        const Text(
          'Limits are enforced by the router, not by this phone. '
          'A phone app alone cannot throttle other devices on the WiFi.',
          style: TextStyle(color: Colors.grey),
        ),
        // Keep the wifi_info seam referenced so the iOS limitation is part
        // of the shipped code, not just the README.
        const SizedBox(height: 8),
        Text(
          'iOS note: ${ManualWifiInfoService().scanLimitationNote}',
          style: const TextStyle(color: Colors.grey),
        ),
      ],
    );
  }
}
