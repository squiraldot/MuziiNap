package com.merrmist.muziinapmusic

import kotlin.math.abs

/**
 * Stateful direct-form-II-transposed biquad for interleaved floating-point PCM.
 *
 * This is a pure DSP building block. It deliberately does not own an AudioTrack
 * or claim to process just_audio output until a custom ExoPlayer AudioProcessor
 * is wired into the playback pipeline.
 */
internal class PcmBiquadProcessor(
    private val channelCount: Int,
    coefficients: Coefficients = Coefficients.IDENTITY
) {
    data class Coefficients(
        val b0: Double,
        val b1: Double,
        val b2: Double,
        val a1: Double,
        val a2: Double
    ) {
        init {
            require(listOf(b0, b1, b2, a1, a2).all { it.isFinite() }) {
                "Biquad coefficients must be finite"
            }
        }

        companion object {
            val IDENTITY = Coefficients(1.0, 0.0, 0.0, 0.0, 0.0)
        }
    }

    private var activeCoefficients = coefficients
    private var bypassed = false
    private val z1 = DoubleArray(channelCount)
    private val z2 = DoubleArray(channelCount)

    init {
        require(channelCount in 1..8) { "Channel count must be between 1 and 8" }
    }

    /** Replaces the filter response and clears old state to avoid stale transients. */
    @Synchronized
    fun setCoefficients(coefficients: Coefficients, resetState: Boolean = true) {
        activeCoefficients = coefficients
        if (resetState) reset()
    }

    @Synchronized
    fun setBypassed(value: Boolean) {
        bypassed = value
    }

    @Synchronized
    fun reset() {
        z1.fill(0.0)
        z2.fill(0.0)
    }

    /**
     * Processes [frameCount] interleaved PCM frames in-place.
     * Samples outside [-1, 1] are retained so headroom/limiting remains the
     * responsibility of the downstream stage rather than introducing clipping.
     */
    @Synchronized
    fun processInPlace(samples: FloatArray, frameCount: Int = samples.size / channelCount) {
        require(frameCount >= 0) { "Frame count cannot be negative" }
        require(frameCount * channelCount <= samples.size) {
            "Buffer is too small for the requested frame count"
        }
        if (bypassed || frameCount == 0) return

        val c = activeCoefficients
        var index = 0
        repeat(frameCount) {
            for (channel in 0 until channelCount) {
                val input = samples[index].toDouble()
                val output = c.b0 * input + z1[channel]
                z1[channel] = c.b1 * input - c.a1 * output + z2[channel]
                z2[channel] = c.b2 * input - c.a2 * output
                samples[index] = if (output.isFinite() && abs(output) < Float.MAX_VALUE) {
                    output.toFloat()
                } else {
                    0f
                }
                index++
            }
        }
    }
}
