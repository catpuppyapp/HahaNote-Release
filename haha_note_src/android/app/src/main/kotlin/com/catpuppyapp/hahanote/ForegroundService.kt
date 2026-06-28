package com.catpuppyapp.hahanote

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import com.catpuppyapp.hahanote.R

class ForegroundService : Service() {

    companion object {
        const val CHANNEL_ID = "foreground_service_channel"
        const val CHANNEL_NAME = "HahaNote Foreground Service"
        const val NOTIFICATION_ID = 1
        const val ACTION_STOP = "com.catpuppyapp.hahanote.ACTION_STOP_SERVICE"
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // 处理来自通知的停止动作
        if (intent?.action == ACTION_STOP) {
            stopForeground(true)
            stopSelf()
            return START_NOT_STICKY
        }

        val notification = buildNotification()
        // 对于 Android O+ 使用 startForegroundService() 启动后必须立即调用 startForeground()
        startForeground(NOTIFICATION_ID, notification)

        // 在此启动你的长期任务（线程、协程、handler、或调度器）
        // 示例：开启一个后台线程或协程去做工作

        return START_STICKY // 或根据需求使用 START_NOT_STICKY / START_REDELIVER_INTENT
    }

    override fun onDestroy() {
        // 清理资源
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun buildNotification(): Notification {
        // 点击通知回到应用
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            pendingIntentFlags()
        )

        // 通知上的停止操作
        val stopIntent = Intent(this, ForegroundService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPending = PendingIntent.getService(
            this,
            0,
            stopIntent,
            pendingIntentFlags()
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("HahaNote Running")
            .setContentText("Avoid app kill by OS")
            .setSmallIcon(R.drawable.noti_icon) // 替换为你的图标
            .setContentIntent(pendingIntent)
            .addAction(R.drawable.baseline_close_24, "Stop", stopPending) // 可选停止按钮
            .setOngoing(true)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val chan = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW // 低重要性避免打断用户
            )
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(chan)
        }
    }

    private fun pendingIntentFlags(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
    }
}
