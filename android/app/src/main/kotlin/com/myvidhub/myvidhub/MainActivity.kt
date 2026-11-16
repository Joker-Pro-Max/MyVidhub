package com.myvidhub.myvidhub

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var hdrResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "myvidhub/hdr_player")
            .setMethodCallHandler { call, result ->
                if (call.method != "play") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val url = call.argument<String>("url")
                if (url.isNullOrEmpty()) {
                    result.error("ARG", "missing video URL", null)
                    return@setMethodCallHandler
                }
                if (hdrResult != null) {
                    result.error("BUSY", "播放器已打开", null)
                    return@setMethodCallHandler
                }
                try {
                    val intent = Intent(this, HdrPlayerActivity::class.java)
                        .putExtra("url", url)
                        .putExtra("title", call.argument<String>("title"))
                        .putExtra("header", call.argument<String>("header"))
                        .putStringArrayListExtra(
                            "subtitles",
                            ArrayList(call.argument<List<String>>("subtitles") ?: emptyList())
                        )
                        .putExtra("position", (call.argument<Number>("position") ?: 0).toLong())
                    hdrResult = result
                    @Suppress("DEPRECATION")
                    startActivityForResult(intent, HDR_PLAYER_REQUEST)
                } catch (e: Exception) {
                    hdrResult = null
                    result.error("START_FAILED", e.message, null)
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "myvidhub/installer")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // 设备首选 ABI，用来挑选对应的安装包
                    "abi" -> result.success(Build.SUPPORTED_ABIS.firstOrNull() ?: "arm64-v8a")

                    // Android 8+ 需要用户允许本应用"安装未知应用"
                    "canInstall" -> result.success(
                        Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                            packageManager.canRequestPackageInstalls()
                    )

                    "openInstallSettings" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startActivity(
                                Intent(
                                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                    Uri.parse("package:$packageName")
                                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            )
                        }
                        result.success(null)
                    }

                    "install" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("ARG", "missing path", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val uri = FileProvider.getUriForFile(
                                this, "$packageName.updates", File(path)
                            )
                            val intent = Intent(Intent.ACTION_VIEW)
                                .setDataAndType(uri, "application/vnd.android.package-archive")
                                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("INSTALL", e.message, null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    @Deprecated("Android activity result callback")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != HDR_PLAYER_REQUEST) return
        val pending = hdrResult
        hdrResult = null
        if (data == null) {
            pending?.success(null)
        } else {
            pending?.success(
                mapOf(
                    "position" to data.getLongExtra("position", 0),
                    "duration" to data.getLongExtra("duration", 0),
                    "finished" to data.getBooleanExtra("finished", false)
                )
            )
        }
    }

    companion object {
        private const val HDR_PLAYER_REQUEST = 4187
    }
}
