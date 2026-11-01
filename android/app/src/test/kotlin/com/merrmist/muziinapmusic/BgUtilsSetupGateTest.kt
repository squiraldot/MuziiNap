package com.merrmist.muziinapmusic

import org.junit.Assert.*
import org.junit.Test

class BgUtilsSetupGateTest {
    @Test
    fun rejectsDuplicateSetupUntilCurrentOperationReleasesGate() {
        val gate = BgUtilsSetupGate()
        assertTrue(gate.tryAcquire())
        assertTrue(gate.isActive())
        assertFalse(gate.tryAcquire())
        gate.release()
        assertFalse(gate.isActive())
        assertTrue(gate.tryAcquire())
    }

    @Test
    fun concurrentRequestsAllowOnlyOneOwner() {
        val gate = BgUtilsSetupGate()
        val successes = java.util.concurrent.atomic.AtomicInteger(0)
        val threads = (0 until 24).map {
            Thread {
                if (gate.tryAcquire()) successes.incrementAndGet()
            }
        }
        threads.forEach { it.start() }
        threads.forEach { it.join() }
        assertEquals(1, successes.get())
    }
}
