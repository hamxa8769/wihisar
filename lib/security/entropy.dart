/// WiHisar security-tester core: password-strength estimation.
///
/// EDUCATIONAL, OWN-WIFI ONLY.
/// This module estimates how hard an *already-known-to-the-user* password
/// would be to guess. It NEVER captures handshakes, NEVER runs a dictionary
/// or brute-force attack, and NEVER sends the password anywhere. The password
/// is passed in as a plain [String] by the caller, used only inside pure
/// functions, and never stored, logged, or transmitted by this module.
///
/// Entropy formula: `entropyBits = length * log2(poolSize)`
/// where poolSize is the size of the character set the password draws from.
/// Estimated offline crack time (average case, half the keyspace):
/// `timeSeconds = 2 ^ (entropyBits - 1) / guessesPerSecond`.
///
/// Reference rates (WPA2 offline PBKDF2-HMAC-SHA1, 4096 iterations):
/// - 100_000 guesses/s: a modest laptop GPU.
/// - 1_000_000 guesses/s: a single modern consumer GPU (e.g. RTX 3070 class,
///   ~750k-1M WPA2 hashes/s in published benchmarks).
/// - 10_000_000 guesses/s: an 8-GPU rig.
/// WPA3-SAE makes offline dictionary attacks impractical by design, so the
/// WPA2 rate is a worst-case estimate; for WPA3 the same password is
/// strictly harder to attack. The report says this explicitly.
library;

import 'dart:math' as math;

/// Offline guess rates used for the crack-time estimate.
enum GuessRate {
  /// Modest laptop GPU.
  laptop(100000, 'laptop GPU (~100k guesses/s)'),

  /// Single modern consumer GPU.
  singleGpu(1000000, 'single GPU (~1M guesses/s)'),

  /// Multi-GPU rig.
  gpuRig(10000000, '8-GPU rig (~10M guesses/s)');

  const GuessRate(this.guessesPerSecond, this.label);

  final int guessesPerSecond;
  final String label;
}

/// Result of analysing one password. Contains no copy of the password.
class PasswordAnalysis {
  const PasswordAnalysis({
    required this.length,
    required this.poolSize,
    required this.entropyBits,
    required this.hasLower,
    required this.hasUpper,
    required this.hasDigit,
    required this.hasSymbol,
    required this.looksLikeDictionaryWord,
  });

  final int length;
  final int poolSize;
  final double entropyBits;
  final bool hasLower;
  final bool hasUpper;
  final bool hasDigit;
  final bool hasSymbol;

  /// True when the password is a single common word / short predictable
  /// pattern. This is a local heuristic over a tiny built-in list, not a
  /// dictionary attack: it only flags passwords the user typed themselves.
  final bool looksLikeDictionaryWord;

  /// Average-case offline crack time in seconds at [rate].
  double crackTimeSeconds(GuessRate rate) {
    if (entropyBits <= 0) return 0;
    // Average guesses needed = half the keyspace.
    return math.pow(2, entropyBits - 1) / rate.guessesPerSecond;
  }

  /// Human-readable crack-time estimate at [rate].
  String crackTimeLabel([GuessRate rate = GuessRate.singleGpu]) =>
      formatDuration(crackTimeSeconds(rate));

  /// Rough strength label from entropy alone.
  String get strengthLabel {
    if (entropyBits < 28) return 'Very weak';
    if (entropyBits < 36) return 'Weak';
    if (entropyBits < 60) return 'Fair';
    if (entropyBits < 80) return 'Strong';
    return 'Very strong';
  }
}

/// Character-set size for [password], from the classes it actually uses.
int characterPoolSize(String password) {
  var pool = 0;
  if (password.contains(RegExp(r'[a-z]'))) pool += 26;
  if (password.contains(RegExp(r'[A-Z]'))) pool += 26;
  if (password.contains(RegExp(r'[0-9]'))) pool += 10;
  // Printable ASCII symbols (space excluded; 32 symbols).
  if (password.contains(RegExp(r'[!-/:-@\[-`{-~]'))) pool += 32;
  if (password.contains(' ')) pool += 1;
  return pool;
}

const _commonPasswords = <String>{
  'password',
  '12345678',
  '123456789',
  'qwerty123',
  'admin123',
  'letmein',
  'welcome',
  'iloveyou',
  'monkey123',
  'dragon123',
  'football',
  'sunshine',
  'princess',
  'password1',
  '1234567890',
  '00000000',
  '11111111',
};

/// Analyse [password] locally. The password is not stored or returned.
PasswordAnalysis analysePassword(String password) {
  final pool = characterPoolSize(password);
  final entropy = pool == 0 || password.isEmpty
      ? 0.0
      : password.length * (math.log(pool) / math.log(2));
  return PasswordAnalysis(
    length: password.length,
    poolSize: pool,
    entropyBits: entropy,
    hasLower: password.contains(RegExp(r'[a-z]')),
    hasUpper: password.contains(RegExp(r'[A-Z]')),
    hasDigit: password.contains(RegExp(r'[0-9]')),
    hasSymbol: password.contains(RegExp(r'[!-/:-@\[-`{-~]')),
    looksLikeDictionaryWord:
        _commonPasswords.contains(password.toLowerCase()) ||
            (password.length <= 10 &&
                RegExp(r'^[a-z]+$').hasMatch(password.toLowerCase())),
  );
}

/// Format a duration in seconds as a short human label.
String formatDuration(double seconds) {
  if (seconds.isNaN || seconds.isInfinite) return 'effectively never';
  if (seconds < 1) return 'less than a second';
  if (seconds < 60) return '${seconds.toStringAsFixed(0)} seconds';
  final minutes = seconds / 60;
  if (minutes < 60) return '${minutes.toStringAsFixed(1)} minutes';
  final hours = minutes / 60;
  if (hours < 24) return '${hours.toStringAsFixed(1)} hours';
  final days = hours / 24;
  if (days < 365) return '${days.toStringAsFixed(1)} days';
  final years = days / 365;
  if (years < 1000) return '${years.toStringAsFixed(1)} years';
  if (years < 1000000) {
    return '${(years / 1000).toStringAsFixed(1)} thousand years';
  }
  return '${(years / 1000000).toStringAsFixed(1)} million years';
}
