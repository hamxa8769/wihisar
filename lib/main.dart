// ignore_for_file: deprecated_member_use
/// WiHisar v0.3.0 — own-WiFi security tester + bandwidth limiter.
///
/// Educational, own-router only. No password cracking of any kind: the
/// security test estimates the strength of a password the user types in
/// for THEIR OWN network, locally, and never stores or sends it.
///
/// v0.3.0: auto scanner (no manual gateway/SSID entry — the app finds
/// your network itself) + Linux tools layer (nmap, arp-scan, iw, nmcli,
/// iperf3; aircrack-ng detected only, cracking NOT built).
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
import 'router/router_adapter.dart';
import 'router/router_detect.dart';
import 'scan/auto_scan.dart';
import 'scan/host.dart';
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
  RouterDetection? _detection;
  LocalNetwork? _network;
  List<ScannedHost> _hosts = [];
  bool _scanning = false;
  double _scanProgress = 0;
  String _scanPhase = '';
  String _scanNote = '';
  List<LinuxTool> _tools = [];
  bool _toolsChecked = false;
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
    });
  }

  /// Find the network this device is on — no manual entry. Fills the SSID
  /// (Test tab) and gateway (Devices tab) automatically. Best effort: if
  /// the OS will not tell us, the fields stay editable by hand.
  Future<void> _detectNetwork() async {
    String? ssid;
    try {
      ssid = await NetworkInfo().getWifiName();
      if (ssid != null) ssid = ssid.replaceAll('"', '').trim();
    } catch (_) {
      // SSID unavailable on this device — user can type it.
    }
    final network = await AutoScanner().detectLocalNetwork(
      ssidOverride: ssid,
    );
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
  }

  /// One-tap scan: finds the network (if not found yet), sweeps every host,
  /// resolves names, probes ports, and checks the Linux tools.
  Future<void> _startScan() async {
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _scanNote = '';
      _hosts = [];
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
    );
    if (!mounted) return;
    setState(() {
      _hosts = hosts;
      _scanning = false;
      _scanPhase = '';
      _scanNote = hosts.isEmpty
          ? 'No devices found. On this device the scan may need local-network permission — try the router DHCP list instead.'
          : 'Found ${hosts.length} device(s) on ${network!.networkAddress}/${network.prefix}.';
    });
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
  /// hosts it finds that the built-in scan missed.
  Future<void> _runNmapScan() async {
    final network = _network;
    if (network == null) return;
    setState(() => _toolsNote = 'Running ${nmapPingScanCommand('${network.networkAddress}/${network.prefix}')} …');
    final ips = await runNmapPingScan('${network.networkAddress}/${network.prefix}');
    if (!mounted) return;
    final known = _hosts.map((h) => h.ip).toSet();
    final extra = ips.where((ip) => !known.contains(ip)).map(
          (ip) => ScannedHost(
            ip: ip,
            isGateway: ip == network.gatewayIp,
            isSelf: ip == network.localIp,
          ),
        );
    setState(() {
      _hosts = [..._hosts, ...extra]
        ..sort((a, b) => a.ip.compareTo(b.ip));
      _toolsNote = ips.isEmpty
          ? 'nmap found no live hosts (is nmap installed?).'
          : 'nmap found ${ips.length} live host(s).';
    });
  }

  /// Run arp-scan on the local network (desktop only) and merge results.
  Future<void> _runArpScan() async {
    setState(() => _toolsNote = 'Running ${arpScanCommand()} …');
    final rows = await runArpScan();
    if (!mounted) return;
    final byIp = {for (final h in _hosts) h.ip: h};
    for (final (ip, mac, vendor) in rows) {
      final existing = byIp[ip];
      byIp[ip] = ScannedHost(
        ip: ip,
        mac: mac,
        hostname: existing?.hostname,
        vendor: vendor.isEmpty ? existing?.vendor : vendor,
        isGateway: existing?.isGateway ?? ip == _network?.gatewayIp,
        isSelf: existing?.isSelf ?? ip == _network?.localIp,
        openPorts: existing?.openPorts ?? const [],
        pingMs: existing?.pingMs,
      );
    }
    final merged = byIp.values.toList()
      ..sort((a, b) => a.ip.compareTo(b.ip));
    setState(() {
      _hosts = merged;
      _toolsNote = rows.isEmpty
          ? 'arp-scan found nothing (needs root on Linux, or is not installed).'
          : 'arp-scan found ${rows.length} device(s).';
    });
  }

  Future<void> _applyLimit() async {
    final device = _selectedDevice;
    if (device == null) return;
    final service = LimiterService(_adapter);
    final result = await service.applyRule(
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
    );
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
        FilledButton.icon(
          onPressed: _scanning ? null : _startScan,
          icon: const Icon(Icons.radar),
          label: Text(_scanning ? 'Scanning…' : 'Scan my network'),
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
                '${h.displayName}${h.isGateway ? '  [ROUTER]' : ''}${h.isSelf ? '  [THIS DEVICE]' : ''}${h.looksRisky ? '  [CHECK]' : ''}',
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${h.ip}${h.mac != null && h.mac!.isNotEmpty ? ' • ${h.mac}' : ''}${h.pingMs != null ? ' • ${h.pingMs}ms' : ''}',
                  ),
                  if (h.openPorts.isNotEmpty)
                    Text(
                      'Open: ${h.openPorts.map((p) => '${p.port} (${p.service})').join(', ')}',
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
            '[CHECK] means Telnet/FTP is open on that device — worth a look.',
            style: TextStyle(color: CyberpunkTheme.textMuted),
          ),
        ],
        const SizedBox(height: 24),
        const CyberHeading('Linux tools'),
        const SizedBox(height: 8),
        Text(
          isDesktop
              ? 'Tools found on this computer. Commands run only on your own network, and the exact command is shown before it runs.'
              : 'These tools live on the Linux / desktop build. On this phone they are not installed — the Linux build (v0.5.0) runs them.',
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
              onPressed: _network == null ? null : _runNmapScan,
              icon: const Icon(Icons.radar),
              label: Text(
                'Run nmap ping scan (${network == null ? '…' : '${network.networkAddress}/${network.prefix}'})',
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _runArpScan,
              icon: const Icon(Icons.hub),
              label: const Text('Run arp-scan --localnet'),
            ),
            if (_toolsNote.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(_toolsNote),
            ],
          ],
        ],
        const SizedBox(height: 24),
        const CyberHeading('Router detect (optional)'),
        const SizedBox(height: 8),
        const Text(
          'Only needed for the limiter: paste the router admin page title if you know it — it raises the confidence score. The scan above already filled in the gateway.',
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
