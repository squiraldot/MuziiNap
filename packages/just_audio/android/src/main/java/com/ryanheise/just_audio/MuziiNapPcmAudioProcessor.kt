package com.ryanheise.just_audio

import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import org.json.JSONObject
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.tanh
import kotlin.math.pow

/** Live config shared by the host app and the player's audio sink. */
object MuziiNapDspController {
    @Volatile private var configJson: String = """{"enabled":false,"bands":[]}"""
    @Volatile private var configRevision: Long = 0L
    @Volatile var lastProcessDurationNs: Long = 0L
        private set
    @Volatile var processedBufferCount: Long = 0L
        private set

    @JvmStatic fun updateConfig(json: String) {
        // Parse before publishing so malformed slider payloads never replace a working config.
        JSONObject(json).getJSONArray("bands")
        configJson = json
        configRevision += 1L
    }

    @JvmStatic fun processingDurationNs(): Long = lastProcessDurationNs
    internal fun snapshot(): JSONObject = JSONObject(configJson)
    internal fun revision(): Long = configRevision
    internal fun recordDuration(startNs: Long) {
        lastProcessDurationNs = (System.nanoTime() - startNs).coerceAtLeast(0L)
        processedBufferCount += 1L
    }
}

/**
 * PCM16/float processor installed in just_audio's Media3 DefaultAudioSink.
 * Config updates are read at buffer boundaries; no player restart is required.
 */
class MuziiNapPcmAudioProcessor : BaseAudioProcessor() {
    private var channels = 0
    private var states = emptyList<Array<DoubleArray>>()
    private var signature = ""
    private var gains = floatArrayOf()
    private var sampleScratch = FloatArray(0)
    private var ceiling = 0.8912509f // -1 dBFS
    private var stereoWidth = 1f
    private var enabled = false
    private var limiterActive = true

    override fun onConfigure(inputAudioFormat: AudioProcessor.AudioFormat): AudioProcessor.AudioFormat {
        if (inputAudioFormat.encoding != C.ENCODING_PCM_16BIT &&
            inputAudioFormat.encoding != C.ENCODING_PCM_FLOAT) {
            channels = 0
            return AudioProcessor.AudioFormat.NOT_SET
        }
        if (inputAudioFormat.channelCount !in 1..8 || inputAudioFormat.sampleRate <= 0) {
            channels = 0
            return AudioProcessor.AudioFormat.NOT_SET
        }
        channels = inputAudioFormat.channelCount
        refreshConfig(inputAudioFormat.sampleRate)
        return inputAudioFormat
    }

    private fun refreshConfig(sampleRate: Int) {
        val revision = MuziiNapDspController.revision()
        val nextSignature = "$revision:$sampleRate:$channels"
        if (signature == nextSignature) return
        val config = MuziiNapDspController.snapshot()
        signature = nextSignature
        enabled = config.optBoolean("enabled", false)
        val advanced = config.optJSONObject("advancedDsp") ?: JSONObject()
        val preampDb = config.optDouble("preamp", 0.0).toFloat().coerceIn(-24f, 12f)
        val outputGainDb = config.optDouble("outputGain", 0.0).toFloat().coerceIn(-24f, 12f)
        val maxBoost = (config.optJSONArray("bands")?.let { bands ->
            (0 until bands.length()).maxOfOrNull { i ->
                val b = bands.optJSONObject(i)
                if (b != null && b.optBoolean("enabled", true)) b.optDouble("gainDb", 0.0).toFloat().coerceAtLeast(0f) else 0f
            } ?: 0f
        } ?: 0f).coerceAtMost(15f)
        // Keep sufficient pre-EQ headroom for summed positive band boosts.
        val compensation = (preampDb + outputGainDb - maxBoost).coerceIn(-36f, 12f)
        val linear = 10.0.pow(compensation / 20.0).toFloat()
        val balance = advanced.optDouble("stereoBalance", 0.0).toFloat().coerceIn(-1f, 1f)
        stereoWidth = advanced.optDouble("stereoWidth", 1.0).toFloat().coerceIn(0f, 2f)
        gains = FloatArray(channels) { channel ->
            val panGain = if (channels >= 2 && channel == 0 && balance > 0f) 1f - balance
                else if (channels >= 2 && channel == 1 && balance < 0f) 1f + balance
                else 1f
            linear * panGain.coerceAtLeast(0.001f)
        }
        val limiterEnabled = config.optBoolean("limiterEnabled", true)
        limiterActive = limiterEnabled
        val limiterDb = if (advanced.optBoolean("enabled", true)) {
            advanced.optDouble("limiterCeilingDb", -1.0).toFloat().coerceIn(-12f, 0f)
        } else -1f
        ceiling = if (limiterEnabled) 10.0.pow(limiterDb / 20.0).toFloat() else 1f

        val bands = config.optJSONArray("bands")
        val perChannel = ArrayList<Array<DoubleArray>>()
        for (channel in 0 until channels) {
            val channelStates = ArrayList<DoubleArray>()
            if (enabled && bands != null) {
                for (i in 0 until bands.length()) {
                    val band = bands.optJSONObject(i) ?: continue
                    if (!band.optBoolean("enabled", true)) continue
                    val frequency = band.optDouble("frequency", 1000.0).coerceIn(20.0, sampleRate / 2.0 - 1.0)
                    val gainDb = band.optDouble("gainDb", 0.0).coerceIn(-15.0, 15.0)
                    val q = band.optDouble("q", 1.0).coerceIn(0.1, 20.0)
                    val coeff = peaking(frequency, gainDb, q, sampleRate)
                    channelStates.add(doubleArrayOf(coeff[0], coeff[1], coeff[2], coeff[3], coeff[4], 0.0, 0.0))
                }
            }
            perChannel.add(channelStates.toTypedArray())
        }
        states = perChannel
    }

