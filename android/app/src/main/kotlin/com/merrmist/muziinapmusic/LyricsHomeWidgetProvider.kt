package com.merrmist.muziinapmusic

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/**
 * Transparent home-screen lyrics widget. Flutter supplies timestamp-synced
 * previous/current/next lines; Android only renders and animates those values.
 */
class LyricsHomeWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        appWidgetIds.forEach { updateWidget(context, appWidgetManager, it, initialize = true) }
    }

    companion object {
        private const val PREFS = "muziinap_home_lyrics_widget"
        private const val KEY_PREVIOUS = "previous_line"
        private const val KEY_CURRENT = "current_line"
        private const val KEY_NEXT = "next_line"
        private const val KEY_PAGE = "visible_page"

        fun updateLines(context: Context, previous: String, current: String, next: String) {
            val preferences = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val targetPage = 1 - preferences.getInt(KEY_PAGE, 0).coerceIn(0, 1)
            preferences.edit()
                .putString(KEY_PREVIOUS, previous)
                .putString(KEY_CURRENT, current)
                .putString(KEY_NEXT, next)
                .putInt(KEY_PAGE, targetPage)
                .apply()

            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, LyricsHomeWidgetProvider::class.java)
            manager.getAppWidgetIds(component).forEach { widgetId ->
                updateWidget(context, manager, widgetId, initialize = false)
            }
        }

        private fun updateWidget(
            context: Context,
            manager: AppWidgetManager,
            widgetId: Int,
            initialize: Boolean
        ) {
            val preferences = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val previous = preferences.getString(KEY_PREVIOUS, "").orEmpty()
            val current = preferences.getString(KEY_CURRENT, "").orEmpty()
            val next = preferences.getString(KEY_NEXT, "").orEmpty()
            val page = preferences.getInt(KEY_PAGE, 0).coerceIn(0, 1)
            val views = RemoteViews(context.packageName, R.layout.lyrics_home_widget)

            if (initialize) {
                // On first placement both pages need content so the first line
                // change can cross-fade from a populated page.
                setPageText(views, 0, previous, current, next)
                setPageText(views, 1, previous, current, next)
            } else {
                // Update the hidden page, then flip to it. The ViewFlipper's
                // fade animations keep the outgoing lyric visible during the change.
                setPageText(views, page, previous, current, next)
            }
            views.setDisplayedChild(R.id.lyrics_home_widget_flipper, page)

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

        private fun setPageText(
            views: RemoteViews,
            page: Int,
            previous: String,
            current: String,
            next: String
        ) {
            val previousId = if (page == 0) R.id.lyrics_home_widget_previous_a
                else R.id.lyrics_home_widget_previous_b
            val currentId = if (page == 0) R.id.lyrics_home_widget_current_a
                else R.id.lyrics_home_widget_current_b
            val nextId = if (page == 0) R.id.lyrics_home_widget_next_a
                else R.id.lyrics_home_widget_next_b
            views.setTextViewText(previousId, previous)
            views.setTextViewText(currentId, current)
            views.setTextViewText(nextId, next)
        }
    }
}
