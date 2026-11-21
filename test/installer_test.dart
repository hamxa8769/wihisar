import 'package:flutter_test/flutter_test.dart';
import 'package:wihisar/update/installer.dart';

void main() {
  group('buildWindowsUpdateScript', () {
    test('copies the extracted files over the install folder and restarts', () {
      final script = buildWindowsUpdateScript(
        exePath: r'C:\WiHisar\wihisar.exe',
        extractedDir: r'C:\Users\test\AppData\Local\Temp\wihisar-update',
      );
      expect(script, contains('robocopy'));
      expect(
        script,
        contains(r'"C:\Users\test\AppData\Local\Temp\wihisar-update"'),
      );
      expect(script, contains(r'"C:\WiHisar"'));
      expect(script, contains(r'start "" "C:\WiHisar\wihisar.exe"'));
      // It waits for the running app to exit first.
      expect(script, contains('timeout /t 2'));
      // And cleans up after itself.
      expect(script, contains('rmdir /S /Q'));
    });

    test('derives the install folder from the exe path', () {
      final script = buildWindowsUpdateScript(
        exePath: r'D:\Apps\WiHisar\wihisar.exe',
        extractedDir: r'C:\Temp\wihisar-update',
      );
      expect(script, contains(r'"D:\Apps\WiHisar"'));
      expect(script, contains(r'"D:\Apps\WiHisar\wihisar.exe"'));
    });

    test('never touches anything outside the two folders', () {
      final script = buildWindowsUpdateScript(
        exePath: r'C:\WiHisar\wihisar.exe',
        extractedDir: r'C:\Temp\wihisar-update',
      );
      expect(script, isNot(contains('del C:')));
      expect(script, isNot(contains('format')));
    });
  });
}
