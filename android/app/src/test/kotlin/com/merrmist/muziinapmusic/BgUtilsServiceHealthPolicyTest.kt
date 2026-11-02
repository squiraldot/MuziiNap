package com.merrmist.muziinapmusic

import org.junit.Assert.assertEquals
import org.junit.Test

class BgUtilsServiceHealthPolicyTest {
    @Test
    fun successfulHealthCheckResetsConsecutiveFailureCount() {
        assertEquals(0, BgUtilsPotService.nextHealthCheckFailureCount(2, true))
    }

    @Test
    fun consecutiveFailuresAccumulateUntilTheServiceCanBeMarkedUnhealthy() {
        var failures = 0
        failures = BgUtilsPotService.nextHealthCheckFailureCount(failures, false)
        assertEquals(1, failures)
        failures = BgUtilsPotService.nextHealthCheckFailureCount(failures, false)
        assertEquals(2, failures)
        failures = BgUtilsPotService.nextHealthCheckFailureCount(failures, false)
        assertEquals(BgUtilsPotService.HEALTH_CHECK_FAILURE_LIMIT, failures)
    }

    @Test
    fun aTransientHealthCheckFailureDoesNotRemainAfterRecovery() {
        var failures = BgUtilsPotService.nextHealthCheckFailureCount(1, false)
        failures = BgUtilsPotService.nextHealthCheckFailureCount(failures, true)
        assertEquals(0, failures)
    }
}
