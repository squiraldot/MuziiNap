package com.ryanheise.just_audio

import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.ByteBuffer
import java.nio.ByteOrder

class MuziiNapPcmAudioProcessorTest {
    @Test
    fun limiterKeepsFloatOutputFiniteAndBelowConfiguredCeiling() {
        MuziiNapDspController.updateConfig(
            """{"enabled":true,"preamp":0,"outputGain":0,"limiterEnabled":true,"bands":[],"advancedDsp":{"enabled":true,"limiterCeilingDb":-6}}"""
        )
        val processor = MuziiNapPcmAudioProcessor()
        processor.configure(AudioProcessor.AudioFormat(48000, 1, C.ENCODING_PCM_FLOAT))
        processor.flush()

        val input = ByteBuffer.allocateDirect(12).order(ByteOrder.LITTLE_ENDIAN)
        input.putFloat(1.0f)
        input.putFloat(-1.0f)
        input.putFloat(Float.NaN)
        input.flip()
        processor.queueInput(input)
        val output = processor.output.order(ByteOrder.LITTLE_ENDIAN)

        assertEquals(12, output.remaining())
        val positive = output.float
        val negative = output.float
        val invalid = output.float
        assertTrue(positive <= 0.502f && positive >= 0f)
        assertTrue(negative >= -0.502f && negative <= 0f)
        assertEquals(0f, invalid, 0f)
    }

    @Test
    fun pcm16OutputIsBoundedAndPreservesChannelFrames() {
        MuziiNapDspController.updateConfig(
            """{"enabled":true,"preamp":0,"outputGain":0,"limiterEnabled":true,"bands":[],"advancedDsp":{"enabled":true,"limiterCeilingDb":-1}}"""
        )
        val processor = MuziiNapPcmAudioProcessor()
        processor.configure(AudioProcessor.AudioFormat(44100, 2, C.ENCODING_PCM_16BIT))
        processor.flush()

        val input = ByteBuffer.allocateDirect(8).order(ByteOrder.LITTLE_ENDIAN)
        input.putShort(32767.toShort())
        input.putShort((-32768).toShort())
        input.putShort(12000.toShort())
        input.putShort((-12000).toShort())
        input.flip()
        processor.queueInput(input)
        val output = processor.output.order(ByteOrder.LITTLE_ENDIAN)

        assertEquals(8, output.remaining())
        val left = output.short.toInt()
        val right = output.short.toInt()
        assertTrue(left in 0..32767)
        assertTrue(right in -32768..0)
        assertTrue(kotlin.math.abs(kotlin.math.abs(output.short.toInt()) - 12000) <= 2500)
        assertTrue(kotlin.math.abs(kotlin.math.abs(output.short.toInt()) - 12000) <= 2500)
    }

    @Test
    fun stereoWidthProcessesLeftAndRightAsMidSidePair() {
        MuziiNapDspController.updateConfig(
            """{"enabled":true,"bands":[],"limiterEnabled":false,"advancedDsp":{"enabled":true,"stereoWidth":2}}"""
        )
        val processor = MuziiNapPcmAudioProcessor()
        processor.configure(AudioProcessor.AudioFormat(48000, 2, C.ENCODING_PCM_FLOAT))
        processor.flush()

        val input = ByteBuffer.allocateDirect(8).order(ByteOrder.LITTLE_ENDIAN)
        input.putFloat(1f)
        input.putFloat(0f)
        input.flip()
        processor.queueInput(input)
        val output = processor.output.order(ByteOrder.LITTLE_ENDIAN)

        assertEquals(1.5f, output.float, 1e-6f)
        assertEquals(-0.5f, output.float, 1e-6f)
    }

    @Test
    fun liveConfigUpdateTakesEffectWithoutReconfiguringProcessor() {
        MuziiNapDspController.updateConfig("""{"enabled":false,"bands":[]}""")
        val processor = MuziiNapPcmAudioProcessor()
        processor.configure(AudioProcessor.AudioFormat(48000, 1, C.ENCODING_PCM_FLOAT))
        processor.flush()

        val before = ByteBuffer.allocateDirect(4).order(ByteOrder.LITTLE_ENDIAN)
        before.putFloat(0.75f)
        before.flip()
        processor.queueInput(before)
        assertEquals(0.75f, processor.output.order(ByteOrder.LITTLE_ENDIAN).float, 1e-6f)

        MuziiNapDspController.updateConfig(
            """{"enabled":true,"limiterEnabled":true,"bands":[],"advancedDsp":{"enabled":true,"limiterCeilingDb":-12}}"""
        )
        val after = ByteBuffer.allocateDirect(4).order(ByteOrder.LITTLE_ENDIAN)
        after.putFloat(0.75f)
        after.flip()
        processor.queueInput(after)
        val limited = processor.output.order(ByteOrder.LITTLE_ENDIAN).float
        assertTrue(limited < 0.32f)
        assertTrue(limited > 0f)
    }

