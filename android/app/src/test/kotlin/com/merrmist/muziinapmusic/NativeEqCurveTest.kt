package com.merrmist.muziinapmusic

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class NativeEqCurveTest {
    @Test
    fun emptyOrDisabledBandsProduceFlatCurve() {
        val flat = NativeEqCurve.convert(emptyList(), bandCount = 32)
        val disabled = NativeEqCurve.convert(
            listOf(NativeEqBand("peaking", 1000f, 9f, 1f, false)),
            bandCount = 32
        )

        assertEquals(32, flat.size)
        assertTrue(flat.all { kotlin.math.abs(it.gainDb) < 0.001f })
        assertTrue(disabled.all { kotlin.math.abs(it.gainDb) < 0.001f })
    }

    @Test
    fun peakingBandBoostsItsCenterAndHonorsQ() {
        val narrow = NativeEqCurve.convert(
            listOf(NativeEqBand("peaking", 1000f, 6f, 4f, true)),
            bandCount = 128
        )
        val broad = NativeEqCurve.convert(
            listOf(NativeEqBand("peaking", 1000f, 6f, 0.5f, true)),
            bandCount = 128
        )
        val narrowAtCenter = narrow.minBy { kotlin.math.abs(it.frequencyHz - 1000f) }
        val broadAtCenter = broad.minBy { kotlin.math.abs(it.frequencyHz - 1000f) }

        assertTrue(narrowAtCenter.gainDb > 4f)
        assertTrue(broadAtCenter.gainDb > 4f)
        assertEquals(narrow.size, broad.size)
        assertTrue(narrow.zip(broad).any { (a, b) -> kotlin.math.abs(a.gainDb - b.gainDb) > 0.25f })
    }

    @Test
    fun unsortedBandsProduceFrequencyOrderedCurve() {
        val curve = NativeEqCurve.convert(
            listOf(
                NativeEqBand("peaking", 5000f, 3f, 1f, true),
                NativeEqBand("peaking", 100f, -4f, 1f, true)
            ),
            bandCount = 64
        )

        assertTrue(curve.zipWithNext().all { (a, b) -> a.frequencyHz < b.frequencyHz })
    }

    @Test
    fun shelfAndPassFiltersProduceNonFlatResponses() {
        val lowShelf = NativeEqCurve.convert(
            listOf(NativeEqBand("lowShelf", 150f, 6f, 0.7f, true)),
            bandCount = 128
        )
        val highPass = NativeEqCurve.convert(
            listOf(NativeEqBand("highPass", 200f, 0f, 0.7f, true)),
            bandCount = 128
        )

        assertTrue(lowShelf.first().gainDb > lowShelf.last().gainDb)
        assertTrue(highPass.first().gainDb < highPass.last().gainDb)
    }
    @Test
    fun stereoBalancePreservesBaseGainAtCenterAndOnlyAttenuatesOppositeSide() {
        val center = NativeEqCurve.channelInputGains(-4f, 0f)
        val left = NativeEqCurve.channelInputGains(-4f, -0.5f)
        val right = NativeEqCurve.channelInputGains(-4f, 0.5f)

        assertEquals(-4f, center.first, 0.001f)
        assertEquals(-4f, center.second, 0.001f)
        assertEquals(-4f, left.first, 0.001f)
        assertTrue(left.second < -4f)
        assertTrue(right.first < -4f)
        assertEquals(-4f, right.second, 0.001f)
    }

    @Test
    fun overlappingBoostsAreRepresentedInTheCombinedCurve() {
        val curve = NativeEqCurve.convert(
            listOf(
                NativeEqBand("peaking", 1000f, 6f, 1f, true),
                NativeEqBand("peaking", 1000f, 6f, 1f, true)
            )
        )

        assertTrue(curve.maxOf { it.gainDb } > 10f)
    }

}
