import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wihisar/roadmap/roadmap.dart';
import 'package:wihisar/update/app_update.dart';

void main() {
  group('parseVersion', () {
    test('parses plain and v-prefixed versions', () {
      expect(parseVersion('0.2.0'), [0, 2, 0]);
      expect(parseVersion('v0.3.0'), [0, 3, 0]);
      expect(parseVersion('v1.10.2+5'), [1, 10, 2]);
    });

    test('rejects non-versions', () {
      expect(parseVersion('hello'), isNull);
      expect(parseVersion('0.2'), isNull);
      expect(parseVersion(''), isNull);
    });
  });

  group('isNewerVersion', () {
    test('newer patch/minor/major wins', () {
      expect(isNewerVersion('0.2.1', '0.2.0'), isTrue);
      expect(isNewerVersion('0.3.0', '0.2.0'), isTrue);
      expect(isNewerVersion('1.0.0', '0.9.9'), isTrue);
    });

    test('same or older is not newer', () {
      expect(isNewerVersion('0.2.0', '0.2.0'), isFalse);
      expect(isNewerVersion('0.1.9', '0.2.0'), isFalse);
      expect(isNewerVersion('v0.2.0', '0.2.0'), isFalse);
    });
  });

  group('UpdateInfo.fromJson', () {
    test('parses a GitHub latest-release payload', () {
      final info = UpdateInfo.fromJson(
        jsonDecode('''
        {
          "tag_name": "v0.3.0",
          "html_url": "https://github.com/hamxa8769/wihisar/releases/tag/v0.3.0",
          "body": "IP scanner lands.",
          "assets": [
            {"name": "wihisar-v0.3.0.apk",
             "browser_download_url": "https://example.com/app.apk"},
            {"name": "wihisar-v0.3.0-windows.zip",
             "browser_download_url": "https://example.com/app.zip"}
          ]
        }
        ''') as Map<String, dynamic>,
      );
      expect(info.latestVersion, '0.3.0');
      expect(info.releaseNotes, contains('IP scanner'));
      expect(info.assetFor('android')?.name, 'wihisar-v0.3.0.apk');
      expect(info.assetFor('windows')?.name, 'wihisar-v0.3.0-windows.zip');
      expect(info.assetFor('ios'), isNull);
    });
  });

  group('checkForUpdate', () {
    test('reports available when the fake release is newer', () async {
      final result = await checkForUpdate(
        currentVersion: '0.2.0',
        fetcher: (_) async => jsonEncode({
          'tag_name': 'v0.3.0',
          'html_url': 'https://github.com/hamxa8769/wihisar/releases/tag/v0.3.0',
          'body': '',
          'assets': [],
        }),
      );
      expect(result.updateAvailable, isTrue);
      expect(result.info?.latestVersion, '0.3.0');
      expect(result.error, isNull);
    });

    test('reports up-to-date when versions match', () async {
      final result = await checkForUpdate(
        currentVersion: '0.2.0',
        fetcher: (_) async => jsonEncode({
          'tag_name': 'v0.2.0',
          'html_url': 'https://github.com/hamxa8769/wihisar/releases/tag/v0.2.0',
          'body': '',
          'assets': [],
        }),
      );
      expect(result.updateAvailable, isFalse);
    });

    test('never throws: offline becomes an error result', () async {
      final result = await checkForUpdate(
        fetcher: (_) async => throw const FormatException('no network'),
      );
      expect(result.updateAvailable, isFalse);
      expect(result.error, isNotNull);
    });
  });

  group('roadmap', () {
    test('versions are unique and in ascending order', () {
      final versions = kRoadmap.map((i) => i.version).toList();
      expect(versions.toSet().length, versions.length);
      final parsed = versions.map(parseVersion).toList();
      for (var i = 1; i < parsed.length; i++) {
        expect(
          isNewerVersion(versions[i], versions[i - 1]),
          isTrue,
          reason: '${versions[i]} should come after ${versions[i - 1]}',
        );
      }
    });

    test('next version is v0.5.0 Vulnerability Lab', () {
      expect(nextVersion, 'v0.5.0');
      expect(
        kRoadmap.firstWhere((i) => i.version == 'v0.5.0').title,
        contains('Vulnerability'),
      );
    });

    test('every item has features and a platform note', () {
      for (final item in kRoadmap) {
        expect(item.features, isNotEmpty);
        expect(item.platforms, isNotEmpty);
        expect(item.summary, isNotEmpty);
      }
    });
  });
}
