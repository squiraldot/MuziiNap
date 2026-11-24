package com.merrmist.muziinapmusic

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

internal data class ThemeWidgetPlaybackState(
    val title: String,
    val artist: String,
    val isPlaying: Boolean
)

/** SQLite-backed widget lifecycle registry and last-known playback snapshot. */
internal object ThemeWidgetRegistry {
    private const val DATABASE_NAME = "muziinap_theme_widgets.db"
    private const val DATABASE_VERSION = 1
    private const val TABLE_WIDGETS = "widget_instances"
    private const val TABLE_PLAYBACK = "playback_state"

    @Volatile private var databaseHelper: WidgetDatabase? = null

    private fun helper(context: Context): WidgetDatabase {
        return databaseHelper ?: synchronized(this) {
            databaseHelper ?: WidgetDatabase(context.applicationContext).also {
                databaseHelper = it
            }
        }
    }

    fun registerWidget(context: Context, widgetId: Int, providerClass: String): Boolean {
        val db = helper(context).writableDatabase
        db.beginTransaction()
        try {
            val alreadyRegistered = db.query(
                TABLE_WIDGETS, arrayOf("app_widget_id"), "app_widget_id = ?",
                arrayOf(widgetId.toString()), null, null, null
            ).use { it.moveToFirst() }
            val count = db.rawQuery("SELECT COUNT(*) FROM $TABLE_WIDGETS", null).use {
                if (it.moveToFirst()) it.getInt(0) else 0
            }
            if (!ThemeWidgetLimitPolicy.canRegister(count, alreadyRegistered)) return false

            val values = ContentValues().apply {
                put("app_widget_id", widgetId)
                put("provider_class", providerClass)
                put("created_at", System.currentTimeMillis())
            }
            db.insertWithOnConflict(TABLE_WIDGETS, null, values, SQLiteDatabase.CONFLICT_REPLACE)
            db.setTransactionSuccessful()
            return true
        } finally {
            db.endTransaction()
        }
    }

    fun unregisterWidget(context: Context, widgetIds: IntArray) {
        if (widgetIds.isEmpty()) return
        val db = helper(context).writableDatabase
        db.beginTransaction()
        try {
            widgetIds.forEach { id ->
                db.delete(TABLE_WIDGETS, "app_widget_id = ?", arrayOf(id.toString()))
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    fun updatePlaybackState(context: Context, title: String, artist: String, isPlaying: Boolean) {
        val values = ContentValues().apply {
            put("id", 1)
            put("title", title.take(180))
            put("artist", artist.take(180))
            put("is_playing", if (isPlaying) 1 else 0)
            put("updated_at", System.currentTimeMillis())
        }
        helper(context).writableDatabase.insertWithOnConflict(
            TABLE_PLAYBACK, null, values, SQLiteDatabase.CONFLICT_REPLACE
        )
    }

    fun playbackState(context: Context): ThemeWidgetPlaybackState {
        return helper(context).readableDatabase.query(
            TABLE_PLAYBACK, arrayOf("title", "artist", "is_playing"),
            "id = ?", arrayOf("1"), null, null, null
        ).use { cursor ->
            if (cursor.moveToFirst()) {
                ThemeWidgetPlaybackState(
                    cursor.getString(0).orEmpty(),
                    cursor.getString(1).orEmpty(),
                    cursor.getInt(2) == 1
                )
            } else {
                ThemeWidgetPlaybackState(
                    "Nothing playing", "Play something in MuziiNap", false
                )
            }
        }
    }

    private class WidgetDatabase(context: Context) :
        SQLiteOpenHelper(context, DATABASE_NAME, null, DATABASE_VERSION) {
        override fun onCreate(db: SQLiteDatabase) {
            db.execSQL(
                """CREATE TABLE $TABLE_WIDGETS (
                    app_widget_id INTEGER PRIMARY KEY,
                    provider_class TEXT NOT NULL,
                    created_at INTEGER NOT NULL
                )""".trimIndent()
            )
            db.execSQL(
                """CREATE TABLE $TABLE_PLAYBACK (
                    id INTEGER PRIMARY KEY CHECK(id = 1),
                    title TEXT NOT NULL,
                    artist TEXT NOT NULL,
                    is_playing INTEGER NOT NULL DEFAULT 0,
                    updated_at INTEGER NOT NULL
                )""".trimIndent()
            )
        }

        override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
            // Future schema upgrades must preserve widget IDs and playback state.
        }
    }
}
