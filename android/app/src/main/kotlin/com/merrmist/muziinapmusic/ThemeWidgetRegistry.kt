package com.merrmist.muziinapmusic

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import java.util.UUID

internal data class ThemeWidgetPlaybackState(
    val title: String,
    val artist: String,
    val isPlaying: Boolean,
    val positionMs: Long = 0L,
    val durationMs: Long = 0L,
    val shuffleEnabled: Boolean = false,
    val repeatMode: String = "OFF",
    val revision: Long = 0L
)

internal data class RegisteredThemeWidget(
    val appWidgetId: Int,
    val internalUuid: String,
    val themeId: String,
    val designId: String,
    val widgetSize: String,
    val lifecycleState: String,
    val providerClass: String
)

/** SQLite-backed theme widget registrations, pin reservations and playback snapshot. */
internal object ThemeWidgetRegistry {
    private const val TABLE_WIDGETS = "widget_instances"
    private const val TABLE_PLAYBACK = "playback_state"
    private const val TABLE_RESERVATIONS = "pin_reservations"

    @Volatile private var databaseHelper: WidgetDatabase? = null

    private fun helper(context: Context): WidgetDatabase {
        return databaseHelper ?: synchronized(this) {
            databaseHelper ?: WidgetDatabase(context.applicationContext).also { databaseHelper = it }
        }
    }