    @Test
    fun flushClearsFilterHistoryForSeekAndTrackTransitions() {
        MuziiNapDspController.updateConfig(
            """{"enabled":true,"bands":[{"enabled":true,"frequency":1000,"gainDb":9,"q":1}],"limiterEnabled":false}"""
        )
        val processor = MuziiNapPcmAudioProcessor()
        processor.configure(AudioProcessor.AudioFormat(48000, 1, C.ENCODING_PCM_FLOAT))
        processor.flush()

        val impulse = ByteBuffer.allocateDirect(8).order(ByteOrder.LITTLE_ENDIAN)
        impulse.putFloat(1f)
        impulse.putFloat(0f)
        impulse.flip()
        processor.queueInput(impulse)
        processor.output

        processor.flush()
        val silence = ByteBuffer.allocateDirect(4).order(ByteOrder.LITTLE_ENDIAN)
        silence.putFloat(0f)
        silence.flip()
        processor.queueInput(silence)
        assertEquals(0f, processor.output.order(ByteOrder.LITTLE_ENDIAN).float, 1e-6f)
    }

    @Test
    fun disabledProcessorIsFormatPreservingNoOp() {
        MuziiNapDspController.updateConfig("""{"enabled":false,"bands":[]}""")
        val processor = MuziiNapPcmAudioProcessor()
        processor.configure(AudioProcessor.AudioFormat(48000, 1, C.ENCODING_PCM_FLOAT))
        processor.flush()

        val input = ByteBuffer.allocateDirect(4).order(ByteOrder.LITTLE_ENDIAN)
        input.putFloat(0.375f)
        input.flip()
        processor.queueInput(input)
        val output = processor.output.order(ByteOrder.LITTLE_ENDIAN)

        assertEquals(0.375f, output.float, 1e-6f)
    }

    @Test
    fun eqBandProducesMeasurableFrequencySelectiveOutputChange() {
        MuziiNapDspController.updateConfig(
            """{"enabled":true,"preamp":0,"outputGain":0,"limiterEnabled":false,"bands":[{"enabled":true,"frequency":1000,"gainDb":12,"q":1}],"advancedDsp":{"enabled":true}}"""
        )
        val processor = MuziiNapPcmAudioProcessor()
        processor.configure(AudioProcessor.AudioFormat(48000, 1, C.ENCODING_PCM_FLOAT))
        processor.flush()

        fun renderTone(frequencyHz: Int): Double {
            val samples = 4800
            val input = ByteBuffer.allocateDirect(samples * 4).order(ByteOrder.LITTLE_ENDIAN)
            for (i in 0 until samples) {
                input.putFloat((0.2 * kotlin.math.sin(2.0 * Math.PI * frequencyHz * i / 48000.0)).toFloat())
            }
            input.flip()
            processor.queueInput(input)
            val output = processor.output.order(ByteOrder.LITTLE_ENDIAN)
            var sumSquares = 0.0
            var count = 0
            while (output.remaining() >= 4) {
                val value = output.float.toDouble()
                if (count >= 480) sumSquares += value * value // Ignore filter startup transient.
                count++
            }
            processor.flush()
            return kotlin.math.sqrt(sumSquares / (count - 480))
        }

        val boostedToneRms = renderTone(1000)
        val outOfBandToneRms = renderTone(10000)
        assertTrue("EQ target frequency should measurably exceed the out-of-band output", boostedToneRms > outOfBandToneRms * 2.5)
    }

