/// True in-app update: download the new version and install it without
/// leaving the app.
///
/// Android: the APK is downloaded into the app cache, then the system
/// installer is opened through the `wihisar.app_update` platform channel
/// (see MainActivity.kt). Android always shows its own install screen and
/// asks once for "install unknown apps" — nothing installs silently.
///
/// Windows: the release zip is downloaded, extracted, and a small .bat
/// applies it: wait for the app to exit, copy the new files over the
/// install folder, restart the exe. The app exits itself after launching
/// the script.
///
/// iOS / macOS / Linux: there is no sideload install path from inside the
/// app, so the updater opens the release page instead (the old behaviour).
/// The UI says so honestly instead of pretending to install.
library;

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'app_update.dart';

class InAppUpdater {
  static const MethodChannel _channel = MethodChannel('wihisar.app_update');

  /// Download [url] to the app cache (`updates/<fileName>`), reporting
  /// progress. Returns the downloaded file. Throws on HTTP / I/O errors.
  Future<File> downloadFile(
    String url, {
    required String fileName,
    void Function(int received, int? total)? onProgress,
  }) async {
    final dir = await getTemporaryDirectory();
    final updateDir = Directory('${dir.path}/updates')
      ..createSync(recursive: true);
    final file = File('${updateDir.path}/$fileName');
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set('User-Agent', 'WiHisar/$kAppVersion');
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException(
          'Download failed: HTTP ${response.statusCode}',
        );
      }
      final total = response.contentLength;
      var received = 0;
      final sink = file.openWrite();
      await for (final chunk in response) {
        received += chunk.length;
        sink.add(chunk);
        onProgress?.call(received, total < 0 ? null : total);
      }
      await sink.close();
      return file;
    } finally {
      client.close();
    }
  }

  /// Open the Android system installer for a downloaded APK.
  /// Returns true when the installer opened.
  Future<bool> installApk(File apk) async {
    if (!Platform.isAndroid) return false;
    try {
      final ok = await _channel.invokeMethod<bool>(
        'installApk',
        {'path': apk.path},
      );
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Whether this app is allowed to install unknown apps (Android 8+).
  /// The system installer asks the user when this is false.
  Future<bool> canInstallUnknownApps() async {
    if (!Platform.isAndroid) return false;
    try {
      final ok = await _channel.invokeMethod<bool>(
        'canInstallUnknownApps',
      );
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }
}

/// Folder containing [exePath], splitting on `\` or `/`.
///
/// Deliberately a plain string operation, not `File(exePath).parent`:
/// the script is generated and unit-tested on Linux, where dart:io would
/// treat a Windows path as one filename and return `.`.
String windowsDirOf(String exePath) {
  final idx = exePath.lastIndexOf(RegExp(r'[\\/]'));
  return idx <= 0 ? exePath : exePath.substring(0, idx);
}

/// Build the Windows update script (pure — unit-tested).
///
/// The script waits 2 seconds for the app to exit, copies every extracted
/// file over the install folder, restarts the exe, and cleans up. It never
/// touches anything outside those two folders.
String buildWindowsUpdateScript({
  required String exePath,
  required String extractedDir,
}) {
  final exeDir = windowsDirOf(exePath);
  return '@echo off\r\n'
      'timeout /t 2 /nobreak >nul\r\n'
      'robocopy "$extractedDir" "$exeDir" /E /R:2 /W:1 >nul\r\n'
      'start "" "$exePath"\r\n'
      'rmdir /S /Q "$extractedDir"\r\n'
      'del "%~f0"\r\n';
}

/// Apply a downloaded Windows release zip: extract it, write the update
/// script, launch it detached, and exit so the script can replace the
/// running exe. This function does not return on success.
Future<void> applyWindowsUpdate({required File zipFile}) async {
  final bytes = await zipFile.readAsBytes();
  final archive = ZipDecoder().decodeBytes(bytes);
  final temp = await getTemporaryDirectory();
  final outDir = Directory('${temp.path}/wihisar-update')
    ..createSync(recursive: true);
  for (final entry in archive) {
    if (!entry.isFile) continue;
    final out = File('${outDir.path}/${entry.name}');
    out.parent.createSync(recursive: true);
    out.writeAsBytesSync(entry.content as List<int>);
  }
  final exePath = Platform.resolvedExecutable;
  final script = buildWindowsUpdateScript(
    exePath: exePath,
    extractedDir: outDir.path,
  );
  final bat = File('${temp.path}/wihisar-update.bat')
    ..writeAsStringSync(script);
  await Process.start(
    'cmd.exe',
    ['/c', 'start', '', bat.path],
    runInShell: true,
    mode: ProcessStartMode.detached,
  );
  exit(0);
}
