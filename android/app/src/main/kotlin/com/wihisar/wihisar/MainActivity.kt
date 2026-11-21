package com.wihisar.wihisar

import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/// In-app update installer.
///
/// Dart downloads the new APK into the app cache, then calls `installApk`
/// on this channel. Android opens the system installer for that APK — the
/// user sees one system prompt ("Allow installing this app?") the first
/// time, then the normal install screen. Nothing installs silently: the
/// system installer is always the one that installs.
class MainActivity : FlutterActivity() {
    private val channelName = "wihisar.app_update"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "installApk" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank()) {
                        result.error("NO_PATH", "APK path is missing", null)
                        return@setMethodCallHandler
                    }
                    result.success(installApk(File(path)))
                }
                "canInstallUnknownApps" -> {
                    // Android 8+: whether this app may install unknown apps.
                    // The system installer asks the user when it is off.
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        result.success(packageManager.canRequestPackageInstalls())
                    } else {
                        result.success(true)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun installApk(apk: File): Boolean {
        return try {
            val uri: Uri = FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                apk,
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }
}
