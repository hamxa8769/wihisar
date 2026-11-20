import 'package:flutter_test/flutter_test.dart';
import 'package:wihisar/security/security_tester.dart';

void main() {
  group('characterPoolSize', () {
    test('lowercase only is 26', () {
      expect(characterPoolSize('abcdefgh'), 26);
    });

    test('mixed classes add up', () {
      expect(characterPoolSize('Ab1!'), 26 + 26 + 10 + 32);
    });

    test('empty password has no pool', () {
      expect(characterPoolSize(''), 0);
    });
  });

  group('analysePassword', () {
    test('entropy is length x log2(pool)', () {
      // 8 lowercase chars: 8 * log2(26) ≈ 37.6 bits — 'Fair' on the
      // strength scale (<28 very weak, <36 weak, <60 fair).
      final a = analysePassword('abcdefgh');
      expect(a.entropyBits, closeTo(8 * 4.7004, 0.01));
      expect(a.strengthLabel, 'Fair');
    });

    test('16 mixed chars is very strong (~105 bits)', () {
      final a = analysePassword('K7#mQ9!xZ2@wP4\$v');
      expect(a.entropyBits, greaterThan(100));
      expect(a.strengthLabel, 'Very strong');
    });

    test('common password is flagged', () {
      expect(analysePassword('password').looksLikeDictionaryWord, isTrue);
      expect(analysePassword('password1').looksLikeDictionaryWord, isTrue);
    });

    test('random password is not flagged', () {
      expect(
          analysePassword('K7#mQ9!xZ2@wP4\$v').looksLikeDictionaryWord,
          isFalse);
    });

    test('short password has a short crack time at GPU speed', () {
      final a = analysePassword('abc12345');
      // ~41 bits at 1M guesses/s ≈ 2^40 / 1e6 ≈ 12 days — weak, not instant.
      expect(a.crackTimeSeconds(GuessRate.singleGpu),
          lessThan(60 * 60 * 24 * 365));
      expect(a.crackTimeSeconds(GuessRate.singleGpu), greaterThan(60));
    });

    test('16 mixed chars takes far longer than a human lifetime', () {
      final a = analysePassword('K7#mQ9!xZ2@wP4\$v');
      final years = a.crackTimeSeconds(GuessRate.gpuRig) / (365 * 24 * 3600);
      expect(years, greaterThan(1e12));
    });

    test('crack time grows with the guess rate', () {
      final a = analysePassword('correcthorsebatterystaple!');
      expect(a.crackTimeSeconds(GuessRate.laptop),
          greaterThan(a.crackTimeSeconds(GuessRate.singleGpu)));
      expect(a.crackTimeSeconds(GuessRate.singleGpu),
          greaterThan(a.crackTimeSeconds(GuessRate.gpuRig)));
    });
  });

  group('formatDuration', () {
    test('formats seconds, days and years', () {
      expect(formatDuration(0.5), 'less than a second');
      expect(formatDuration(90), contains('minutes'));
      expect(formatDuration(90000), contains('days'));
      expect(formatDuration(365 * 24 * 3600 * 5), contains('years'));
    });
  });

  group('SecurityReport', () {
    test('WPA3 + strong password + WPS off scores an A', () {
      final report = testOwnWifi(
        ssid: 'MyHome',
        securityType: SecurityType.wpa3,
        wpsEnabled: false,
        password: 'K7#mQ9!xZ2@wP4\$vT8&nR1',
      );
      expect(report.grade, 'A');
      expect(report.score, greaterThanOrEqualTo(90));
    });

    test('WEP + weak password scores an F', () {
      final report = testOwnWifi(
        ssid: 'OldNet',
        securityType: SecurityType.wep,
        wpsEnabled: true,
        password: 'password',
      );
      expect(report.grade, 'F');
      expect(report.fixes, isNotEmpty);
      expect(report.fixes.first, contains('WPA3'));
    });

    test('WPS on lowers the score and adds a fix', () {
      final withWps = testOwnWifi(
        ssid: 'Home',
        securityType: SecurityType.wpa2,
        wpsEnabled: true,
        password: 'K7#mQ9!xZ2@wP4\$vT8&nR1',
      );
      final withoutWps = testOwnWifi(
        ssid: 'Home',
        securityType: SecurityType.wpa2,
        wpsEnabled: false,
        password: 'K7#mQ9!xZ2@wP4\$vT8&nR1',
      );
      expect(withWps.score, lessThan(withoutWps.score));
      expect(withWps.fixes.any((f) => f.contains('WPS')), isTrue);
    });

    test('report never contains the password', () {
      const password = 'K7#mQ9!xZ2@wP4\$v';
      final report = testOwnWifi(
        ssid: 'Home',
        securityType: SecurityType.wpa2,
        wpsEnabled: false,
        password: password,
      );
      expect(report.toString(), isNot(contains(password)));
      // The analysis keeps only derived numbers.
      expect(report.passwordAnalysis.length, password.length);
    });
  });
}
