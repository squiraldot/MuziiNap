package com.merrmist.muziinapmusic

/**
 * Runs a sequence of stateful PCM stages in order, in-place.
 *
 * The chain is intentionally independent of playback ownership. It can be
 * attached to an ExoPlayer AudioProcessor once the app owns/configures that
 * pipeline; creating a chain alone does not change audio emitted by just_audio.
 */
internal class PcmDspChain(
    private val stages: List<PcmBiquadProcessor>,
    private val channelCount: Int
) {
    init {
        require(channelCount in 1..8) { "Channel count must be between 1 and 8" }
        require(stages.isNotEmpty()) { "At least one DSP stage is required" }
    }

    @Synchronized
    fun processInPlace(samples: FloatArray, frameCount: Int = samples.size / channelCount) {
        require(frameCount >= 0) { "Frame count cannot be negative" }
        require(frameCount * channelCount <= samples.size) {
            "Buffer is too small for the requested frame count"
        }
        for (stage in stages) {
            stage.processInPlace(samples, frameCount)
        }
    }

    @Synchronized
    fun reset() {
        stages.forEach(PcmBiquadProcessor::reset)
    }
}
