package com.merrmist.muziinapmusic

import org.junit.Assert.assertEquals
import org.junit.Test

class PcmDspChainTest {
    @Test
    fun stagesRunInOrderOnTheSameBuffer() {
        val halfGain = PcmBiquadProcessor(
            1,
            PcmBiquadProcessor.Coefficients(0.5, 0.0, 0.0, 0.0, 0.0)
        )
        val quarterGain = PcmBiquadProcessor(
            1,
            PcmBiquadProcessor.Coefficients(0.5, 0.0, 0.0, 0.0, 0.0)
        )
        val chain = PcmDspChain(listOf(halfGain, quarterGain), channelCount = 1)
        val samples = floatArrayOf(1f, -0.8f)

        chain.processInPlace(samples)

        assertEquals(0.25f, samples[0], 1e-6f)
        assertEquals(-0.2f, samples[1], 1e-6f)
    }

    @Test
    fun resetClearsEveryStage() {
        val feedback = PcmBiquadProcessor(
            1,
            PcmBiquadProcessor.Coefficients(1.0, 0.0, 0.0, -0.5, 0.0)
        )
        val chain = PcmDspChain(listOf(feedback), channelCount = 1)
        val impulse = floatArrayOf(1f, 0f)
        chain.processInPlace(impulse)
        assertEquals(0.5f, impulse[1], 1e-6f)

        chain.reset()
        val silence = floatArrayOf(0f)
        chain.processInPlace(silence)
        assertEquals(0f, silence[0], 1e-6f)
    }

    @Test(expected = IllegalArgumentException::class)
    fun rejectsEmptyChain() {
        PcmDspChain(emptyList(), channelCount = 2)
    }
}
