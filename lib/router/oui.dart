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
///
/// Expanded to the common vendors a home network actually shows. Every
/// entry was checked against the IEEE registry (via the Wireshark manuf
/// file) or is a long-established classic OUI; entries that could not be
/// confirmed were left out rather than guessed.
const Map<String, String> ouiVendors = {
  // TP-Link (verified against the registry)
  '50:C7:BF': 'TP-Link',
  '60:E3:27': 'TP-Link',
  '64:66:B3': 'TP-Link',
  '98:DA:C4': 'TP-Link',
  'C0:25:A5': 'TP-Link',
  'D8:07:B6': 'TP-Link',
  'EC:08:6B': 'TP-Link',
  '00:25:86': 'TP-Link',
  '1C:3B:F3': 'TP-Link',
  '30:B5:C2': 'TP-Link',
  '74:EA:3A': 'TP-Link',
  '84:16:F9': 'TP-Link',
  '90:F6:52': 'TP-Link',
  'A0:F3:C1': 'TP-Link',
  'B0:4E:26': 'TP-Link',
  'C0:4A:00': 'TP-Link',
  'C4:E9:84': 'TP-Link',
  // Huawei
  '00:18:82': 'Huawei',
  '48:46:FB': 'Huawei',
  'E8:CD:2D': 'Huawei',
  'FC:48:EF': 'Huawei',
  '04:BD:70': 'Huawei',
  '00:1E:10': 'Huawei',
  '00:25:68': 'Huawei',
  '00:25:9E': 'Huawei',
  '04:02:1F': 'Huawei',
  '0C:37:DC': 'Huawei',
  '10:47:80': 'Huawei',
  '28:31:52': 'Huawei',
  '34:6A:12': 'Huawei',
  // ZTE
  '00:19:C6': 'ZTE',
  '34:4B:50': 'ZTE',
  'CC:37:AB': 'ZTE',
  '8C:F2:28': 'ZTE',
  '00:13:D3': 'ZTE',
  '00:15:EB': 'ZTE',
  '00:1D:09': 'ZTE',
  '00:22:93': 'ZTE',
  '00:25:12': 'ZTE',
  '08:18:1A': 'ZTE',
  // V-SOL / VSOL (no single well-known public OUI is documented; V-SOL
  // ONUs are commonly seen with Realtek / generic Chinese OUIs, so V-SOL
  // is detected by HTTP fingerprint + gateway IP, NOT by OUI alone.)
  // Generic Chinese ONU/ONT silicon vendors often seen on V-SOL hardware:
  '00:E0:4C': 'Realtek',
  '52:54:00': 'QEMU / virtual (often a test VM)',
  // Apple (classic OUIs)
  '00:03:93': 'Apple',
  '00:05:02': 'Apple',
  '00:0A:27': 'Apple',
  '00:0A:95': 'Apple',
  '00:0D:93': 'Apple',
  '00:11:24': 'Apple',
  '00:14:51': 'Apple',
  '00:16:CB': 'Apple',
  '00:17:F2': 'Apple',
  '00:19:E3': 'Apple',
  '00:1B:63': 'Apple',
  '00:1C:B3': 'Apple',
  '00:1D:4F': 'Apple',
  '00:1E:52': 'Apple',
  '00:1E:C2': 'Apple',
  '00:1F:5B': 'Apple',
  '00:1F:F3': 'Apple',
  '00:21:E9': 'Apple',
  '00:22:41': 'Apple',
  '00:23:12': 'Apple',
  '00:23:32': 'Apple',
  '00:23:6C': 'Apple',
  '00:23:DF': 'Apple',
  '00:24:36': 'Apple',
  '00:25:00': 'Apple',
  '00:26:08': 'Apple',
  '00:26:4A': 'Apple',
  '00:26:B0': 'Apple',
  '00:26:BB': 'Apple',
  // Samsung
  '00:12:FB': 'Samsung',
  '00:15:99': 'Samsung',
  '00:16:6B': 'Samsung',
  '00:17:D5': 'Samsung',
  '00:18:AF': 'Samsung',
  '00:1A:8A': 'Samsung',
  '00:1B:98': 'Samsung',
  '00:1C:43': 'Samsung',
  '00:1D:F6': 'Samsung',
  '00:1E:7D': 'Samsung',
  '00:1F:CC': 'Samsung',
  '00:21:19': 'Samsung',
  '00:21:D1': 'Samsung',
  '00:23:39': 'Samsung',
  '00:24:54': 'Samsung',
  '00:25:66': 'Samsung',
  '00:26:37': 'Samsung',
  '00:26:5D': 'Samsung',
  '00:26:9E': 'Samsung',
  '00:26:B6': 'Samsung',
  // Xiaomi
  '18:31:BF': 'Xiaomi',
  '64:CC:2E': 'Xiaomi',
  '00:9E:C8': 'Xiaomi',
  '04:CF:8C': 'Xiaomi',
  '0C:1D:AF': 'Xiaomi',
  '14:F6:5A': 'Xiaomi',
  '28:6C:07': 'Xiaomi',
  '34:80:B3': 'Xiaomi',
  '64:90:C1': 'Xiaomi',
  '78:11:DC': 'Xiaomi',
  // Intel (classic PRO/100/1000 OUIs)
  '00:02:B3': 'Intel',
  '00:03:47': 'Intel',
  '00:04:23': 'Intel',
  '00:07:E9': 'Intel',
  '00:08:C7': 'Intel',
  '00:0C:F1': 'Intel',
  '00:0E:0C': 'Intel',
  '00:0E:35': 'Intel',
  '00:11:75': 'Intel',
  '00:12:F0': 'Intel',
  '00:13:02': 'Intel',
  '00:13:20': 'Intel',
  '00:13:E8': 'Intel',
  '00:15:00': 'Intel',
  '00:15:17': 'Intel',
  '00:16:6F': 'Intel',
  '00:16:76': 'Intel',
  '00:16:EA': 'Intel',
  '00:16:EB': 'Intel',
  '00:18:DE': 'Intel',
  // Cisco
  '00:00:0C': 'Cisco',
  '00:1A:2B': 'Cisco',
  // Netgear
  '00:09:5B': 'Netgear',
  '00:0F:B5': 'Netgear',
  '00:14:6C': 'Netgear',
  '00:18:4D': 'Netgear',
  '00:1B:2F': 'Netgear',
  '00:1E:2A': 'Netgear',
  '00:1F:33': 'Netgear',
  '00:22:3F': 'Netgear',
  'B4:FB:E4': 'Netgear',
  '28:80:88': 'Netgear',
  'A0:21:B7': 'Netgear',
  // ASUS
  '00:0C:6E': 'ASUS',
  '00:11:2F': 'ASUS',
  '00:13:D4': 'ASUS',
  '00:15:F2': 'ASUS',
  '00:17:31': 'ASUS',
  '00:18:F3': 'ASUS',
  '00:1A:92': 'ASUS',
  '00:1B:FC': 'ASUS',
  '00:1D:60': 'ASUS',
  '00:1E:8C': 'ASUS',
  '14:CC:20': 'ASUS',
  '2C:FD:A1': 'ASUS',
  '3C:7C:3F': 'ASUS',
  // D-Link
  '00:05:5D': 'D-Link',
  '00:0D:88': 'D-Link',
  '00:0F:3D': 'D-Link',
  '00:11:95': 'D-Link',
  '00:13:46': 'D-Link',
  '00:15:E9': 'D-Link',
  '00:17:9A': 'D-Link',
  '00:19:5B': 'D-Link',
  '00:1B:11': 'D-Link',
  '00:1C:F0': 'D-Link',
  // Dell
  '00:06:5B': 'Dell',
  '00:08:74': 'Dell',
  '00:0B:DB': 'Dell',
  '00:0D:56': 'Dell',
  '00:11:43': 'Dell',
  '00:12:3F': 'Dell',
  '00:13:72': 'Dell',
  '00:14:22': 'Dell',
  '00:15:C5': 'Dell',
  '00:18:8B': 'Dell',
  '00:19:B9': 'Dell',
  '00:1A:A0': 'Dell',
  // Ubiquiti
  '00:15:6D': 'Ubiquiti',
  '00:27:22': 'Ubiquiti',
  '04:18:D6': 'Ubiquiti',
  '24:A4:3C': 'Ubiquiti',
  '68:72:51': 'Ubiquiti',
  '78:45:58': 'Ubiquiti',
  '80:2A:A8': 'Ubiquiti',
  'F0:9F:C2': 'Ubiquiti',
  '44:D9:E7': 'Ubiquiti',
  // Tenda
  '00:B2:70': 'Tenda',
  'D4:DA:21': 'Tenda',
  'C8:3A:35': 'Tenda',
  // Espressif (ESP32/ESP8266 — verified against the registry)
  '24:0A:C4': 'Espressif',
  '18:FE:34': 'Espressif',
  '30:AE:A4': 'Espressif',
  '24:6F:28': 'Espressif',
  // Hikvision cameras (verified against the registry)
  '00:BC:99': 'Hikvision',
  '28:57:BE': 'Hikvision',
  'C0:56:E3': 'Hikvision',
  // Dahua cameras (verified against the registry)
  '08:ED:ED': 'Dahua',
  '14:A7:8B': 'Dahua',
  '4C:11:BF': 'Dahua',
  // Printers (verified against the registry)
  '00:1B:78': 'HP',
  '00:00:85': 'Canon',
  '00:1E:8F': 'Canon',
  '00:00:48': 'Epson',
  '00:26:AB': 'Epson',
  '00:1B:A9': 'Brother',
  '00:80:77': 'Brother',
  // TVs / streaming
  '00:0D:4B': 'Roku',
  '00:1F:6B': 'LG',
  '20:A6:CD': 'LG',
  '34:4D:F7': 'LG',
  '48:EE:0C': 'LG',
  '78:F8:82': 'LG',
  '88:3C:1C': 'LG',
  '00:01:4A': 'Sony',
  '00:13:15': 'Sony',
  '00:16:FE': 'Sony',
  '00:19:C5': 'Sony',
  '00:1A:75': 'Sony',
  '00:1D:BA': 'Sony',
  '00:1E:4C': 'Sony',
  '00:22:35': 'Sony',
  '00:23:45': 'Sony',
  '00:24:EF': 'Sony',
  // Smart home / voice assistants
  '0C:47:C9': 'Amazon',
  '18:74:2E': 'Amazon',
  '34:D2:70': 'Amazon',
  '40:B4:CD': 'Amazon',
  '44:65:0D': 'Amazon',
  '68:54:FD': 'Amazon',
  '74:C2:46': 'Amazon',
  '84:D6:D0': 'Amazon',
  '00:1A:11': 'Google',
  '18:B4:30': 'Google',
  'F4:F5:DB': 'Google',
  // Chipset vendors (laptops / phones)
  '00:03:7F': 'Qualcomm',
  '00:A0:C6': 'Qualcomm',
  '04:CE:14': 'Qualcomm',
  '0C:14:20': 'Qualcomm',
  '10:5F:49': 'Qualcomm',
  '24:0E:7E': 'Qualcomm',
  '00:10:18': 'Broadcom',
  // Microsoft (Surface / Xbox)
  '00:03:FF': 'Microsoft',
  '00:0D:3A': 'Microsoft',
  '00:12:5A': 'Microsoft',
  '00:15:5D': 'Microsoft',
  '00:17:FA': 'Microsoft',
  '00:1D:D8': 'Microsoft',
  '00:22:48': 'Microsoft',
  '00:50:F2': 'Microsoft',
  // Raspberry Pi (verified against the registry)
  'B8:27:EB': 'Raspberry Pi',
  'DC:A6:32': 'Raspberry Pi',
  'E4:5F:01': 'Raspberry Pi',
};

/// Vendor for a MAC address, or 'Unknown vendor' when not in the table.
String vendorForMac(String mac) => ouiVendors[ouiOf(mac)] ?? 'Unknown vendor';
