package com.merrmist.muziinapmusic

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WidgetControlVisibilityPolicyTest {
    @Test
    fun activeRenderRestoresEveryPlaybackControl() {
        assertTrue(WidgetControlVisibilityPolicy.forMode(WidgetRenderMode.ACTIVE).visible)
    }

    @Test
    fun limitReachedRenderHidesEveryPlaybackControl() {
        assertFalse(WidgetControlVisibilityPolicy.forMode(WidgetRenderMode.LIMIT_REACHED).visible)
    }

    @Test
    fun unavailableRenderHidesEveryPlaybackControl() {
        assertFalse(WidgetControlVisibilityPolicy.forMode(WidgetRenderMode.UNAVAILABLE).visible)
    }
}
