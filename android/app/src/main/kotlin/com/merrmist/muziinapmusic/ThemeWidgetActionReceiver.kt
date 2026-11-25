package com.merrmist.muziinapmusic

import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.view.KeyEvent

/** Validates every widget action before forwarding it to the existing audio session. */
class ThemeWidgetActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_WIDGET_COMMAND) return
        val widgetId = intent.getIntExtra(EXTRA_WIDGET_ID, -1)
        val command = intent.getStringExtra(EXTRA_COMMAND) ?: return
        if (widgetId < 0 || !ThemeWidgetRegistry.isRegisteredWidget(context, widgetId)) return

        val keyCode = when (command) {
            COMMAND_PREVIOUS -> KeyEvent.KEYCODE_MEDIA_PREVIOUS
            COMMAND_PLAY_PAUSE -> KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
            COMMAND_NEXT -> KeyEvent.KEYCODE_MEDIA_NEXT
            COMMAND_SHUFFLE, COMMAND_REPEAT -> {
                val activityIntent = Intent(context, MainActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    putExtra(EXTRA_PENDING_ACTION, command)
                }
                context.startActivity(activityIntent)
                return
            }
            else -> return
        }

        val mediaButton = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
            component = ComponentName(context, "com.ryanheise.audioservice.MediaButtonReceiver")
            putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
        }
        context.sendBroadcast(mediaButton)
    }

    companion object {
        const val ACTION_WIDGET_COMMAND = "com.merrmist.muziinapmusic.WIDGET_ACTION"
        const val EXTRA_WIDGET_ID = "muziinap.widget.APP_WIDGET_ID"
        const val EXTRA_COMMAND = "muziinap.widget.COMMAND"
        const val EXTRA_PENDING_ACTION = "muziinap.widget.PENDING_ACTION"
        const val COMMAND_PREVIOUS = "previous"
        const val COMMAND_PLAY_PAUSE = "play_pause"
        const val COMMAND_NEXT = "next"
        const val COMMAND_SHUFFLE = "shuffle"
        const val COMMAND_REPEAT = "repeat"
    }
}
