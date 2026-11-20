/// Own-WiFi security report: what the tester found and how to fix it.
///
/// This module is deliberately reusable: it has no Flutter dependency, so it
/// can be dropped into another Dart/Flutter project as a standalone package
/// (see `lib/security/` — copy the whole folder).
library;

import 'entropy.dart';

/// WiFi security protocol seen on the user's own network.
enum SecurityType {
  wpa3('WPA3 (SAE)', 100, 'Current standard. SAE stops offline dictionary attacks.'),
  wpa2('WPA2 (AES/CCMP)', 80,
      'Secure with a strong password. A captured handshake can be attacked offline, so password entropy is everything.'),
  wpa('WPA (TKIP)', 40, 'Outdated. TKIP has known weaknesses; upgrade to WPA2/WPA3.'),
  wep('WEP', 5, 'Broken. Crackable in minutes regardless of password. Never use.'),
  open('Open (no password)', 0, 'No encryption at all. Anyone nearby can read traffic.'),
  unknown('Unknown', 50, 'Could not determine the security type.');

  const SecurityType(this.label, this.baseScore, this.note);

  final String label;

  /// Score contribution (0-100) of the protocol alone.
  final int baseScore;
  final String note;
}

/// A complete, locally computed report for the user's own WiFi.
class SecurityReport {
  SecurityReport({
    required this.ssid,
    required this.securityType,
    required this.wpsEnabled,
    required this.passwordAnalysis,
    this.signalDbm,
    this.channel,
    this.band,
  }) : score = _computeScore(
          securityType: securityType,
          wpsEnabled: wpsEnabled,
          passwordAnalysis: passwordAnalysis,
        );

  final String ssid;
  final SecurityType securityType;
  final bool wpsEnabled;
  final PasswordAnalysis passwordAnalysis;
  final int? signalDbm;
  final int? channel;
  final String? band;

  /// Overall score 0-100.
  final int score;

  static int _computeScore({
    required SecurityType securityType,
    required bool wpsEnabled,
    required PasswordAnalysis passwordAnalysis,
  }) {
    var score = securityType.baseScore * 0.5;
    // Password entropy contributes up to 50 points (80+ bits = full marks).
    score += (passwordAnalysis.entropyBits.clamp(0, 80) / 80) * 50;
    if (wpsEnabled) score -= 20; // WPS PIN is brute-forceable in hours.
    if (passwordAnalysis.looksLikeDictionaryWord) score -= 15;
    if (passwordAnalysis.length < 8) score -= 10;
    return score.clamp(0, 100).round();
  }

  String get grade {
    if (score >= 90) return 'A';
    if (score >= 75) return 'B';
    if (score >= 60) return 'C';
    if (score >= 40) return 'D';
    return 'F';
  }

  String get verdict {
    switch (grade) {
      case 'A':
        return 'Excellent — your WiFi is well protected.';
      case 'B':
        return 'Good — a few improvements would make it excellent.';
      case 'C':
        return 'Fair — worth fixing the items below.';
      case 'D':
        return 'Weak — an attacker nearby could break in with modest effort.';
      default:
        return 'Critical — change your settings now.';
    }
  }

  /// Concrete fixes, most urgent first.
  List<String> get fixes {
    final fixes = <String>[];
    if (securityType == SecurityType.wep ||
        securityType == SecurityType.open) {
      fixes.add(
          'Switch the router to WPA3 if available, otherwise WPA2 with AES. Never use WEP or an open network.');
    } else if (securityType == SecurityType.wpa) {
      fixes.add('Switch from WPA/TKIP to WPA2 or WPA3 with AES.');
    } else if (securityType == SecurityType.wpa2) {
      fixes.add(
          'If your router offers WPA3, switch to WPA3 (or WPA2/WPA3 mixed mode for older devices).');
    }
    if (wpsEnabled) {
      fixes.add(
          'Turn WPS off. The 8-digit WPS PIN can be brute-forced in hours — it bypasses your password.');
    }
    if (passwordAnalysis.length < 16) {
      fixes.add(
          'Use a password of 16+ characters. Length beats complexity: each extra random character multiplies the attacker\u2019s work.');
    }
    if (!passwordAnalysis.hasUpper ||
        !passwordAnalysis.hasDigit ||
        !passwordAnalysis.hasSymbol) {
      fixes.add(
          'Mix upper/lowercase letters, digits and symbols — or use 5 random words, which is just as strong and easier to type.');
    }
    if (passwordAnalysis.looksLikeDictionaryWord) {
      fixes.add(
          'Avoid common words, names, dates and your address — those are the first guesses in any wordlist.');
    }
    fixes.add(
        'Change the router admin password from its default (e.g. V-SOL admin/stdONU101) and keep the firmware updated.');
    return fixes;
  }

  /// One-line summary of the crack-time estimate, with the WPA3 caveat.
  String crackTimeSummary() {
    if (securityType == SecurityType.wpa3) {
      return 'WPA3 (SAE) makes offline guessing impractical, so the WPA2-style estimate below is a worst case — your real protection is stronger.';
    }
    return 'Estimated offline crack time at single-GPU speed: '
        '${passwordAnalysis.crackTimeLabel(GuessRate.singleGpu)} '
        '(laptop: ${passwordAnalysis.crackTimeLabel(GuessRate.laptop)}; '
        '8-GPU rig: ${passwordAnalysis.crackTimeLabel(GuessRate.gpuRig)}).';
  }
}
