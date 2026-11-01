package com.merrmist.muziinapmusic

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.widget.Toast
import androidx.core.app.NotificationCompat

internal object BgUtilsDownloadNotifications {
    private const val CHANNEL_ID = "muziinap_node_runtime_download"
    private const val NOTIFICATION_ID = 73044

    private fun manager(context: Context): NotificationManager {
        val manager = context.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Node.js Runtime Download", NotificationManager.IMPORTANCE_LOW)
            )
        }
        return manager
    }

    fun begin(context: Context) {
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Downloading Node.js runtime")
            .setContentText("Preparing secure download…")
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setProgress(0, 0, true)
            .build()
        manager(context).notify(NOTIFICATION_ID, notification)
    }

    fun update(context: Context, downloaded: Long, total: Long) {
        val knownTotal = total > 0
        val progress = if (knownTotal) ((downloaded * 100) / total).toInt().coerceIn(0, 100) else 0
        val downloadedMb = downloaded / (1024 * 1024)
        val totalText = if (knownTotal) " / ${total / (1024 * 1024)} MB" else ""
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Downloading Node.js runtime")
            .setContentText("$downloadedMb MB$totalText")
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setProgress(100, progress, !knownTotal)
            .build()
        manager(context).notify(NOTIFICATION_ID, notification)
    }

    fun success(context: Context) {
        manager(context).cancel(NOTIFICATION_ID)
        Toast.makeText(context, "Node.js runtime downloaded successfully", Toast.LENGTH_LONG).show()
    }

    fun failure(context: Context) {
        manager(context).cancel(NOTIFICATION_ID)
    }
}
