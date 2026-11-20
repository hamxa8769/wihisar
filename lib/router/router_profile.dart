/// Router profiles: what WiHisar knows about each vendor's hardware.
///
/// A profile is a set of *fingerprints* (keywords seen in the admin page,
/// SSDP/UPnP server string, SNMP sysDescr, or OUI vendor) plus the login
/// defaults that are public knowledge for that vendor. Defaults are shown
/// only so the user can log in to THEIR OWN router and change them — the app
/// never tries credentials against a router the user does not own, and it
/// never stores the admin password.
library;

/// How a router's admin page / firmware identifies itself.
class RouterProfile {
  const RouterProfile({
    required this.id,
    required this.vendor,
    required this.displayName,
    required this.keywords,
    required this.commonGatewayIps,
    this.defaultUsername,
    this.defaultPassword,
    this.loginNote,
    this.supportsAppLimit = false,
    this.limitNote = '',
  });

  /// Stable id, e.g. `vsol`.
  final String id;
  final String vendor;
  final String displayName;

  /// Lower-case substrings matched against HTTP title / Server header /
  /// SSDP server string / SNMP sysDescr / mDNS model.
  final List<String> keywords;

  /// Gateway IPs this vendor commonly uses.
  final List<String> commonGatewayIps;

  /// Publicly documented factory default login, if any.
  final String? defaultUsername;
  final String? defaultPassword;

  /// What the user needs to know at first login.
  final String? loginNote;

  /// True only when this vendor has a documented per-device limit API
  /// that WiHisar actually implements (see the adapter for this profile).
  final bool supportsAppLimit;

  final String limitNote;
}

/// All built-in profiles, most specific first.
const List<RouterProfile> routerProfiles = [
  RouterProfile(
    id: 'vsol',
    vendor: 'V-SOL',
    displayName: 'V-SOL ONU / ONT router',
    keywords: ['vsol', 'v-sol', 'v sol', 'gpon onu', 'onu web', 'vsol gpon'],
    commonGatewayIps: ['192.168.1.1', '192.168.131.1'],
    defaultUsername: 'admin',
    defaultPassword: 'stdONU101',
    loginNote:
        'Older V-SOL ONUs: 192.168.1.1, admin / stdONU101. Newer V-SOL routers: 192.168.131.1, no default password — you set one on first login. Change the admin password after first login.',
    supportsAppLimit: false,
    limitNote:
        'Most V-SOL ONU web UIs have no per-device bandwidth control. WiHisar can list devices (DHCP list) but cannot enforce a limit on this router. Fallback: put the router in bridge mode behind an OpenWrt router, or use a separate SSID with SQM.',
  ),
  RouterProfile(
    id: 'tplink',
    vendor: 'TP-Link',
    displayName: 'TP-Link Archer / Deco router',
    keywords: ['tp-link', 'tplink', 'archer', 'deco'],
    commonGatewayIps: ['192.168.0.1', '192.168.1.1'],
    defaultUsername: 'admin',
    defaultPassword: 'admin',
    loginNote:
        'Older TP-Link: admin / admin. Newer Archer/Deco: no default password — you set one on first setup. Modern firmware uses a token-based web API.',
    supportsAppLimit: true,
    limitNote:
        'TP-Link Bandwidth Control / QoS can limit per device on many Archer models. Support varies by model and firmware — WiHisar reports honestly when a model does not expose it.',
  ),
  RouterProfile(
    id: 'huawei',
    vendor: 'Huawei',
    displayName: 'Huawei ONT / router',
    keywords: ['huawei', 'hg8245', 'hg8145', 'eg8145', 'optixstar'],
    commonGatewayIps: ['192.168.100.1', '192.168.1.1'],
    defaultUsername: 'telecomadmin',
    defaultPassword: 'admintelecom',
    loginNote:
        'Huawei ONTs often have two logins: telecomadmin (full) and root/user. Defaults vary by ISP — PTCL and other ISPs commonly change them. Check the label on the router.',
    supportsAppLimit: false,
    limitNote:
        'Huawei ONT web UIs generally have no per-device bandwidth limit API. Device list is available; limiting needs an OpenWrt router behind it.',
  ),
  RouterProfile(
    id: 'zte',
    vendor: 'ZTE',
    displayName: 'ZTE F-series ONT / router',
    keywords: ['zte', 'zxhn', 'f660', 'f670', 'f680'],
    commonGatewayIps: ['192.168.1.1'],
    defaultUsername: 'admin',
    defaultPassword: 'admin',
    loginNote:
        'ZTE defaults vary by ISP; many ISP-supplied units change the admin password. Check the label on the router.',
    supportsAppLimit: false,
    limitNote:
        'ZTE F-series web UIs generally have no per-device bandwidth limit API. Device list is available; limiting needs an OpenWrt router behind it.',
  ),
  RouterProfile(
    id: 'openwrt',
    vendor: 'OpenWrt',
    displayName: 'OpenWrt router (LuCI)',
    keywords: ['openwrt', 'luci'],
    commonGatewayIps: ['192.168.1.1'],
    defaultUsername: 'root',
    loginNote:
        'OpenWrt uses the root password you set (or SSH key). No factory default — set it on first setup.',
    supportsAppLimit: true,
    limitNote:
        'Full per-device limiting via SQM (cake, dual-dsthost fairness) and HTB queues. Requires luci-app-sqm and SSH or LuCI RPC access.',
  ),
  RouterProfile(
    id: 'generic',
    vendor: 'Generic',
    displayName: 'Unknown / generic router',
    keywords: [],
    commonGatewayIps: ['192.168.1.1', '192.168.0.1', '192.168.100.1'],
    loginNote:
        'Unknown router. WiHisar will try the gateway IP, MAC vendor and admin-page fingerprint; if nothing matches, only the subnet device scan is available.',
    supportsAppLimit: false,
    limitNote:
        'Unknown router — no limiter API is implemented for it. WiHisar will say so instead of faking a limit.',
  ),
];

/// Find a profile by id, falling back to `generic`.
RouterProfile profileById(String id) => routerProfiles.firstWhere(
      (p) => p.id == id,
      orElse: () => routerProfiles.last,
    );
