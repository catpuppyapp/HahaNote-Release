package com.catpuppyapp.hahanote

import android.annotation.TargetApi
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.widget.Toast
import androidx.core.content.FileProvider
import com.catpuppyapp.hahanote.BuildConfig
import com.catpuppyapp.hahanote.utils.mime.MimeType
import com.catpuppyapp.hahanote.utils.mime.guessFromFileName
import com.catpuppyapp.hahanote.utils.mime.intentType
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity: FlutterActivity() {
    private val CHANNEL = "app/channel"

    @TargetApi(Build.VERSION_CODES.DONUT)
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            // don't forget set result
            if (call.method == "moveToBackground") {
                // true is nonRoot, if false,
                // only move task to back when the Activity is root,
                // else work for any Activity
                moveTaskToBack(true)
                result.success(null)
            } else if (call.method == "startForegroundService") {
                try {
                    doStartForegroundService()
                    result.success(null)
                }catch (e: Exception) {
                    result.error("ERR", e.localizedMessage, null)
                }
            } else if (call.method == "stopForegroundService") {
                try {
                    doStopForegroundService()
                    result.success(null)
                }catch (e: Exception) {
                    result.error("ERR", e.localizedMessage, null)
                }
            } else if (call.method == "showMsg") {
                val msg = call.argument<String>("msg")
                val longDuration = call.argument<Boolean>("longDuration") == true

                Toast.makeText(context, msg, if(longDuration) Toast.LENGTH_LONG else Toast.LENGTH_SHORT).show();
                result.success(null)
            } else if (call.method == "showDisableBatteryOptimizationSettings") {
                val packageName: String? = call.argument<String>("packageName")
                if(packageName.isNullOrBlank()) {
                    result.error("INVALID_PACKAGE", packageName, null)
                }else {
                    showDisableBatteryOptimizationSettings(packageName, result)
                }
            } else if (call.method == "isAlreadyDisabledBatteryOptimization") {
                val packageName: String? = call.argument<String>("packageName")
                if(packageName.isNullOrBlank()) {
                    result.error("INVALID_PACKAGE", packageName, null)
                }else {
                    result.success(isAlreadyDisabledBatteryOptimization(packageName))
                }
            } else if (call.method == "openFileWithApp") {
                val path = call.argument<String>("path")
                var mime = call.argument<String>("mime")
                val packageName = call.argument<String>("packageName") // 可选
                if (path.isNullOrEmpty()) {
                    result.error("ARG_ERR","path missing", null)
                    return@setMethodCallHandler
                }

                val file = File(path)
                if (!file.exists()) {
                    result.error("NO_FILE","file not found", null)
                    return@setMethodCallHandler
                }


                try {
                    if(mime.isNullOrEmpty()) {
                        mime = MimeType.guessFromFileName(file.name).intentType
                    }

                    // authority 必须和 Manifest file provider配置写的一样
                    val authority = BuildConfig.FILE_PROVIDIER_AUTHORITY
                    val uri = FileProvider.getUriForFile(this, authority, file)

                    // 基本 intent
                    val intent = Intent(Intent.ACTION_VIEW).apply {
                        setDataAndType(uri, mime)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                        // 否则可能不会启动 activity?？
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }

                    // 兼容Markor，对别的软件也没冲突，所以统一设置上了
                    intent.putExtra("EXTRA_FILEPATH", file.canonicalPath);

                    if(mime.startsWith("text/")) {
                        if (!packageName.isNullOrEmpty()) {
                            // 如果调用者指定了包名，不需要我去尝试查找一个包名打开文件了，直接用该包打开
                            intent.setPackage(packageName)
                            startActivity(intent)
                            result.success(null)
                        }else {
                            // 调用者未指定包名，若是文本文件，则尝试找一个支持的编辑器打开文件
                            findEditorToOpenFile(intent, result);
                        }
                    }else {
                        // 非文本文件
                        startActivity(intent)
                        result.success(null)
                    }

                } catch (e: Exception) {
                    result.error("OPEN_ERR", e.localizedMessage, null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    @TargetApi(Build.VERSION_CODES.DONUT)
    private fun findEditorToOpenFile(intent: Intent, result: MethodChannel.Result) {
        var err: Exception? = null;

        try {
            intent.setPackage("net.gsantner.markor");
            startActivity(intent)
            result.success(null)
            return;
        }catch (e: Exception) {
            err = e;
        }


        try {
            intent.setPackage("com.catpuppyapp.puppygit.play.pro");
            startActivity(intent)
            result.success(null)
            return;
        }catch (e: Exception) {
            err = e;
        }


        try {
            intent.setPackage("com.blacksquircle.ui");
            startActivity(intent)
            result.success(null)
            return;
        }catch (e: Exception) {
            err = e;
        }


        try {
            intent.setPackage("com.rhmsoft.edit.pro");
            startActivity(intent)
            result.success(null)
            return;
        }catch (e: Exception) {
            err = e;
        }


        try {
            intent.setPackage("com.rhmsoft.edit");
            startActivity(intent)
            result.success(null)
            return;
        }catch (e: Exception) {
            err = e;
        }


        try {
            intent.setPackage("com.foxdebug.acode");
            startActivity(intent)
            result.success(null)
            return;
        }catch (e: Exception) {
            err = e;
        }


        try {
            intent.setPackage("com.foxdebug.acodefree");
            startActivity(intent)
            result.success(null)
            return;
        }catch (e: Exception) {
            err = e;
        }

        // 若执行到这还没返回，说明有异常
        result.error("EDITOR_NOT_FOUND", err.localizedMessage, null)
    }

    @TargetApi(Build.VERSION_CODES.M)
    private fun isAlreadyDisabledBatteryOptimization(packageName: String) : Boolean {
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        return powerManager.isIgnoringBatteryOptimizations(packageName)
    }

    @TargetApi(Build.VERSION_CODES.M)
    private fun showDisableBatteryOptimizationSettings(packageName: String, result: MethodChannel.Result) {
        try {
            if(isAlreadyDisabledBatteryOptimization(packageName)) {
                result.success(null)
                return
            }


            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
            intent.data = Uri.parse("package:$packageName")

            startActivity(intent)
            result.success(null)
        }catch (e: Exception) {
            result.error("SHOW_DISABLE_BATTERY_OPTIMIZATION_ERR", e.localizedMessage, null)
        }
    }

    /**
     * 用户需要在列表中手动找到你的 App。然后禁用电池优化，不过更符合google play商店政策（鸟商店）
     */
//    @TargetApi(Build.VERSION_CODES.M)
//    private fun showDisableBatteryOptimizationSettingsList(result: MethodChannel.Result) {
//        try {
//            val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
//            startActivity(intent)
//        }catch (e: Exception) {
//            result.error("SHOW_DISABLE_BATTERY_OPTIMIZATION_LIST_ERR", e.localizedMessage, null)
//        }
//    }

    private fun doStartForegroundService() {
        val svcIntent = Intent(this, ForegroundService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(svcIntent)
        } else {
            startService(svcIntent)
        }
    }

    private fun doStopForegroundService() {
        val stopIntent = Intent(this, ForegroundService::class.java)
        stopService(stopIntent)
    }
}
