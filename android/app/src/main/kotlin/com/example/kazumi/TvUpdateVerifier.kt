package com.example.kazumi

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

/** Downstream updates are valid only for this package and its installed signer. */
object TvUpdateVerifier {
    @Suppress("DEPRECATION")
    fun handle(activity: Activity, call: MethodCall, result: MethodChannel.Result) {
        try {
            require(activity.packageName == "com.fenghaha.kazumitv") {
                "当前安装包不支持此电视更新渠道"
            }
            val pm = activity.packageManager
            when (call.method) {
                "getAppUpdateInfo" -> {
                    val info = pm.getPackageInfo(activity.packageName, 0)
                    result.success(mapOf(
                        "package" to activity.packageName,
                        "versionCode" to code(info),
                        "versionName" to (info.versionName ?: ""),
                        "abis" to Build.SUPPORTED_ABIS.toList(),
                        "sdk" to Build.VERSION.SDK_INT,
                    ))
                }
                "canInstallTvUpdate" -> result.success(
                    Build.VERSION.SDK_INT < 26 || pm.canRequestPackageInstalls()
                )
                "openTvUpdateInstallSettings" -> {
                    if (Build.VERSION.SDK_INT >= 26) {
                        activity.startActivity(Intent(
                            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                            Uri.parse("package:${activity.packageName}"),
                        ))
                    }
                    result.success(null)
                }
                "verifyTvUpdateApk" -> {
                    val path = call.argument<String>("path") ?: error("缺少安装包")
                    val expected = call.argument<Number>("versionCode")?.toLong()
                        ?: error("缺少安装版本")
                    val file = File(path).canonicalFile
                    require(file.isFile && file.path.startsWith(
                        activity.cacheDir.canonicalPath + File.separator
                    )) { "安装包不在本应用下载目录" }
                    val flags = if (Build.VERSION.SDK_INT >= 28)
                        PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
                    val current = pm.getPackageInfo(activity.packageName, flags)
                    val candidate = pm.getPackageArchiveInfo(file.path, flags)
                        ?: error("无法读取安装包")
                    require(candidate.packageName == activity.packageName) { "安装包应用标识不匹配" }
                    require(code(candidate) == expected && expected > code(current)) {
                        "安装版本不匹配或不是更新版本"
                    }
                    val installedSigners = signers(current)
                    val downloadedSigners = signers(candidate)
                    require(installedSigners.isNotEmpty() && installedSigners == downloadedSigners) {
                        "安装包签名与当前应用不一致"
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("TV_UPDATE_INVALID", e.message ?: "无法验证电视更新", null)
        }
    }

    @Suppress("DEPRECATION")
    private fun code(info: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()

    @Suppress("DEPRECATION")
    private fun signers(info: PackageInfo): Set<String> {
        val signatures = if (Build.VERSION.SDK_INT >= 28)
            info.signingInfo?.apkContentsSigners else info.signatures
        return signatures.orEmpty().map { signature ->
            MessageDigest.getInstance("SHA-256").digest(signature.toByteArray())
                .joinToString("") { "%02x".format(it) }
        }.toSet()
    }
}
