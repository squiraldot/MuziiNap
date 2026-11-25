package com.merrmist.muziinapmusic

import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent

/** Receives only the explicit completion callback for an in-app pin reservation. */
class ThemeWidgetPinReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val token = intent.getStringExtra(EXTRA_RESERVATION_TOKEN) ?: return
        val widgetId = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, -1)
        if (widgetId < 0) {
            ThemeWidgetRegistry.releaseReservation(context, token)
            return
        }
        val size = ThemeWidgetRegistry.reservationSize(context, token) ?: return
        val provider = if (size == "4x3") MusicThemeWidget4x3Provider::class.java
            else MusicThemeWidget4x2Provider::class.java
        if (!ThemeWidgetRegistry.finalizePin(context, token, widgetId, provider.name)) return

        val update = Intent(context, provider).apply {
            action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, intArrayOf(widgetId))
        }
        context.sendBroadcast(update)
    }

    companion object {
        const val EXTRA_RESERVATION_TOKEN = "muziinap.widget.RESERVATION_TOKEN"
    }
}
