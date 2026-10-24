package com.merrmist.muziinapmusic

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/**
 * Minimal home-screen widget that displays only the currently active synced lyric.
 * The text is supplied by Flutter playback state; no background polling is used.
 */
class LyricsHomeWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        appWidgetIds.forEach { updateWidget(context, appWidgetManager, it) }
    }

    companion object {
        private const val PREFS = "muziinap_home_lyrics_widget"
        private const val KEY_LINE = "current_line"

        fun updateLine(context: Context, line: String) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putString(KEY_LINE, line)
                .apply()

            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, LyricsHomeWidgetProvider::class.java)
            manager.getAppWidgetIds(component).forEach { widgetId ->
                updateWidget(context, manager, widgetId)
            }
        }

        private fun updateWidget(
            context: Context,
            manager: AppWidgetManager,
            widgetId: Int
        ) {
            val line = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getString(KEY_LINE, "").orEmpty()
            val views = RemoteViews(context.packageName, R.layout.lyrics_home_widget)
            views.setTextViewText(R.id.lyrics_home_widget_text, line)

            val launchIntent = context.packageManager
                .getLaunchIntentForPackage(context.packageName)
                ?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            if (launchIntent != null) {
                val pendingIntent = PendingIntent.getActivity(
                    context,
                    7401,
                    launchIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                views.setOnClickPendingIntent(R.id.lyrics_home_widget_root, pendingIntent)
            }
            manager.updateAppWidget(widgetId, views)
        }
    }
}
