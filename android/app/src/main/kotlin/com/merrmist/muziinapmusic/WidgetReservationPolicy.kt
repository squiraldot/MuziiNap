package com.merrmist.muziinapmusic

/**
 * Stable identity for one selectable theme design.
 *
 * Widget size is deliberately excluded: the same theme/design pair cannot be
 * installed twice at different launcher sizes.
 */
internal data class ThemeWidgetIdentity(
    val themeId: String,
    val designId: String
)

/**
 * Pure reservation gate shared by pinning and direct-picker registration.
 * The SQLite registry remains authoritative for persisted active/pending rows.
 */
internal object WidgetReservationPolicy {
    const val MAX_WIDGETS = 2

    fun canReserve(
        activeCount: Int,
        pendingCount: Int,
        requestedIdentity: ThemeWidgetIdentity,
        registeredIdentities: Set<ThemeWidgetIdentity>,
        pendingIdentities: Set<ThemeWidgetIdentity>,
        recoveryConflict: Boolean
    ): Boolean {
        if (requestedIdentity.themeId.isBlank() || requestedIdentity.designId.isBlank()) {
            return false
        }
        if (recoveryConflict) return false
        if (requestedIdentity in registeredIdentities || requestedIdentity in pendingIdentities) {
            return false
        }

        val occupiedSlots = activeCount.coerceAtLeast(0) + pendingCount.coerceAtLeast(0)
        return occupiedSlots < MAX_WIDGETS
    }
}
