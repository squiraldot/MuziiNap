package com.merrmist.muziinapmusic

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WidgetRecoveryPolicyTest {
    @Test
    fun associatesOnePendingReservationWithOneUnregisteredWidget() {
        assertTrue(WidgetRecoveryPolicy.canAssociateReservation(1, 1))
    }

    @Test
    fun refusesToGuessWhenMultiplePinRequestsArePending() {
        assertFalse(WidgetRecoveryPolicy.canAssociateReservation(2, 1))
    }

    @Test
    fun refusesToGuessWhenMultipleWidgetsAreUnregistered() {
        assertFalse(WidgetRecoveryPolicy.canAssociateReservation(1, 2))
    }

    @Test
    fun refusesToAssociateWhenNoReservationExists() {
        assertFalse(WidgetRecoveryPolicy.canAssociateReservation(0, 1))
    }
}
