package com.merrmist.muziinapmusic

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.log10
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

internal data class NativeEqBand(
    val type: String,
    val frequencyHz: Float,
    val gainDb: Float,
    val q: Float,
    val enabled: Boolean
)

internal data class NativeEqPoint(
    val frequencyHz: Float,
    val gainDb: Float
)

/**
 * Samples parametric biquad responses onto a logarithmic gain curve that the
 * platform DynamicsProcessing EQ can represent. DynamicsProcessing exposes
 * cutoff/gain bands, not arbitrary biquad Q or filter types, so this is an
 * approximation of the requested response rather than a native biquad chain.
 */
internal object NativeEqCurve {
    private const val SAMPLE_RATE_HZ = 48000.0
    private const val MIN_FREQUENCY_HZ = 20.1
    private const val MAX_FREQUENCY_HZ = 20000.0
    private const val MAX_GAIN_DB = 15.0
    private const val MIN_GAIN_DB = -15.0

    private data class Coefficients(
        val b0: Double,
        val b1: Double,
        val b2: Double,
        val a0: Double,
        val a1: Double,
        val a2: Double
    )

    fun convert(bands: List<NativeEqBand>, bandCount: Int = 128): List<NativeEqPoint> {
        require(bandCount in 1..128) { "DynamicsProcessing supports at most 128 EQ bands" }
        val active = bands.filter { it.enabled && it.frequencyHz.isFinite() && it.gainDb.isFinite() }
        val minLog = ln(MIN_FREQUENCY_HZ)
        val maxLog = ln(MAX_FREQUENCY_HZ)
        return List(bandCount) { index ->
            val fraction = if (bandCount == 1) 0.5 else index.toDouble() / (bandCount - 1)
            val frequency = exp(minLog + fraction * (maxLog - minLog))
            val gain = active.sumOf { band ->
                responseDb(band, frequency)
            }.coerceIn(MIN_GAIN_DB, MAX_GAIN_DB)
            NativeEqPoint(frequency.toFloat(), gain.toFloat())
        }
    }

    fun channelInputGains(baseInputGainDb: Float, balance: Float): Pair<Float, Float> {
        val pan = balance.coerceIn(-1f, 1f)
        val leftAttenuation = if (pan > 0f) {
            (20.0 * log10((1f - pan).coerceAtLeast(0.001f).toDouble())).toFloat()
        } else {
            0f
        }
        val rightAttenuation = if (pan < 0f) {
            (20.0 * log10((1f + pan).coerceAtLeast(0.001f).toDouble())).toFloat()
        } else {
            0f
        }
        return Pair(
            (baseInputGainDb + leftAttenuation).coerceIn(-60f, 15f),
            (baseInputGainDb + rightAttenuation).coerceIn(-60f, 15f)
        )
    }

    private fun responseDb(band: NativeEqBand, frequency: Double): Double {
        val center = band.frequencyHz.toDouble().coerceIn(20.0, 20000.0)
        val q = band.q.toDouble().coerceIn(0.1, 20.0)
        val gain = band.gainDb.toDouble().coerceIn(-15.0, 15.0)
        val coefficients = coefficients(band.type, center, gain, q) ?: return 0.0
        val omega = 2.0 * PI * frequency / SAMPLE_RATE_HZ
        val c1 = cos(omega)
        val s1 = sin(omega)
        val c2 = cos(2.0 * omega)
        val s2 = sin(2.0 * omega)
        val numeratorReal = coefficients.b0 + coefficients.b1 * c1 + coefficients.b2 * c2
        val numeratorImag = -coefficients.b1 * s1 - coefficients.b2 * s2
        val denominatorReal = coefficients.a0 + coefficients.a1 * c1 + coefficients.a2 * c2
        val denominatorImag = -coefficients.a1 * s1 - coefficients.a2 * s2
        val numerator = numeratorReal * numeratorReal + numeratorImag * numeratorImag
        val denominator = denominatorReal * denominatorReal + denominatorImag * denominatorImag
        if (!numerator.isFinite() || !denominator.isFinite() || denominator < 1e-24) return 0.0
        return 10.0 * log10((numerator / denominator).coerceAtLeast(1e-24))
    }

    private fun coefficients(type: String, frequency: Double, gainDb: Double, q: Double): Coefficients? {
        val f = frequency.coerceIn(20.0, SAMPLE_RATE_HZ / 2.0 - 1.0)
        val omega = 2.0 * PI * f / SAMPLE_RATE_HZ
        val c = cos(omega)
        val s = sin(omega)
        val alpha = s / (2.0 * q)
        val a = 10.0.pow(gainDb / 40.0)

        val raw = when (type) {
            "peaking" -> Coefficients(
                1.0 + alpha * a, -2.0 * c, 1.0 - alpha * a,
                1.0 + alpha / a, -2.0 * c, 1.0 - alpha / a
            )
            "lowPass" -> Coefficients(
                (1.0 - c) / 2.0, 1.0 - c, (1.0 - c) / 2.0,
                1.0 + alpha, -2.0 * c, 1.0 - alpha
            )
            "highPass" -> Coefficients(
                (1.0 + c) / 2.0, -(1.0 + c), (1.0 + c) / 2.0,
                1.0 + alpha, -2.0 * c, 1.0 - alpha
            )
            "bandPass" -> Coefficients(
                alpha, 0.0, -alpha,
                1.0 + alpha, -2.0 * c, 1.0 - alpha
            )
            "notch" -> Coefficients(
                1.0, -2.0 * c, 1.0,
                1.0 + alpha, -2.0 * c, 1.0 - alpha
            )
            "lowShelf", "highShelf" -> {
                val shelfAlpha = s / 2.0 * sqrt(
                    ((a + 1.0 / a) * (1.0 / q - 1.0) + 2.0).coerceAtLeast(0.0)
                )
                val beta = 2.0 * sqrt(a) * shelfAlpha
                if (type == "lowShelf") {
                    Coefficients(
                        a * ((a + 1.0) - (a - 1.0) * c + beta),
                        2.0 * a * ((a - 1.0) - (a + 1.0) * c),
                        a * ((a + 1.0) - (a - 1.0) * c - beta),
                        (a + 1.0) + (a - 1.0) * c + beta,
                        -2.0 * ((a - 1.0) + (a + 1.0) * c),
                        (a + 1.0) + (a - 1.0) * c - beta
                    )
                } else {
                    Coefficients(
                        a * ((a + 1.0) + (a - 1.0) * c + beta),
                        -2.0 * a * ((a - 1.0) + (a + 1.0) * c),
                        a * ((a + 1.0) + (a - 1.0) * c - beta),
                        (a + 1.0) - (a - 1.0) * c + beta,
                        2.0 * ((a - 1.0) - (a + 1.0) * c),
                        (a + 1.0) - (a - 1.0) * c - beta
                    )
                }
            }
            else -> return null
        }
        if (!listOf(raw.b0, raw.b1, raw.b2, raw.a0, raw.a1, raw.a2).all { it.isFinite() } ||
            abs(raw.a0) < 1e-12
        ) return null
        return Coefficients(
            raw.b0 / raw.a0,
            raw.b1 / raw.a0,
            raw.b2 / raw.a0,
            1.0,
            raw.a1 / raw.a0,
            raw.a2 / raw.a0
        )
    }
}
