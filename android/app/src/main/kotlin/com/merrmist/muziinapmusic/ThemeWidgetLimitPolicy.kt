package com.merrmist.muziinapmusic

/** Shared cap policy for all theme-based music widget sizes. */
internal object ThemeWidgetLimitPolicy {
    const val MAX_WIDGETS = 2

    fun canRegister(currentCount: Int, alreadyRegistered: Boolean): Boolean {
        return alreadyRegistered || currentCount.coerceAtLeast(0) < MAX_WIDGETS
    }
}
