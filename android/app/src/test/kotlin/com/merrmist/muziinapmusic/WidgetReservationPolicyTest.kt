package com.merrmist.muziinapmusic

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WidgetReservationPolicyTest {
    private val first = ThemeWidgetIdentity("dragon-ball-z", "widget-1")
    private val second = ThemeWidgetIdentity("dragon-ball-z", "widget-2")

    @Test
    fun allowsTwoDifferentDesignReservations() {
        assertTrue(WidgetReservationPolicy.canReserve(0, 0, first, emptySet(), emptySet(), false))
        assertTrue(WidgetReservationPolicy.canReserve(1, 0, second, setOf(first), emptySet(), false))
    }

    @Test
    fun rejectsThirdReservationIncludingPendingReservations() {
        assertFalse(WidgetReservationPolicy.canReserve(2, 0, second, setOf(first), emptySet(), false))
        assertFalse(WidgetReservationPolicy.canReserve(1, 1, second, setOf(first), emptySet(), false))
    }

    @Test
    fun rejectsDuplicateThemeAndDesignIdentityRegardlessOfSize() {
        assertFalse(WidgetReservationPolicy.canReserve(1, 0, first, setOf(first), emptySet(), false))
        assertFalse(WidgetReservationPolicy.canReserve(0, 1, first, emptySet(), setOf(first), false))
    }

    @Test
    fun blocksNewReservationsDuringRecoveryConflict() {
        assertFalse(WidgetReservationPolicy.canReserve(3, 0, second, setOf(first), emptySet(), true))
    }

    @Test
    fun rejectsBlankDesignIdentity() {
        assertFalse(
            WidgetReservationPolicy.canReserve(
                0, 0, ThemeWidgetIdentity(" ", "widget-1"), emptySet(), emptySet(), false
            )
        )
    }
}
