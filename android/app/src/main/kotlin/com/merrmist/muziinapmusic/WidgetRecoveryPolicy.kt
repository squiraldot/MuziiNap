package com.merrmist.muziinapmusic

/** Conservative recovery pairing: never guess when multiple IDs or tokens exist. */
internal object WidgetRecoveryPolicy {
    fun canAssociateReservation(pendingReservationCount: Int, unregisteredWidgetCount: Int): Boolean =
        pendingReservationCount == 1 && unregisteredWidgetCount == 1
}