    private fun peaking(frequency: Double, gainDb: Double, q: Double, sampleRate: Int): DoubleArray {
        val w = 2.0 * PI * frequency / sampleRate
        val c = cos(w)
        val alpha = sin(w) / (2.0 * q)
        val a = 10.0.pow(gainDb / 40.0)
        val a0 = 1.0 + alpha / a
        return doubleArrayOf(
            (1.0 + alpha * a) / a0,
            (-2.0 * c) / a0,
            (1.0 - alpha * a) / a0,
            (-2.0 * c) / a0,
            (1.0 - alpha / a) / a0
        )
    }

    override fun queueInput(inputBuffer: ByteBuffer) {
        val format = inputAudioFormat
        val encoding = format.encoding
        val bytesPerSample = if (encoding == C.ENCODING_PCM_16BIT) 2 else 4
        val inputBytes = inputBuffer.remaining()
        val output = replaceOutputBuffer(inputBytes).order(ByteOrder.LITTLE_ENDIAN)
        val source = inputBuffer.slice().order(ByteOrder.LITTLE_ENDIAN)
        if (channels > 0) refreshConfig(format.sampleRate)
        if (!enabled || channels <= 0) {
            output.put(source)
            output.flip()
            inputBuffer.position(inputBuffer.limit())
            return
        }
        val usableSamples = (inputBytes / bytesPerSample) -
            (inputBytes / bytesPerSample) % channels
        if (sampleScratch.size < usableSamples) sampleScratch = FloatArray(usableSamples)
        val samples = sampleScratch
        for (index in 0 until usableSamples) {
            val sample = if (encoding == C.ENCODING_PCM_16BIT) source.short.toFloat() / 32768f else source.float
            samples[index] = if (sample.isFinite()) sample else 0f
        }
        if (channels >= 2 && stereoWidth != 1f) {
            for (frame in 0 until usableSamples / channels) {
                val leftIndex = frame * channels
                val rightIndex = leftIndex + 1
                val mid = (samples[leftIndex] + samples[rightIndex]) * 0.5f
                val side = (samples[leftIndex] - samples[rightIndex]) * 0.5f * stereoWidth
                samples[leftIndex] = mid + side
                samples[rightIndex] = mid - side
            }
        }
        val startNs = System.nanoTime()
        for (index in 0 until usableSamples) {
            val channel = index % channels
            var value = samples[index] * gains.getOrElse(channel) { 1f }
            for (state in states.getOrElse(channel) { emptyArray() }) {
                val y = state[0] * value + state[5]
                state[5] = state[1] * value - state[3] * y + state[6]
                state[6] = state[2] * value - state[4] * y
                value = if (y.isFinite() && abs(y) < Float.MAX_VALUE) y.toFloat() else 0f
            }
            // Soft-knee limiting reduces hard-clipping distortion while enforcing
            // the configured peak ceiling as the final safety net.
            val magnitude = abs(value)
            val kneeStart = ceiling * 0.8f
            if (limiterActive && magnitude > kneeStart) {
                val width = (ceiling - kneeStart).coerceAtLeast(1e-5f)
                val limited = kneeStart + width * tanh(((magnitude - kneeStart) / width).toDouble()).toFloat()
                value = if (value < 0f) -limited else limited
            }
            if (encoding == C.ENCODING_PCM_16BIT) {
                output.putShort((value * 32768f).toInt().coerceIn(-32768, 32767).toShort())
            } else {
                output.putFloat(value)
            }
        }
        while (source.hasRemaining()) output.put(source.get())
        inputBuffer.position(inputBuffer.limit())
        output.flip()
        MuziiNapDspController.recordDuration(startNs)
    }

    override fun onFlush() {
        states.forEach { channel -> channel.forEach { state -> state[5] = 0.0; state[6] = 0.0 } }
    }

    override fun onReset() {
        channels = 0
        states = emptyList()
        signature = ""
        gains = floatArrayOf()
        sampleScratch = FloatArray(0)
        stereoWidth = 1f
    }
}
