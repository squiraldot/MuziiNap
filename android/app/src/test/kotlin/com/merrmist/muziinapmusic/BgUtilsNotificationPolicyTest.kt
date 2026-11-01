package com.merrmist.muziinapmusic

import org.junit.Assert.*
import org.junit.Test

class BgUtilsNotificationPolicyTest {
    @Test
    fun notificationPermissionIsOptionalOnAndroid13AndNewer() {
        assertFalse(BgUtilsDownloadNotifications.notificationsAllowed(33, false))
        assertFalse(BgUtilsDownloadNotifications.notificationsAllowed(35, false))
        assertTrue(BgUtilsDownloadNotifications.notificationsAllowed(33, true))
    }

    @Test
    fun preAndroid13DoesNotRequireRuntimeNotificationPermission() {
        assertTrue(BgUtilsDownloadNotifications.notificationsAllowed(32, false))
        assertTrue(BgUtilsDownloadNotifications.notificationsAllowed(26, false))
    }
}
