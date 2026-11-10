package com.example.plan_zajec_uek

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Executors

class UpdateFileProvider : FileProvider()

@Suppress("DEPRECATION")
class AppUpdateBridge(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "uek_plan/app_updates")
    private val worker = Executors.newSingleThreadExecutor()
    private val directory get() = File(activity.cacheDir, "updates")
    private val signatureFlags get() = if (Build.VERSION.SDK_INT >= 28) {
        PackageManager.GET_SIGNING_CERTIFICATES
    } else {
        PackageManager.GET_SIGNATURES
    }

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "installedApp" -> {
                    val info = installed()
                    result.success(mapOf("version" to info.versionName,
                        "build" to versionCode(info), "packageName" to info.packageName,
                        "abi" to Build.SUPPORTED_ABIS.firstOrNull {
                            it in setOf("arm64-v8a", "armeabi-v7a", "x86_64")
                        }))
                }
                "downloadDirectory" -> result.success(directory.absolutePath)
                "verifyUpdate", "installUpdate" -> worker.execute {
                    try {
                        val file = verifiedFile(call)
                        activity.runOnUiThread {
                            try {
                                if (call.method == "installUpdate") result.success(install(file))
                                else result.success(null)
                            } catch (e: Exception) {
                                result.error("INSTALL_FAILED", "Nie można otworzyć instalatora Androida.", null)
                            }
                        }
                    } catch (e: Exception) {
                        activity.runOnUiThread {
                            result.error("INVALID_UPDATE", e.message ?: "Nieprawidłowy instalator.", null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun installed(): PackageInfo =
        activity.packageManager.getPackageInfo(activity.packageName, signatureFlags)

    private fun versionCode(info: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()

    private fun signatures(info: PackageInfo): Set<String> {
        val signatures = if (Build.VERSION.SDK_INT >= 28) {
            info.signingInfo?.apkContentsSigners
        } else info.signatures
        return signatures.orEmpty().map {
            MessageDigest.getInstance("SHA-256").digest(it.toByteArray())
                .joinToString("") { byte -> "%02x".format(byte) }
        }.toSet()
    }

    private fun verifiedFile(call: MethodCall): File {
        val path = call.argument<String>("path") ?: error("Brak pliku aktualizacji.")
        val file = File(path).canonicalFile
        require(file == File(directory, "update.apk").canonicalFile && file.isFile) {
            "Nieprawidłowa lokalizacja instalatora. Pobierz aktualizację ponownie."
        }
        val apk = activity.packageManager.getPackageArchiveInfo(file.path, signatureFlags)
            ?: error("Nie można odczytać instalatora.")
        val current = installed()
        require(apk.packageName == current.packageName) { "Instalator dotyczy innej aplikacji." }
        require(versionCode(apk) == call.argument<Number>("build")?.toLong() &&
            apk.versionName == call.argument<String>("version") && versionCode(apk) > versionCode(current)) {
            "Instalator nie jest oczekiwaną, nowszą wersją aplikacji."
        }
        val expectedSignatures = signatures(current)
        require(expectedSignatures.isNotEmpty() && signatures(apk) == expectedSignatures) {
            "Podpis instalatora nie zgadza się z zainstalowaną aplikacją."
        }
        return file
    }

    private fun install(file: File): Boolean {
        if (Build.VERSION.SDK_INT >= 26 && !activity.packageManager.canRequestPackageInstalls()) {
            activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:${activity.packageName}")))
            return false
        }
        val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.updates", file)
        activity.startActivity(Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        })
        return true
    }

    fun close() {
        channel.setMethodCallHandler(null)
        worker.shutdown()
    }
}
