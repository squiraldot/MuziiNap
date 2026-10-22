package com.merrmist.muziinapmusic

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PcmBiquadProcessorTest {
    @Test
    fun identityCoefficientsPreservePcm() {
        val processor = PcmBiquadProcessor(2)
        val samples = floatArrayOf(0.25f, -0.5f, 1.2f, -1.4f)

        processor.processInPlace(samples)

        assertEquals(0.25f, samples[0], 1e-6f)
        assertEquals(-0.5f, samples[1], 1e-6f)
        assertEquals(1.2f, samples[2], 1e-6f)
        assertEquals(-1.4f, samples[3], 1e-6f)
    }

    @Test
    fun bypassPreservesInputAndDoesNotAdvanceState() {
        val processor = PcmBiquadProcessor(
            channelCount = 1,
            coefficients = PcmBiquadProcessor.Coefficients(
                b0 = 0.5, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0
            )
        )
        processor.setBypassed(true)
        val bypassed = floatArrayOf(1f, 0.5f)
        processor.processInPlace(bypassed)
        assertEquals(1f, bypassed[0], 0f)
        assertEquals(0.5f, bypassed[1], 0f)

        processor.setBypassed(false)
        val active = floatArrayOf(1f)
        processor.processInPlace(active)
        assertEquals(0.5f, active[0], 1e-6f)
    }

    @Test
    fun filterStateIsIndependentPerChannel() {
        val processor = PcmBiquadProcessor(
            channelCount = 2,
            coefficients = PcmBiquadProcessor.Coefficients(
                b0 = 1.0, b1 = 0.0, b2 = 0.0, a1 = -0.5, a2 = 0.0
            )
        )
        val samples = floatArrayOf(1f, 0f, 0f, 0f)
        processor.processInPlace(samples)

        assertEquals(1f, samples[0], 1e-6f)
        assertEquals(0f, samples[1], 1e-6f)
        assertEquals(0.5f, samples[2], 1e-6f)
        assertEquals(0f, samples[3], 1e-6f)
    }

    @Test
    fun resetClearsFilterHistory() {
        val processor = PcmBiquadProcessor(
            channelCount = 1,
            coefficients = PcmBiquadProcessor.Coefficients(
                b0 = 1.0, b1 = 0.0, b2 = 0.0, a1 = -0.8, a2 = 0.0
            )
        )
        val impulse = floatArrayOf(1f, 0f)
        processor.processInPlace(impulse)
        assertTrue(impulse[1] > 0f)

        processor.reset()
        val afterReset = floatArrayOf(0f)
        processor.processInPlace(afterReset)
        assertEquals(0f, afterReset[0], 1e-6f)
    }

    @Test(expected = IllegalArgumentException::class)
    fun rejectsInvalidChannelCount() {
        PcmBiquadProcessor(0)
    }

    @Test(expected = IllegalArgumentException::class)
    fun rejectsTooShortBuffer() {
        PcmBiquadProcessor(2).processInPlace(floatArrayOf(1f), frameCount = 1)
    }
}