    @Test
    fun processingDurationIsRecordedForEnabledDspBuffers() {
        MuziiNapDspController.updateConfig(
            """{"enabled":true,"bands":[{"enabled":true,"frequency":1000,"gainDb":3,"q":1}],"limiterEnabled":true}"""
        )
        val processor = MuziiNapPcmAudioProcessor()
        processor.configure(AudioProcessor.AudioFormat(48000, 2, C.ENCODING_PCM_FLOAT))
        processor.flush()

        val previousProcessedBufferCount = MuziiNapDspController.processedBufferCount
        val frames = 2400
        val input = ByteBuffer.allocateDirect(frames * 2 * 4).order(ByteOrder.LITTLE_ENDIAN)
        repeat(frames) {
            input.putFloat(0.1f)
            input.putFloat(-0.1f)
        }
        input.flip()
        processor.queueInput(input)

        assertEquals(frames * 2 * 4, processor.output.remaining())
        assertTrue("DSP timing should be available after a processed buffer", MuziiNapDspController.processingDurationNs() > 0L)
        assertEquals(previousProcessedBufferCount + 1L, MuziiNapDspController.processedBufferCount)
    }

    @Test
    fun invalidLiveConfigDoesNotReplaceLastValidConfig() {
        MuziiNapDspController.updateConfig(
            """{"enabled":true,"limiterEnabled":true,"bands":[],"advancedDsp":{"enabled":true,"limiterCeilingDb":-12}}"""
        )
        try {
            MuziiNapDspController.updateConfig("""{"enabled":true,"bands":null}""")
        } catch (_: Exception) {
            // The invalid update is expected to be rejected atomically.
        }

        val processor = MuziiNapPcmAudioProcessor()
        processor.configure(AudioProcessor.AudioFormat(48000, 1, C.ENCODING_PCM_FLOAT))
        processor.flush()
        val input = ByteBuffer.allocateDirect(4).order(ByteOrder.LITTLE_ENDIAN)
        input.putFloat(0.75f)
        input.flip()
        processor.queueInput(input)

        val result = processor.output.order(ByteOrder.LITTLE_ENDIAN).float
        assertTrue("Previously valid limiter config must remain active", result in 0f..0.26f)
    }

    @Test
    fun repeatedBuffersRemainFiniteAndFrameAlignedDuringLongPlaybackSequence() {
        MuziiNapDspController.updateConfig(
            """{"enabled":true,"bands":[{"enabled":true,"frequency":250,"gainDb":6,"q":0.8}],"limiterEnabled":true,"advancedDsp":{"enabled":true,"limiterCeilingDb":-1}}"""
        )
        val processor = MuziiNapPcmAudioProcessor()
        processor.configure(AudioProcessor.AudioFormat(48000, 2, C.ENCODING_PCM_FLOAT))
        processor.flush()

        repeat(300) { bufferIndex ->
            val input = ByteBuffer.allocateDirect(512 * 2 * 4).order(ByteOrder.LITTLE_ENDIAN)
            repeat(512) { frame ->
                val sample = (0.7 * kotlin.math.sin(2.0 * Math.PI * (bufferIndex * 512 + frame) * 440.0 / 48000.0)).toFloat()
                input.putFloat(sample)
                input.putFloat(-sample)
            }
            input.flip()
            processor.queueInput(input)
            val output = processor.output.order(ByteOrder.LITTLE_ENDIAN)
            assertEquals("Every buffer must preserve stereo frame alignment", 512 * 2 * 4, output.remaining())
            while (output.remaining() >= 4) {
                val value = output.float
                assertTrue("Output samples must remain finite", value.isFinite())
                assertTrue("Limiter must keep output within full scale", kotlin.math.abs(value) <= 1f)
            }
        }
    }

    @Test
    fun reconfigureAfterChannelAndSampleRateChangeDoesNotReuseOldFilterState() {
        MuziiNapDspController.updateConfig(
            """{"enabled":true,"bands":[{"enabled":true,"frequency":1000,"gainDb":9,"q":1}],"limiterEnabled":false}"""
        )
        val processor = MuziiNapPcmAudioProcessor()
        processor.configure(AudioProcessor.AudioFormat(48000, 1, C.ENCODING_PCM_FLOAT))
        processor.flush()
        val impulse = ByteBuffer.allocateDirect(4).order(ByteOrder.LITTLE_ENDIAN)
        impulse.putFloat(1f)
        impulse.flip()
        processor.queueInput(impulse)
        processor.output

        processor.configure(AudioProcessor.AudioFormat(44100, 2, C.ENCODING_PCM_FLOAT))
        processor.flush()
        val silence = ByteBuffer.allocateDirect(8).order(ByteOrder.LITTLE_ENDIAN)
        silence.putFloat(0f)
        silence.putFloat(0f)
        silence.flip()
        processor.queueInput(silence)
        val output = processor.output.order(ByteOrder.LITTLE_ENDIAN)
        assertEquals(0f, output.float, 1e-6f)
        assertEquals(0f, output.float, 1e-6f)
    }

}
