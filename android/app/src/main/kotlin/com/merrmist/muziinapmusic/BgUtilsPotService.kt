package com.merrmist.muziinapmusic

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.content.pm.ServiceInfo
import androidx.core.app.NotificationCompat
import java.util.concurrent.atomic.AtomicBoolean

class BgUtilsPotService : Service() {
    @Volatile private var serverProcess: Process? = null
    private val stopping = AtomicBoolean(false)
    private val channelId = "muziinap_bgutils_provider"
    private val notificationId = 73043

    override fun onCreate() {
        super.onCreate()
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(channelId, "YouTube PO Token Provider", NotificationManager.IMPORTANCE_LOW)
            )
        }
        val notification = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("MuziiNap PO Token Provider")
            .setContentText("Preparing the local YouTube attestation service")
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(notificationId, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(notificationId, notification)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopServer()
            stopSelf()
            return START_NOT_STICKY
        }
        Thread({
            try {
                BgUtilsRuntimeManager.prepareServer(this) { message -> updateNotification(message) }
                if (stopping.get()) return@Thread
                serverProcess?.destroy()
                serverProcess = BgUtilsRuntimeManager.launchServer(this)
                val deadline = System.currentTimeMillis() + 30_000
                while (!stopping.get() && System.currentTimeMillis() < deadline) {
                    if (BgUtilsRuntimeManager.isServerReady()) {
                        updateNotification("Ready • localhost:${BgUtilsRuntimeManager.PORT}")
                        while (!stopping.get() && serverProcess?.isAlive == true) Thread.sleep(1000)
                        break
                    }
                    if (serverProcess?.isAlive != true) {
                        throw IllegalStateException("BgUtils server exited before becoming ready.")
                    }
                    Thread.sleep(400)
                }
                check(BgUtilsRuntimeManager.isServerReady()) { "BgUtils server did not become ready." }
            } catch (error: Exception) {
                android.util.Log.e("MuziiNap-BgUtils", "Provider startup failed", error)
                updateNotification("Setup failed • open Settings to retry")
                stopSelf()
            }
        }, "MuziiNap-BgUtils-setup").start()
        return START_NOT_STICKY
    }

    private fun updateNotification(message: String) {
        val notification: Notification = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("MuziiNap PO Token Provider")
            .setContentText(message)
            .setOngoing(true)
            .build()
        getSystemService(NotificationManager::class.java).notify(notificationId, notification)
    }

    private fun stopServer() {
        stopping.set(true)
        serverProcess?.destroy()
        if (serverProcess?.isAlive == true) serverProcess?.destroyForcibly()
        serverProcess = null
    }

    override fun onDestroy() {
        stopServer()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        const val ACTION_STOP = "com.merrmist.muziinapmusic.BGUTILS_STOP"
    }
}
