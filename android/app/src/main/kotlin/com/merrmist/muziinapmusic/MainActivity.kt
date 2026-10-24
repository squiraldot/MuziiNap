package com.merrmist.muziinapmusic

import android.content.Intent
import android.app.NotificationChannel
import android.app.NotificationManager
import androidx.core.app.NotificationCompat
import android.net.Uri
import android.media.audiofx.Visualizer
import android.util.Base64
import org.json.JSONObject
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.annotation.Keep
import com.ryanheise.audioservice.AudioServiceActivity
import com.ryanheise.just_audio.MuziiNapDspController
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.hypot

class MainActivity : AudioServiceActivity() {
    private val spectrumChannel = "muziinap/spectrum_analyzer"
    private val downloadNotificationChannel = "muziinap/download_notifications"
    private val downloadNotificationId = 73041
    // Prevent a delayed dismissal for one song from removing the next song's
    // notification when the queue advances quickly.
    private var downloadNotificationGeneration = 0
    private val presetShareChannel = "muziinap/preset_share"
    private val presetShareMethodChannel = "muziinap/preset_share_method"
    private var presetEventSink: EventChannel.EventSink? = null
    private var initialPreset: String? = null
    private val visualizers = ConcurrentHashMap<Int, Visualizer>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, presetShareChannel)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    presetEventSink = events
                    initialPreset?.let {
                        events?.success(it)
                        initialPreset = null
                    }
                }
                override fun onCancel(arguments: Any?) {
                    presetEventSink = null
                }
            })
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, presetShareMethodChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialPreset" -> result.success(initialPreset.also { initialPreset = null })
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "muziinap/pcm_dsp")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setConfig" -> {
                        val config = call.argument<String>("config")
                        if (config == null) {
                            result.error("invalid_config", "Missing EQ config JSON", null)
                        } else {
                            try {
                                MuziiNapDspController.updateConfig(config)
                                result.success(true)
                            } catch (error: Exception) {
                                result.error("invalid_config", error.message, null)
                            }
                        }
                    }
                    "getProcessingDurationNs" -> result.success(MuziiNapDspController.processingDurationNs())
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "muziinap/home_lyrics_widget")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "updateLines" -> {
                        LyricsHomeWidgetProvider.updateLines(
                            this,
                            call.argument<String>("previous").orEmpty(),
                            call.argument<String>("current").orEmpty(),
                            call.argument<String>("next").orEmpty(),
                            call.argument<Int>("activeIndex") ?: -1
                        )
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        handlePresetIntent(intent)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, downloadNotificationChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "update" -> {
                        showDownloadNotification(
                            title = call.argument<String>("title") ?: "Downloading music",
                            message = call.argument<String>("message") ?: "",
                            progress = call.argument<Int>("progress") ?: 0,
                            ongoing = call.argument<Boolean>("ongoing") ?: true,
                            complete = call.argument<Boolean>("complete") ?: false
                        )
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, spectrumChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        val sessionId = call.argument<Int>("sessionId") ?: 0
                        val captureSize = call.argument<Int>("captureSize") ?: 1024
                        result.success(startVisualizer(sessionId, captureSize))
                    }
                    "getFft" -> {
                        val data = readSpectrum()
                        if (data == null) {
                            result.success(null)
                        } else {
                            result.success(data)
                        }
                    }
                    "stop" -> {
                        stopVisualizer()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun showDownloadNotification(
        title: String,
        message: String,
        progress: Int,
        ongoing: Boolean,
        complete: Boolean
    ) {
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 73042)
            return
        }
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        val channelId = "muziinap_downloads"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(channelId, "Music downloads", NotificationManager.IMPORTANCE_LOW)
            )
        }
        val builder = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(message)
            .setOnlyAlertOnce(true)
            .setOngoing(ongoing)
            .setAutoCancel(complete)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
        if (complete) {
            builder.setProgress(0, 0, false)
                .setContentText("$message • Saved offline")
        } else if (title == "Download failed") {
            builder.setProgress(0, 0, false)
                .setCategory(NotificationCompat.CATEGORY_ERROR)
        } else {
            builder.setProgress(100, progress.coerceIn(0, 100), false)
        }
        val generation = ++downloadNotificationGeneration
        try {
            manager.notify(downloadNotificationId, builder.build())
            if (complete) {
                // Keep the completion state visible briefly, then remove it.
                // A newer download update increments the generation and cancels
                // this pending dismissal implicitly.
                Handler(Looper.getMainLooper()).postDelayed({
                    if (generation == downloadNotificationGeneration) {
                        manager.cancel(downloadNotificationId)
                    }
                }, 4_000L)
            }
        } catch (_: SecurityException) {
            // Android 13+ may block notifications until the user grants permission.
        }
    }

    private fun startVisualizer(sessionId: Int, requestedCaptureSize: Int): Boolean {
        if (sessionId <= 0) return false
        stopVisualizer()
        return try {
            val visualizer = Visualizer(sessionId)
            val range = Visualizer.getCaptureSizeRange()
            val requested = requestedCaptureSize
                .coerceAtLeast(range[0])
                .coerceAtMost(range[1])
            val captureSize = Integer.highestOneBit(requested)
                .coerceIn(range[0], range[1])
            visualizer.setCaptureSize(captureSize)
            visualizer.setScalingMode(Visualizer.SCALING_MODE_NORMALIZED)
            visualizer.enabled = true
            visualizers[sessionId] = visualizer
            true
        } catch (_: SecurityException) {
            false
        } catch (_: RuntimeException) {
            false
        } catch (_: UnsupportedOperationException) {
            false
        }
    }

    private fun readSpectrum(): Map<String, Any>? {
        val visualizer = visualizers.values.firstOrNull() ?: return null
        return try {
            if (!visualizer.enabled) return null
            val fft = ByteArray(visualizer.captureSize)
            if (visualizer.getFft(fft) != Visualizer.SUCCESS) return null

            val magnitudes = ArrayList<Double>(fft.size / 2 + 1)
            magnitudes.add(kotlin.math.abs(fft[0].toInt()).toDouble())
            for (index in 1 until fft.size / 2) {
                val real = fft[index * 2].toInt()
                val imaginary = fft[index * 2 + 1].toInt()
                magnitudes.add(hypot(real.toDouble(), imaginary.toDouble()))
            }
            magnitudes.add(kotlin.math.abs(fft[1].toInt()).toDouble())

            mapOf(
                "magnitudes" to magnitudes,
                "sampleRateHz" to visualizer.samplingRate / 1000,
                "captureSize" to visualizer.captureSize
            )
        } catch (_: IllegalStateException) {
            null
        } catch (_: RuntimeException) {
            null
        }
    }

    private fun stopVisualizer() {
        val current = visualizers.values.toList()
        visualizers.clear()
        current.forEach { visualizer ->
            try {
                visualizer.enabled = false
            } catch (_: RuntimeException) {
            }
            try {
                visualizer.release()
            } catch (_: RuntimeException) {
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handlePresetIntent(intent)
    }

    private fun handlePresetIntent(intent: Intent?) {
        if (intent == null) return
        val action = intent.action ?: return
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_VIEW) return
        val uri = when (action) {
            Intent.ACTION_SEND -> intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
            else -> intent.data
        } ?: return
        try {
            val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() } ?: return
            // Telegram and other apps may share .mneq files as application/octet-stream.
            // Validate the preset signature instead of relying on the incoming MIME type.
            val source = bytes.toString(Charsets.UTF_8)
            if (JSONObject(source).optString("format") != "muziinap-eq") return
            val content = Base64.encodeToString(bytes, Base64.NO_WRAP)
            val payload = "base64:" + content
            if (presetEventSink != null) {
                presetEventSink?.success(payload)
            } else {
                initialPreset = payload
            }
        } catch (_: Exception) {
            // Invalid/unreadable shared files are ignored; Flutter can show errors for decoded payloads.
        }
    }

    override fun onDestroy() {
        stopVisualizer()
        super.onDestroy()
    }
}
