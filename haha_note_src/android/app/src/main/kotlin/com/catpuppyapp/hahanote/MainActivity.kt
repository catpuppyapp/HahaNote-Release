package com.catpuppyapp.hahanote

import android.annotation.TargetApi
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
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
            } else if (call.method == "getExternalStorageRootPath") {
                result.success(getExternalStorageRootPath())
            } else if (call.method == "getExternalDataFilesDirPath") {
                result.success(getExternalDataFilesDirPath(applicationContext))
            } else if (call.method == "getInnerDataFilesDirPath") {
                result.success(getInnerDataFilesDirPath(applicationContext))
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
                    // 这个ACTION不要用ACTION_EDIT，个人经验，用ACTION_VIEW+URI写权限兼容性更好
                    // 若用ACTION_EDIT，可能会启动程序的特定Activity，
                    // 比如你想预览图片，若用ACTION_EDIT可能会启动程序用来编辑图片的Activity
                    val intent = Intent(Intent.ACTION_VIEW).apply {
                        setDataAndType(uri, mime)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        // 可能有部分程序会判断，若uri有写权限，
                        // 进入编辑模式，否则进入预览模式，
                        // 若有必要，可仅在mime为text类型时，再加写权限
                        // 不过根据我的经验，没必要，相比之下ACTIVE用VIEW更重要些，
                        // 多数程序都是根据ACTION_VIEW或ACTION_EDIT来判断是期望预览文件还是编辑文件，
                        // 然后启动对应模式的，用uri是否有写权限来判断的比较少
                        addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                        // 否则可能不会启动 activity?？
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }

                    // 兼容Markor，对别的软件也没冲突，所以统一设置上了
                    intent.putExtra("EXTRA_FILEPATH", file.canonicalPath);

                    // 由于本软件是笔记软件，内置的包名都是文本编辑器，只支持编辑文本类型，
                    // 所以只有text类型才指定打开程序，非text类型一律使用系统默认程序打开（弹对应mime的程序选择器）
                    // 若不判断mime类型是否text，则会错误使用文本编辑器的包名打开非文本文件，
                    // 例如：若不判断mime是否是text，就会在包名是PuppyGit，文件是视频类型时，错误地使用PuppyGit打开视频文件
                    if(mime.startsWith("text/")
                        && packageName != null
                        && packageName.isNotEmpty()
                        && packageName != "SYSTEM"
                    ) {
                        // 若包名非SYSTEM，则设置上，将使用指定程序打开文件；
                        // 否则不设置，将使用系统默认程序打开 （弹对应mime的程序选择器，
                        // 当mime是text时，则弹出可用的文本编辑器供用户选择）
                        intent.setPackage(packageName)
                    }

                    startActivity(intent)
                    result.success(null)

                } catch (e: Exception) {
                    result.error("OPEN_ERR", e.localizedMessage, null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    /**
     * find a supported text editor to open file
     */
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

    /**
     * @return "/storage/emulated/0" or "" if has exception
     *
     */
    fun getExternalStorageRootPath():String{
        return try {
            Environment.getExternalStorageDirectory().canonicalPath
        }catch (_:Exception) {
            ""
        }
    }

    @TargetApi(Build.VERSION_CODES.FROYO)
    fun getExternalDataFilesDirPath(context: Context):String {
        return try {
            val dir = context.getExternalFilesDir(null) ?: throw RuntimeException("`context.getExternalFilesDir(null)` returned `null`")
            if(!dir.exists()) {
                dir.mkdirs()
            }

            dir.canonicalPath ?: ""
        }catch (e:Exception) {
            e.printStackTrace()

            ""
        }
    }

    @TargetApi(Build.VERSION_CODES.N)
    fun getInnerDataFilesDirPath(context: Context):String {
        return try {
            val filesDir = File(context.dataDir.canonicalPath, "files")
            if(!filesDir.exists()) {
                filesDir.mkdirs()
            }

            filesDir.canonicalPath
        }catch (e: Exception) {
            e.printStackTrace()

            ""
        }
    }

}
