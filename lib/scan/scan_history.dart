/// Scan history: remembers which devices (by MAC) have been seen before,
/// so the next scan can flag a MAC that never appeared as NEW.
///
/// Stored in shared_preferences under [historyKey] as JSON:
/// `{mac: {ip, label, firstSeen, lastSeen}}` (epoch milliseconds).
/// Corrupt or missing data loads as empty history — never throws.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'host.dart';

class _SeenDevice {
  const _SeenDevice({
    required this.ip,
    required this.label,
    required this.firstSeenMs,
    required this.lastSeenMs,
  });

  final String ip;
  final String label;
  final int firstSeenMs;
  final int lastSeenMs;

  Map<String, dynamic> toJson() => {
        'ip': ip,
        'label': label,
        'firstSeen': firstSeenMs,
        'lastSeen': lastSeenMs,
      };

  factory _SeenDevice.fromJson(Map<String, dynamic> json) => _SeenDevice(
        ip: json['ip']?.toString() ?? '',
        label: json['label']?.toString() ?? '',
        firstSeenMs: json['firstSeen'] as int? ?? 0,
        lastSeenMs: json['lastSeen'] as int? ?? 0,
      );
}

class ScanHistory {
  static const String historyKey = 'wihisar_last_seen';

  final Map<String, _SeenDevice> _seen = {};

  /// MAC addresses seen before, upper-case.
  Set<String> get knownMacs => _seen.keys.toSet();

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(historyKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      _seen.clear();
      for (final entry in decoded.entries) {
        final value = entry.value;
        if (value is! Map<String, dynamic>) continue;
        _seen[entry.key.toUpperCase()] =
            _SeenDevice.fromJson(value);
      }
    } catch (_) {
      // Corrupt storage loads as empty history.
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    final map = {
      for (final e in _seen.entries) e.key: e.value.toJson(),
    };
    await prefs.setString(historyKey, jsonEncode(map));
  }

  /// MACs in [hosts] that were never seen before (non-empty MACs only).
  /// Call BEFORE [recordScan], or the answer is always empty.
  Set<String> newMacs(List<ScannedHost> hosts) {
    final fresh = <String>{};
    for (final h in hosts) {
      final mac = (h.mac ?? '').trim().toUpperCase();
      if (mac.isEmpty) continue;
      if (!_seen.containsKey(mac)) fresh.add(mac);
    }
    return fresh;
  }

  /// Record this scan: new MACs get a first-seen time, known ones get a
  /// fresh last-seen time. Persists immediately.
  Future<void> recordScan(List<ScannedHost> hosts, {DateTime? now}) async {
    final at = (now ?? DateTime.now()).millisecondsSinceEpoch;
    for (final h in hosts) {
      final mac = (h.mac ?? '').trim().toUpperCase();
      if (mac.isEmpty) continue;
      final previous = _seen[mac];
      _seen[mac] = _SeenDevice(
        ip: h.ip,
        label: h.displayName,
        firstSeenMs: previous?.firstSeenMs ?? at,
        lastSeenMs: at,
      );
    }
    await save();
  }
}