    fun reconcile(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        val activeIds = (manager.getAppWidgetIds(
            ComponentName(context, MusicThemeWidget4x2Provider::class.java)
        ) + manager.getAppWidgetIds(
            ComponentName(context, MusicThemeWidget4x3Provider::class.java)
        )).toSet()
        val db = helper(context).writableDatabase
        db.beginTransaction()
        try {
            db.query(TABLE_WIDGETS, arrayOf("app_widget_id"), null, null, null, null, null).use { cursor ->
                val staleIds = mutableListOf<Int>()
                while (cursor.moveToNext()) {
                    val id = cursor.getInt(0)
                    if (id !in activeIds) staleIds.add(id)
                }
                staleIds.forEach { id ->
                    db.delete(TABLE_WIDGETS, "app_widget_id = ?", arrayOf(id.toString()))
                }
            }
            pruneExpiredReservations(db)
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    fun isRegisteredWidget(context: Context, widgetId: Int): Boolean =
        findWidget(helper(context).readableDatabase, widgetId) != null

    private fun pruneExpiredReservations(db: SQLiteDatabase) {
        // Allow launchers a day to deliver their pin callback before releasing a lost reservation.
        val expiry = System.currentTimeMillis() - 24L * 60L * 60L * 1000L
        db.delete(TABLE_RESERVATIONS, "created_at < ?", arrayOf(expiry.toString()))
    }

    fun registerWidget(
        context: Context,
        widgetId: Int,
        providerClass: String,
        themeId: String = "dragon-ball-z",
        designId: String = "widget-1",
        widgetSize: String = if (providerClass.contains("4x3")) "4x3" else "4x2"
    ): Boolean {
        if (widgetId < 0 || themeId.isBlank() || designId.isBlank() ||
            (widgetSize != "4x2" && widgetSize != "4x3")) return false
        val db = helper(context).writableDatabase
        db.beginTransaction()
        try {
            pruneExpiredReservations(db)
            val existing = findWidget(db, widgetId)
            if (existing != null) {
                db.setTransactionSuccessful()
                return true
            }
            val count = scalarCount(db, TABLE_WIDGETS)
            val pending = scalarCount(db, TABLE_RESERVATIONS)
            val identities = readIdentities(db, TABLE_WIDGETS)
            val pendingIdentities = readIdentities(db, TABLE_RESERVATIONS)
            val identity = ThemeWidgetIdentity(themeId, designId)
            if (!WidgetReservationPolicy.canReserve(
                    count, pending, identity, identities, pendingIdentities, false
                )) return false

            val now = System.currentTimeMillis()
            val values = ContentValues().apply {
                put("app_widget_id", widgetId)
                put("provider_class", providerClass)
                put("created_at", now)
                put("internal_uuid", UUID.randomUUID().toString())
                put("theme_id", themeId)
                put("design_id", designId)
                put("widget_size", widgetSize)
                put("lifecycle_state", "ACTIVE")
                putNull("pending_pin_token")
                put("updated_at", now)
            }
            db.insertOrThrow(TABLE_WIDGETS, null, values)
            db.setTransactionSuccessful()
            return true
        } finally {
            db.endTransaction()
        }
    }

    fun reservePin(
        context: Context,
        token: String,
        themeId: String,
        designId: String,
        widgetSize: String
    ): Boolean {
        if (token.isBlank() || themeId.isBlank() || designId.isBlank() ||
            (widgetSize != "4x2" && widgetSize != "4x3")) return false
        val db = helper(context).writableDatabase
        db.beginTransaction()
        try {
            pruneExpiredReservations(db)
            if (db.query(TABLE_RESERVATIONS, arrayOf("token"), "token = ?",
                    arrayOf(token), null, null, null).use { it.moveToFirst() }) {
                db.setTransactionSuccessful()
                return true
            }
            val activeCount = scalarCount(db, TABLE_WIDGETS)
            val pendingCount = scalarCount(db, TABLE_RESERVATIONS)
            val activeIdentities = readIdentities(db, TABLE_WIDGETS)
            val pendingIdentities = readIdentities(db, TABLE_RESERVATIONS)
            if (!WidgetReservationPolicy.canReserve(
                    activeCount, pendingCount, ThemeWidgetIdentity(themeId, designId),
                    activeIdentities, pendingIdentities, false
                )) return false
            db.insertOrThrow(TABLE_RESERVATIONS, null, ContentValues().apply {
                put("token", token)
                put("theme_id", themeId)
                put("design_id", designId)
                put("widget_size", widgetSize)
                put("created_at", System.currentTimeMillis())
            })
            db.setTransactionSuccessful()
            return true
        } finally {
            db.endTransaction()
        }
    }

    fun finalizePin(
        context: Context,
        token: String,
        widgetId: Int,
        providerClass: String
    ): Boolean {
        if (token.isBlank() || widgetId < 0) return false
        val db = helper(context).writableDatabase
        db.beginTransaction()
        try {
            val reservation = db.query(
                TABLE_RESERVATIONS,
                arrayOf("theme_id", "design_id", "widget_size"),
                "token = ?", arrayOf(token), null, null, null
            ).use { cursor ->
                if (!cursor.moveToFirst()) null else Triple(
                    cursor.getString(0), cursor.getString(1), cursor.getString(2)
                )
            } ?: return false
            val existing = findWidget(db, widgetId)
            if (existing != null) {
                db.delete(TABLE_RESERVATIONS, "token = ?", arrayOf(token))
                db.setTransactionSuccessful()
                return true
            }
            val duplicate = db.query(
                TABLE_WIDGETS, arrayOf("app_widget_id"),
                "theme_id = ? AND design_id = ?",
                arrayOf(reservation.first, reservation.second), null, null, null
            ).use { it.moveToFirst() }
            if (duplicate) return false
            val now = System.currentTimeMillis()
            db.insertOrThrow(TABLE_WIDGETS, null, ContentValues().apply {
                put("app_widget_id", widgetId)
                put("provider_class", providerClass)
                put("created_at", now)
                put("internal_uuid", UUID.randomUUID().toString())
                put("theme_id", reservation.first)
                put("design_id", reservation.second)
                put("widget_size", reservation.third)
                put("lifecycle_state", "ACTIVE")
                putNull("pending_pin_token")
                put("updated_at", now)
            })
            db.delete(TABLE_RESERVATIONS, "token = ?", arrayOf(token))
            db.setTransactionSuccessful()
            return true
        } finally {
            db.endTransaction()
        }
    }

    fun reservationSize(context: Context, token: String): String? {
        if (token.isBlank()) return null
        return helper(context).readableDatabase.query(
            TABLE_RESERVATIONS, arrayOf("widget_size"), "token = ?",
            arrayOf(token), null, null, null
        ).use { if (it.moveToFirst()) it.getString(0) else null }
    }

    fun pendingReservationCount(context: Context): Int =
        scalarCount(helper(context).readableDatabase, TABLE_RESERVATIONS)

    fun releaseReservation(context: Context, token: String) {
        if (token.isBlank()) return
        helper(context).writableDatabase.delete(TABLE_RESERVATIONS, "token = ?", arrayOf(token))
    }

    fun unregisterWidget(context: Context, widgetIds: IntArray) {
        if (widgetIds.isEmpty()) return
        val db = helper(context).writableDatabase
        db.beginTransaction()
        try {
            widgetIds.forEach { id -> db.delete(TABLE_WIDGETS, "app_widget_id = ?", arrayOf(id.toString())) }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    fun registeredWidget(context: Context, widgetId: Int): RegisteredThemeWidget? =
        findWidget(helper(context).readableDatabase, widgetId)

    fun registeredWidgets(context: Context): List<RegisteredThemeWidget> {
        return helper(context).readableDatabase.query(
            TABLE_WIDGETS,
            arrayOf("app_widget_id", "internal_uuid", "theme_id", "design_id",
                "widget_size", "lifecycle_state", "provider_class"),
            null, null, null, null, "created_at ASC"
        ).use { cursor ->
            buildList {
                while (cursor.moveToNext()) add(RegisteredThemeWidget(
                    cursor.getInt(0), cursor.getString(1), cursor.getString(2),
                    cursor.getString(3), cursor.getString(4), cursor.getString(5),
                    cursor.getString(6)
                ))
            }
        }
    }

    fun updatePlaybackState(
        context: Context,
        title: String,
        artist: String,
        isPlaying: Boolean,
        positionMs: Long = 0L,
        durationMs: Long = 0L,
        shuffleEnabled: Boolean = false,
        repeatMode: String = "OFF",
        revision: Long = System.currentTimeMillis()
    ): Boolean {
        if (repeatMode !in setOf("OFF", "ALL", "ONE")) return false
        val db = helper(context).writableDatabase
        db.beginTransaction()
        try {
            val currentRevision = db.query(
                TABLE_PLAYBACK, arrayOf("revision"), "id = ?", arrayOf("1"),
                null, null, null
            ).use { if (it.moveToFirst()) it.getLong(0) else -1L }
            if (revision < currentRevision) return false
            val values = ContentValues().apply {
                put("id", 1)
                put("title", title.take(180))
                put("artist", artist.take(180))
                put("is_playing", if (isPlaying) 1 else 0)
                put("position_ms", positionMs.coerceAtLeast(0L))
                put("duration_ms", durationMs.coerceAtLeast(0L))
                put("shuffle_enabled", if (shuffleEnabled) 1 else 0)
                put("repeat_mode", repeatMode)
                put("revision", revision)
                put("updated_at", System.currentTimeMillis())
            }
            db.insertWithOnConflict(TABLE_PLAYBACK, null, values, SQLiteDatabase.CONFLICT_REPLACE)
            db.setTransactionSuccessful()
            return true
        } finally {
            db.endTransaction()
        }
    }

    fun playbackState(context: Context): ThemeWidgetPlaybackState {
        return helper(context).readableDatabase.query(
            TABLE_PLAYBACK,
            arrayOf("title", "artist", "is_playing", "position_ms", "duration_ms",
                "shuffle_enabled", "repeat_mode", "revision"),
            "id = ?", arrayOf("1"), null, null, null
        ).use { cursor ->
            if (cursor.moveToFirst()) ThemeWidgetPlaybackState(
                cursor.getString(0).orEmpty(), cursor.getString(1).orEmpty(),
                cursor.getInt(2) == 1, cursor.getLong(3), cursor.getLong(4),
                cursor.getInt(5) == 1, cursor.getString(6), cursor.getLong(7)
            ) else ThemeWidgetPlaybackState(
                "Nothing playing", "Play something in MuziiNap", false
            )
        }
    }

    private fun findWidget(db: SQLiteDatabase, widgetId: Int): RegisteredThemeWidget? {
        return db.query(TABLE_WIDGETS,
            arrayOf("app_widget_id", "internal_uuid", "theme_id", "design_id",
                "widget_size", "lifecycle_state", "provider_class"),
            "app_widget_id = ?", arrayOf(widgetId.toString()), null, null, null
        ).use { c ->
            if (!c.moveToFirst()) null else RegisteredThemeWidget(
                c.getInt(0), c.getString(1), c.getString(2), c.getString(3),
                c.getString(4), c.getString(5), c.getString(6)
            )
        }
    }

    private fun scalarCount(db: SQLiteDatabase, table: String): Int =
        db.rawQuery("SELECT COUNT(*) FROM $table", null).use {
            if (it.moveToFirst()) it.getInt(0) else 0
        }

    private fun readIdentities(db: SQLiteDatabase, table: String): Set<ThemeWidgetIdentity> =
        db.query(table, arrayOf("theme_id", "design_id"), null, null, null, null, null).use { c ->
            buildSet {
                while (c.moveToNext()) add(ThemeWidgetIdentity(c.getString(0), c.getString(1)))
            }
        }

    private class WidgetDatabase(context: Context) :
        SQLiteOpenHelper(context, "muziinap_theme_widgets.db", null, 2) {
        override fun onCreate(db: SQLiteDatabase) {
            db.execSQL("""CREATE TABLE widget_instances (
                app_widget_id INTEGER PRIMARY KEY,
                provider_class TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                internal_uuid TEXT NOT NULL,
                theme_id TEXT NOT NULL,
                design_id TEXT NOT NULL,
                widget_size TEXT NOT NULL,
                lifecycle_state TEXT NOT NULL,
                pending_pin_token TEXT,
                updated_at INTEGER NOT NULL
            )""".trimIndent())
            db.execSQL("""CREATE TABLE playback_state (
                id INTEGER PRIMARY KEY CHECK(id = 1),
                title TEXT NOT NULL,
                artist TEXT NOT NULL,
                is_playing INTEGER NOT NULL DEFAULT 0,
                position_ms INTEGER NOT NULL DEFAULT 0,
                duration_ms INTEGER NOT NULL DEFAULT 0,
                shuffle_enabled INTEGER NOT NULL DEFAULT 0,
                repeat_mode TEXT NOT NULL DEFAULT 'OFF',
                revision INTEGER NOT NULL DEFAULT 0,
                updated_at INTEGER NOT NULL
            )""".trimIndent())
            db.execSQL("""CREATE TABLE pin_reservations (
                token TEXT PRIMARY KEY,
                theme_id TEXT NOT NULL,
                design_id TEXT NOT NULL,
                widget_size TEXT NOT NULL,
                created_at INTEGER NOT NULL
            )""".trimIndent())
        }

        override fun onOpen(db: SQLiteDatabase) {
            super.onOpen(db)
            db.query(TABLE_WIDGETS, arrayOf("app_widget_id"), "internal_uuid = ''", null,
                null, null, null).use { cursor ->
                val ids = mutableListOf<Int>()
                while (cursor.moveToNext()) ids.add(cursor.getInt(0))
                ids.forEach { id ->
                    db.update(TABLE_WIDGETS, ContentValues().apply {
                        put("internal_uuid", UUID.randomUUID().toString())
                        put("updated_at", System.currentTimeMillis())
                    }, "app_widget_id = ?", arrayOf(id.toString()))
                }
            }
        }

        override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
            if (oldVersion < 2) {
                db.execSQL("ALTER TABLE widget_instances ADD COLUMN internal_uuid TEXT NOT NULL DEFAULT ''")
                db.execSQL("ALTER TABLE widget_instances ADD COLUMN theme_id TEXT NOT NULL DEFAULT 'dragon-ball-z'")
                db.execSQL("ALTER TABLE widget_instances ADD COLUMN design_id TEXT NOT NULL DEFAULT 'widget-1'")
                db.execSQL("ALTER TABLE widget_instances ADD COLUMN widget_size TEXT NOT NULL DEFAULT '4x2'")
                db.execSQL("ALTER TABLE widget_instances ADD COLUMN lifecycle_state TEXT NOT NULL DEFAULT 'ACTIVE'")
                db.execSQL("ALTER TABLE widget_instances ADD COLUMN pending_pin_token TEXT")
                db.execSQL("ALTER TABLE widget_instances ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0")
                db.execSQL("UPDATE widget_instances SET internal_uuid = lower(hex(randomblob(16))), updated_at = created_at")
                db.execSQL("ALTER TABLE playback_state ADD COLUMN position_ms INTEGER NOT NULL DEFAULT 0")
                db.execSQL("ALTER TABLE playback_state ADD COLUMN duration_ms INTEGER NOT NULL DEFAULT 0")
                db.execSQL("ALTER TABLE playback_state ADD COLUMN shuffle_enabled INTEGER NOT NULL DEFAULT 0")
                db.execSQL("ALTER TABLE playback_state ADD COLUMN repeat_mode TEXT NOT NULL DEFAULT 'OFF'")
                db.execSQL("ALTER TABLE playback_state ADD COLUMN revision INTEGER NOT NULL DEFAULT 0")
                db.execSQL("""CREATE TABLE pin_reservations (
                    token TEXT PRIMARY KEY, theme_id TEXT NOT NULL, design_id TEXT NOT NULL,
                    widget_size TEXT NOT NULL, created_at INTEGER NOT NULL
                )""".trimIndent())
            }
        }
    }
}
