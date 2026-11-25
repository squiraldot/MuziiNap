package com.merrmist.muziinapmusic

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.net.Uri
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import android.view.KeyEvent
import android.view.View
import android.widget.RemoteViews
import java.util.concurrent.ConcurrentHashMap

/** Fixed-size Android adapters delegate all behavior to one shared renderer. */
abstract class ThemeMusicWidgetProvider : AppWidgetProvider() {
    internal abstract val widgetLayout: Int
    internal abstract val widgetFolder: String

    override fun onUpdate(context: Context, manager: AppWidgetManager, appWidgetIds: IntArray) {
        appWidgetIds.forEach { id ->
            if (ThemeMusicWidgetRenderer.assetsAvailable(context, id, widgetFolder) &&
                ThemeWidgetRegistry.registerWidget(context, id, javaClass.name)) {
                ThemeMusicWidgetRenderer.render(context, manager, id, widgetLayout, widgetFolder)
            } else {
                ThemeMusicWidgetRenderer.renderUnavailable(context, manager, id, widgetLayout)
            }
        }
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        ThemeWidgetRegistry.unregisterWidget(context, appWidgetIds)
        ThemeMusicWidgetRenderer.releaseUnusedAssets(context)
        super.onDeleted(context, appWidgetIds)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context, manager: AppWidgetManager, appWidgetId: Int, newOptions: android.os.Bundle
    ) {
        if (ThemeMusicWidgetRenderer.assetsAvailable(context, appWidgetId, widgetFolder) &&
            ThemeWidgetRegistry.registerWidget(context, appWidgetId, javaClass.name)) {
            ThemeMusicWidgetRenderer.render(context, manager, appWidgetId, widgetLayout, widgetFolder)
        } else {
            ThemeMusicWidgetRenderer.renderUnavailable(context, manager, appWidgetId, widgetLayout)
        }
        super.onAppWidgetOptionsChanged(context, manager, appWidgetId, newOptions)
    }
}

class MusicThemeWidget4x2Provider : ThemeMusicWidgetProvider() {
    override val widgetLayout: Int = R.layout.music_theme_widget
    override val widgetFolder: String = "4x2"
}

class MusicThemeWidget4x3Provider : ThemeMusicWidgetProvider() {
    override val widgetLayout: Int = R.layout.music_theme_widget
    override val widgetFolder: String = "4x3"
}

internal object ThemeMusicWidgetRenderer {
    private const val TAG = "MuziiNapThemeWidget"
    private const val ASSET_DIRECTORY = "assets/widget_assets/Dragon_Ball_Z"
    private const val MAX_DECODED_EDGE_PX = 256
    private val bitmapCache = ConcurrentHashMap<String, Bitmap>()

