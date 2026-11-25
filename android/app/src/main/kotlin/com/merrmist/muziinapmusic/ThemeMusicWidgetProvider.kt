package com.merrmist.muziinapmusic

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
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
    protected abstract val widgetLayout: Int

    override fun onUpdate(context: Context, manager: AppWidgetManager, appWidgetIds: IntArray) {
        appWidgetIds.forEach { id ->
            if (ThemeWidgetRegistry.registerWidget(context, id, javaClass.name)) {
                ThemeMusicWidgetRenderer.render(context, manager, id, widgetLayout)
            } else {
                ThemeMusicWidgetRenderer.renderLimitReached(context, manager, id, widgetLayout)
            }
        }
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        ThemeWidgetRegistry.unregisterWidget(context, appWidgetIds)
        super.onDeleted(context, appWidgetIds)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context, manager: AppWidgetManager, appWidgetId: Int, newOptions: android.os.Bundle
    ) {
        if (ThemeWidgetRegistry.registerWidget(context, appWidgetId, javaClass.name)) {
            ThemeMusicWidgetRenderer.render(context, manager, appWidgetId, widgetLayout)
        } else {
            ThemeMusicWidgetRenderer.renderLimitReached(context, manager, appWidgetId, widgetLayout)
        }
        super.onAppWidgetOptionsChanged(context, manager, appWidgetId, newOptions)
    }
}

class MusicThemeWidget4x2Provider : ThemeMusicWidgetProvider() {
    override val widgetLayout: Int = R.layout.music_theme_widget
}

class MusicThemeWidget4x3Provider : ThemeMusicWidgetProvider() {
    override val widgetLayout: Int = R.layout.music_theme_widget
}

internal object ThemeMusicWidgetRenderer {
    private const val TAG = "MuziiNapThemeWidget"
    private const val ASSET_PREFIX =
        "flutter_assets/assets/widget_assets/Dragon_Ball_Z/4x2/Widget1/"
    private val bitmapCache = ConcurrentHashMap<String, Bitmap>()

    fun render(context: Context, manager: AppWidgetManager, widgetId: Int, layoutId: Int) {
        val state = ThemeWidgetRegistry.playbackState(context)
        val views = RemoteViews(context.packageName, layoutId)
        views.setTextViewText(R.id.music_theme_widget_title, state.title)
        views.setTextViewText(R.id.music_theme_widget_artist, state.artist)
        views.setImageViewResource(
            R.id.music_theme_widget_play_pause,
            if (state.isPlaying) android.R.drawable.ic_media_pause
            else android.R.drawable.ic_media_play
        )
        setAsset(context, views, R.id.music_theme_widget_background, "Background.png")
        setAsset(context, views, R.id.music_theme_widget_border, "Border.png")
        setAsset(context, views, R.id.music_theme_widget_character, "Character.png")

        views.setOnClickPendingIntent(R.id.music_theme_widget_root, launchPendingIntent(context, widgetId))
        views.setOnClickPendingIntent(
            R.id.music_theme_widget_previous,
            mediaButtonPendingIntent(context, widgetId, KeyEvent.KEYCODE_MEDIA_PREVIOUS, 1)
        )
        views.setOnClickPendingIntent(
            R.id.music_theme_widget_play_pause,
            mediaButtonPendingIntent(context, widgetId, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, 2)
        )
        views.setOnClickPendingIntent(
            R.id.music_theme_widget_next,
            mediaButtonPendingIntent(context, widgetId, KeyEvent.KEYCODE_MEDIA_NEXT, 3)
        )
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

    private fun setAsset(context: Context, views: RemoteViews, viewId: Int, fileName: String) {
        val path = ASSET_PREFIX + fileName
        try {
            val bitmap = bitmapCache[path] ?: synchronized(bitmapCache) {
                bitmapCache[path] ?: context.assets.open(path).use { stream ->
                    BitmapFactory.decodeStream(
                        stream, null, BitmapFactory.Options().apply { inSampleSize = 2 }
                    )
                }?.also { bitmapCache[path] = it }
            }
            if (bitmap != null) views.setImageViewBitmap(viewId, bitmap)
        } catch (error: Exception) {
            Log.w(TAG, "Could not load bundled widget image $path", error)
        }
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

    private fun mediaButtonPendingIntent(
        context: Context, widgetId: Int, keyCode: Int, actionSlot: Int
    ): PendingIntent {
        val intent = Intent(Intent.ACTION_MEDIA_BUTTON)
            .setComponent(ComponentName(context, "com.ryanheise.audioservice.MediaButtonReceiver"))
            .putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
        return PendingIntent.getBroadcast(
            context, widgetId * 10 + actionSlot, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    fun updateAll(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        listOf(
            MusicThemeWidget4x2Provider::class.java,
            MusicThemeWidget4x3Provider::class.java
        ).forEach { provider ->
            manager.getAppWidgetIds(ComponentName(context, provider)).forEach { id ->
                if (ThemeWidgetRegistry.registerWidget(context, id, provider.name)) {
                    render(context, manager, id, R.layout.music_theme_widget)
                } else {
                    renderLimitReached(context, manager, id, R.layout.music_theme_widget)
                }
            }
        }
    }
}
