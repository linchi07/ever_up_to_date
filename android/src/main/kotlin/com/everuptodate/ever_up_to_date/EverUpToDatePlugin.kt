package com.everuptodate.ever_up_to_date

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File

class EverUpToDatePlugin :
    FlutterPlugin,
    MethodCallHandler {
    private lateinit var channel: MethodChannel
    private var applicationContext: Context? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "ever_up_to_date")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result
    ) {
        val context = applicationContext
        if (context == null) {
            result.error("NO_CONTEXT", "Application context is null", null)
            return
        }

        when (call.method) {
            "installApk" -> {
                val filePath = call.argument<String>("filePath")
                if (filePath.isNullOrEmpty()) {
                    result.error("INVALID_ARGUMENT", "filePath is required", null)
                    return
                }

                try {
                    val file = File(filePath)
                    if (!file.exists()) {
                        result.error("FILE_NOT_FOUND", "APK file does not exist at $filePath", null)
                        return
                    }

                    val authority = "${context.packageName}.ever_up_to_date.fileprovider"
                    val contentUri = FileProvider.getUriForFile(context, authority, file)

                    val intent = Intent(Intent.ACTION_VIEW).apply {
                        setDataAndType(contentUri, "application/vnd.android.package-archive")
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
                    }

                    context.startActivity(intent)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("INSTALL_FAILED", e.localizedMessage, null)
                }
            }

            "canRequestPackageInstalls" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    result.success(context.packageManager.canRequestPackageInstalls())
                } else {
                    result.success(true)
                }
            }

            "openInstallPermissionSettings" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    try {
                        val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                            data = Uri.parse("package:${context.packageName}")
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        }
                        context.startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SETTINGS_FAILED", e.localizedMessage, null)
                    }
                } else {
                    result.success(true)
                }
            }

            else -> {
                result.notImplemented()
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        applicationContext = null
    }
}