    fun render(
        context: Context,
        manager: AppWidgetManager,
        widgetId: Int,
        layoutId: Int,
        widgetFolder: String
    ) {
        val state = ThemeWidgetRegistry.playbackState(context)
        val views = RemoteViews(context.packageName, layoutId)
        views.setTextViewText(R.id.music_theme_widget_title, state.title)
        views.setTextViewText(R.id.music_theme_widget_artist, state.artist)
        views.setImageViewResource(
            R.id.music_theme_widget_play_pause,
            if (state.isPlaying) android.R.drawable.ic_media_pause
            else android.R.drawable.ic_media_play
        )
        setAsset(context, views, widgetId, R.id.music_theme_widget_background, widgetFolder, "Background.png")
        setAsset(context, views, widgetId, R.id.music_theme_widget_border, widgetFolder, "Border.png")
        setAsset(context, views, widgetId, R.id.music_theme_widget_character, widgetFolder, "Character.png")

        val progress = if (state.durationMs > 0L) {
            ((state.positionMs.coerceIn(0L, state.durationMs) * 1000L) / state.durationMs).toInt()
        } else 0
        views.setProgressBar(R.id.music_theme_widget_progress, 1000, progress, false)
        views.setViewVisibility(R.id.music_theme_widget_progress,
            if (state.durationMs > 0L) View.VISIBLE else View.GONE)
        views.setFloat(R.id.music_theme_widget_shuffle, "setAlpha", if (state.shuffleEnabled) 1f else 0.45f)
        views.setFloat(R.id.music_theme_widget_repeat, "setAlpha", if (state.repeatMode == "OFF") 0.45f else 1f)
        views.setContentDescription(R.id.music_theme_widget_repeat, "Repeat ${state.repeatMode.lowercase()}")
        views.setOnClickPendingIntent(R.id.music_theme_widget_root, launchPendingIntent(context, widgetId))
        views.setOnClickPendingIntent(R.id.music_theme_widget_previous,
            actionPendingIntent(context, widgetId, ThemeWidgetActionReceiver.COMMAND_PREVIOUS, 1))
        views.setOnClickPendingIntent(R.id.music_theme_widget_play_pause,
            actionPendingIntent(context, widgetId, ThemeWidgetActionReceiver.COMMAND_PLAY_PAUSE, 2))
        views.setOnClickPendingIntent(R.id.music_theme_widget_next,
            actionPendingIntent(context, widgetId, ThemeWidgetActionReceiver.COMMAND_NEXT, 3))
        views.setOnClickPendingIntent(R.id.music_theme_widget_shuffle,
            actionPendingIntent(context, widgetId, ThemeWidgetActionReceiver.COMMAND_SHUFFLE, 4))
        views.setOnClickPendingIntent(R.id.music_theme_widget_repeat,
            actionPendingIntent(context, widgetId, ThemeWidgetActionReceiver.COMMAND_REPEAT, 5))
        manager.updateAppWidget(widgetId, views)
    }

    fun releaseUnusedAssets(context: Context) {
        if (ThemeWidgetRegistry.registeredWidgets(context).isEmpty()) {
            bitmapCache.clear()
        }
    }

    fun assetsAvailable(context: Context, widgetId: Int, widgetFolder: String): Boolean {
        val registration = ThemeWidgetRegistry.registeredWidget(context, widgetId)
        val themeId = registration?.themeId ?: "dragon-ball-z"
        val designId = registration?.designId ?: "widget-1"
        return ThemeWidgetAssetPath.assetsAvailable(context, themeId, designId, widgetFolder)
    }

    fun renderUnavailable(
        context: Context, manager: AppWidgetManager, widgetId: Int, layoutId: Int
    ) {
        val views = RemoteViews(context.packageName, layoutId).apply {
            setTextViewText(R.id.music_theme_widget_title, "Theme assets unavailable")
            setTextViewText(R.id.music_theme_widget_artist, "Remove this widget and choose an available design")
            setViewVisibility(R.id.music_theme_widget_previous, View.GONE)
            setViewVisibility(R.id.music_theme_widget_play_pause, View.GONE)
            setViewVisibility(R.id.music_theme_widget_next, View.GONE)
            setViewVisibility(R.id.music_theme_widget_shuffle, View.GONE)
            setViewVisibility(R.id.music_theme_widget_repeat, View.GONE)
            setViewVisibility(R.id.music_theme_widget_progress, View.GONE)
        }
        manager.updateAppWidget(widgetId, views)
    }

    /** Android's AppWidgetManager cannot delete host-owned widget IDs; show a clear cap message instead. */
    fun renderLimitReached(
        context: Context, manager: AppWidgetManager, widgetId: Int, layoutId: Int
    ) {
        val views = RemoteViews(context.packageName, layoutId).apply {
            setTextViewText(R.id.music_theme_widget_title, "Widget limit reached")
            setTextViewText(
                R.id.music_theme_widget_artist,
                "Remove a theme widget to add this one"
            )
            setViewVisibility(R.id.music_theme_widget_previous, View.GONE)
            setViewVisibility(R.id.music_theme_widget_play_pause, View.GONE)
            setViewVisibility(R.id.music_theme_widget_next, View.GONE)
        }
        manager.updateAppWidget(widgetId, views)
    }

