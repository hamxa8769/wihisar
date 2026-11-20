/// Small offline IEEE OUI (vendor) table for gateway MAC lookup.
///
/// This is a deliberately small starter table — the full IEEE registry is
/// huge and would bloat a lightweight app. It covers the vendors WiHisar
/// profiles first (TP-Link, Huawei, ZTE, common Chinese ONU/ONT makers) plus
/// the biggest consumer brands. Add rows as new routers are seen in the
/// field; unknown OUIs return 'Unknown vendor' and lower the detection
/// confidence instead of guessing.
library;

/// Normalise a MAC to upper-case colon form, e.g. `50:C7:BF:AA:BB:CC`.
String normaliseMac(String mac) {
  final hex = mac.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toUpperCase();
  if (hex.length < 12) return mac.toUpperCase();
  final parts = <String>[];
  for (var i = 0; i < 12; i += 2) {
    parts.add(hex.substring(i, i + 2));
  }
  return parts.join(':');
}

/// First 3 bytes (OUI) of a MAC address.
String ouiOf(String mac) {
  final n = normaliseMac(mac);
  final parts = n.split(':');
  return parts.length >= 3 ? parts.sublist(0, 3).join(':') : '';
}

/// OUI -> vendor. Keys are upper-case colon OUIs.
const Map<String, String> ouiVendors = {
  // TP-Link
  '50:C7:BF': 'TP-Link',
  '60:E3:27': 'TP-Link',
  '64:66:B3': 'TP-Link',
  '98:DA:C4': 'TP-Link',
  'C0:25:A5': 'TP-Link',
  'D8:07:B6': 'TP-Link',
  'EC:08:6B': 'TP-Link',
  // Huawei
  '00:18:82': 'Huawei',
  '48:46:FB': 'Huawei',
  'E8:CD:2D': 'Huawei',
  'FC:48:EF': 'Huawei',
  '04:BD:70': 'Huawei',
  // ZTE
  '00:19:C6': 'ZTE',
  '34:4B:50': 'ZTE',
  'CC:37:AB': 'ZTE',
  '8C:F2:28': 'ZTE',
  // V-SOL / VSOL (no single well-known public OUI is documented; V-SOL
  // ONUs are commonly seen with Realtek / generic Chinese OUIs, so V-SOL
  // is detected by HTTP fingerprint + gateway IP, NOT by OUI alone.)
  // Generic Chinese ONU/ONT silicon vendors often seen on V-SOL hardware:
  '00:E0:4C': 'Realtek',
  '52:54:00': 'QEMU / virtual (often a test VM)',
  // Other big consumer brands
  '00:1A:2B': 'Cisco',
  'F0:9F:C2': 'Ubiquiti',
  '44:D9:E7': 'Ubiquiti',
  'B4:FB:E4': 'Netgear',
  '28:80:88': 'Netgear',
  'A0:21:B7': 'Netgear',
  '14:CC:20': 'ASUS',
  '2C:FD:A1': 'ASUS',
  '3C:7C:3F': 'ASUS',
  '18:31:BF': 'Xiaomi',
  '64:CC:2E': 'Xiaomi',
  'D4:DA:21': 'Tenda',
  'C8:3A:35': 'Tenda',
};

/// Vendor for a MAC address, or 'Unknown vendor' when not in the table.
String vendorForMac(String mac) => ouiVendors[ouiOf(mac)] ?? 'Unknown vendor';
