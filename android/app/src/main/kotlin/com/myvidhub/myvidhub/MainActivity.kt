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
    private val dolbyProbes = mutableSetOf<DolbyVisionProbe>()
    private lateinit var inlineHdrPlayer: InlineHdrPlayer

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        inlineHdrPlayer = InlineHdrPlayer(this)
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "myvidhub/inline_hdr_view", inlineHdrPlayer.viewFactory
        )
        io.flutter.plugin.common.EventChannel(
            flutterEngine.dartExecutor.binaryMessenger, "myvidhub/inline_hdr_events"
        ).setStreamHandler(inlineHdrPlayer)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "myvidhub/hdr_player")
            .setMethodCallHandler { call, result ->
                if (call.method.startsWith("inline")) {
                    inlineHdrPlayer.handle(call, result)
                    return@setMethodCallHandler
                }
                if (call.method == "probe") {
                    val url = call.argument<String>("url")
                    if (url.isNullOrBlank()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    lateinit var probe: DolbyVisionProbe
                    probe = DolbyVisionProbe(this, url, call.argument<String>("header")) { detected ->
                        dolbyProbes.remove(probe)
                        result.success(detected)
                    }
                    dolbyProbes.add(probe)
                    probe.start()
                    return@setMethodCallHandler
                }
                result.notImplemented()
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

    override fun onPause() {
        if (::inlineHdrPlayer.isInitialized) inlineHdrPlayer.onBackground()
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        if (::inlineHdrPlayer.isInitialized) inlineHdrPlayer.onForeground()
    }

    override fun onDestroy() {
        dolbyProbes.toList().forEach { it.finish() }
        if (::inlineHdrPlayer.isInitialized) inlineHdrPlayer.close()
        super.onDestroy()
    }

}