    private fun setAsset(
        context: Context,
        views: RemoteViews,
        widgetId: Int,
        viewId: Int,
        widgetFolder: String,
        fileName: String
    ) {
        val registration = ThemeWidgetRegistry.registeredWidget(context, widgetId)
        val assetName = if (registration != null) {
            ThemeWidgetAssetPath.resolve(registration.themeId, registration.designId, widgetFolder, fileName)
        } else {
            ThemeWidgetAssetPath.resolve(widgetFolder, fileName)
        }
        // Flutter stores declared assets under assets/flutter_assets in the APK.
        // Using this documented AssetManager path also works when the widget host
        // starts the receiver before a FlutterEngine has been created.
        val assetKey = "flutter_assets/$assetName"
        try {
            val bitmap = bitmapCache[assetKey] ?: synchronized(bitmapCache) {
                bitmapCache[assetKey] ?: decodeAsset(context, assetKey)?.also {
                    bitmapCache[assetKey] = it
                }
            }
            if (bitmap == null) {
                Log.e(TAG, "Widget image decoded to null: $assetName (APK key=$assetKey)")
            } else {
                views.setImageViewBitmap(viewId, bitmap)
                Log.i(TAG, "Loaded widget image $assetName: ${bitmap.width}x${bitmap.height}, ${bitmap.byteCount} bytes")
            }
        } catch (error: Exception) {
            Log.e(TAG, "Could not load widget image $assetName (APK key=$assetKey)", error)
        } catch (error: OutOfMemoryError) {
            Log.e(TAG, "Not enough memory to decode widget image $assetName", error)
        }
    }

    private fun decodeAsset(context: Context, assetKey: String): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        context.assets.open(assetKey).use { BitmapFactory.decodeStream(it, null, bounds) }

        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
            Log.e(TAG, "Invalid widget image dimensions for $assetKey")
            return null
        }

        var sampleSize = 1
        while (
            bounds.outWidth / (sampleSize * 2) >= MAX_DECODED_EDGE_PX ||
            bounds.outHeight / (sampleSize * 2) >= MAX_DECODED_EDGE_PX
        ) {
            sampleSize *= 2
        }

        val options = BitmapFactory.Options().apply {
            inSampleSize = sampleSize
            inPreferredConfig = Bitmap.Config.ARGB_8888
            inScaled = false
        }
        return context.assets.open(assetKey).use { BitmapFactory.decodeStream(it, null, options) }
    }

    private fun launchPendingIntent(context: Context, widgetId: Int): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        return PendingIntent.getActivity(
            context, widgetId * 10, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun actionPendingIntent(
        context: Context,
        widgetId: Int,
        command: String,
        actionSlot: Int
    ): PendingIntent {
        val intent = Intent(context, ThemeWidgetActionReceiver::class.java).apply {
            action = "com.merrmist.muziinapmusic.WIDGET_ACTION"
            data = Uri.parse("muziinap-widget://$widgetId/$command")
            putExtra(ThemeWidgetActionReceiver.EXTRA_WIDGET_ID, widgetId)
            putExtra(ThemeWidgetActionReceiver.EXTRA_COMMAND, command)
        }
        return PendingIntent.getBroadcast(
            context, widgetId * 10 + actionSlot, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    fun updateAll(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        val providers = listOf(
            MusicThemeWidget4x2Provider(),
            MusicThemeWidget4x3Provider()
        )
        providers.forEach { provider ->
            manager.getAppWidgetIds(ComponentName(context, provider.javaClass)).forEach { id ->
                if (assetsAvailable(context, id, provider.widgetFolder) &&
                    ThemeWidgetRegistry.registerWidget(context, id, provider.javaClass.name)) {
                    render(context, manager, id, provider.widgetLayout, provider.widgetFolder)
                } else {
                    renderUnavailable(context, manager, id, provider.widgetLayout)
                }
            }
        }
    }
}
