/// WiHisar v0.1.0 — own-WiFi security tester + bandwidth limiter.
///
/// Educational, own-router only. No password cracking of any kind: the
/// security test estimates the strength of a password the user types in
/// for THEIR OWN network, locally, and never stores or sends it.
library;

import 'package:flutter/material.dart';

import 'devices/device_scan.dart';
import 'limiter/limit_rule.dart';
import 'limiter/limiter_service.dart';
import 'router/adapters/generic_adapter.dart';
import 'router/router_adapter.dart';
import 'router/router_detect.dart';
import 'security/security_tester.dart';
import 'wifi/wifi_info.dart';

void main() => runApp(const WiHisarApp());

class WiHisarApp extends StatelessWidget {
  const WiHisarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WiHisar — وائی حصار',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
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

  // --- Devices / detection state ---
  final _gatewayCtrl = TextEditingController(text: '192.168.1.1');
  final _titleCtrl = TextEditingController();
  final _serverCtrl = TextEditingController();
  RouterDetection? _detection;
  List<ConnectedDevice> _devices = [];
  String _scanNote = '';

  // --- Limits tab state ---
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

  Future<void> _scanDevices() async {
    setState(() => _scanNote = 'Scanning the local subnet…');
    final devices = await SubnetScanner().readNeighbourTable();
    setState(() {
      _devices = devices;
      _scanNote = devices.isEmpty
          ? 'No devices found in the ARP table. On this device the scan may need local-network permission — try the router DHCP list instead.'
          : 'Found ${devices.length} device(s) in the ARP table.';
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
        title: const Text('WiHisar — وائی حصار'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'About',
            onPressed: () => showDialog<void>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('WiHisar v0.1.0'),
                content: const Text(
                  'Own-WiFi security tester and bandwidth limiter (educational).\n\n'
                  '• Tests ONLY your own WiFi.\n'
                  '• No password cracking, no handshake capture.\n'
                  '• Your password is analysed locally and never stored or sent.\n'
                  '• On iOS, WiFi scanning is blocked by Apple — use the router-login path.\n'
                  '• If your router has no limiter API, WiHisar says so instead of faking a limit.',
                ),
                actions: [
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
      body: IndexedStack(
        index: _tab,
        children: [_testTab(), _devicesTab(), _limitsTab()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.shield_outlined), label: 'Test'),
          NavigationDestination(icon: Icon(Icons.devices), label: 'Devices'),
          NavigationDestination(icon: Icon(Icons.speed), label: 'Limits'),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- Test tab
  Widget _testTab() {
    final report = _report;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Test your OWN WiFi',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Detect your router',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'WiHisar detects the gateway automatically (gateway IP, MAC vendor, admin-page fingerprint). Paste the admin page title if you know it — it raises the confidence score.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _gatewayCtrl,
          decoration: const InputDecoration(
            labelText: 'Gateway IP',
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
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _scanDevices,
          icon: const Icon(Icons.search),
          label: const Text('Scan connected devices'),
        ),
        if (_scanNote.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(_scanNote),
        ],
        const SizedBox(height: 8),
        for (final d in _devices)
          ListTile(
            leading: Icon(
                d.isGateway ? Icons.router : Icons.devices_other),
            title: Text(d.hostname ?? d.ip),
            subtitle: Text(
                '${d.ip} • ${d.mac}${d.vendor != null ? ' • ${d.vendor}' : ''}'),
            onTap: () => setState(() {
              _selectedDevice = d;
              _tab = 2;
            }),
          ),
        const SizedBox(height: 8),
        const Text(
          'Tip: tap a device to set its limit on the Limits tab. '
          'On iOS, WiFi scanning is blocked by Apple — the device list comes from your router instead.',
          style: TextStyle(color: Colors.grey),
        ),
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
        const Text(
          'Bandwidth limits',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
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
