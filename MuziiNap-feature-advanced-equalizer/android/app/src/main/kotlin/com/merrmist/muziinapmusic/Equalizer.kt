package com.merrmist.muziinapmusic

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.audiofx.AudioEffect
import android.media.audiofx.DynamicsProcessing
import android.media.audiofx.Virtualizer
import android.os.Build
import androidx.annotation.Keep
import org.json.JSONObject
import java.util.concurrent.ConcurrentHashMap

@Keep
class Equalizer {
    private val dynamicsProcessors = ConcurrentHashMap<Int, DynamicsProcessing>()
    private val virtualizers = ConcurrentHashMap<Int, Virtualizer>()

    fun openEqualizer(sessionId: Int, context: Context, activity: Activity): Boolean {
        val intent = Intent(AudioEffect.ACTION_DISPLAY_AUDIO_EFFECT_CONTROL_PANEL).apply {
            putExtra(AudioEffect.EXTRA_PACKAGE_NAME, context.packageName)
            putExtra(AudioEffect.EXTRA_AUDIO_SESSION, sessionId)
            putExtra(AudioEffect.EXTRA_CONTENT_TYPE, AudioEffect.CONTENT_TYPE_MUSIC)
        }
        if (intent.resolveActivity(context.packageManager) != null) {
            activity.startActivityForResult(intent, 0)
            return true
        }

        return openManufacturerEqualizer(sessionId, context, activity) ||
            openSoundSettings(activity)
    }

    /**
     * Applies the complete MuziiNap DSP chain to one Android audio session.
     *
     * API 28+ provides the native chain:
     * input gain -> PreEQ -> MBC -> PostEQ -> Limiter.
     * SoundFX controls are translated into deterministic gain/drive parameters
     * inside that same chain. Surround uses the platform Virtualizer when supported.
     */
    fun applyEqualizerConfig(sessionId: Int, configJson: String): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P || sessionId <= 0) {
            return false
        }

        return try {
            val config = JSONObject(configJson)
            val enabled = config.optBoolean("enabled", true)
            val preamp = config.optDouble("preamp", 0.0).toFloat()
            val outputGain = config.optDouble("outputGain", 0.0).toFloat()
            val limiterEnabled = config.optBoolean("limiterEnabled", true)
            val bands = config.optJSONArray("bands") ?: return false
            val advanced = config.optJSONObject("advancedDsp") ?: JSONObject()
            val advancedEnabled = advanced.optBoolean("enabled", true)

            if (bands.length() > MAX_PARAMETRIC_BANDS) {
                return false
            }

            val nativeCurve = NativeEqCurve.convert(
                (0 until bands.length()).map { index ->
                    val band = bands.getJSONObject(index)
                    NativeEqBand(
                        type = band.optString("type", "peaking"),
                        frequencyHz = band.optDouble("frequency", 1000.0).toFloat(),
                        gainDb = band.optDouble("gainDb", 0.0).toFloat(),
                        q = band.optDouble("q", 1.0).toFloat(),
                        enabled = band.optBoolean("enabled", true)
                    )
                },
                bandCount = MAX_EQ_BANDS
            )

            val probe = DynamicsProcessing(sessionId)
            val channelCount = probe.channelCount
            probe.release()

            if (channelCount <= 0) {
                return false
            }

            val postEqBandCount = 4
            val mbcBandCount = 4
            val builder = DynamicsProcessing.Config.Builder(
                DynamicsProcessing.VARIANT_FAVOR_FREQUENCY_RESOLUTION,
                channelCount,
                true,
                nativeCurve.size,
                true,
                mbcBandCount,
                true,
                postEqBandCount,
                true
            )

            val totalInputGain = calculateInputGain(
                preamp,
                outputGain,
                advanced.apply {
                    put("bandsForHeadroom", bands)
                    put(
                        "nativeCurveMaxBoostDb",
                        nativeCurve.maxOfOrNull { it.gainDb.coerceAtLeast(0f) } ?: 0f
                    )
                },
                advancedEnabled
            )
            builder.setInputGainAllChannelsTo(totalInputGain)
            configureStereoBalance(
                builder,
                channelCount,
                advanced,
                advancedEnabled,
                totalInputGain
            )

            val processor = DynamicsProcessing(
                0,
                sessionId,
                builder.build()
            )

            val cutoffs = calculateCutoffs(nativeCurve)
            for (channel in 0 until channelCount) {
                for (bandIndex in nativeCurve.indices) {
                    val gain = nativeCurve[bandIndex].gainDb
                        .coerceIn(-15f, 15f)
                    processor.setPreEqBandByChannelIndex(
                        channel,
                        bandIndex,
                        DynamicsProcessing.EqBand(
                            enabled,
                            cutoffs[bandIndex],
                            gain
                        )
                    )
                }

                configureAdvancedMbc(processor, channel, advanced, advancedEnabled)
                configureAdvancedPostEq(processor, channel, advanced, advancedEnabled)

                val ceiling = if (advancedEnabled) {
                    advanced.optDouble("limiterCeilingDb", -1.0)
                        .toFloat()
                        .coerceIn(-12f, 0f)
                } else {
                    -1f
                }
                val release = if (advancedEnabled) {
                    advanced.optDouble("limiterReleaseMs", 80.0)
                        .toFloat()
                        .coerceIn(10f, 1000f)
                } else {
                    80f
                }

                processor.setLimiterByChannelIndex(
                    channel,
                    DynamicsProcessing.Limiter(
                        true,
                        limiterEnabled && enabled,
                        0,
                        1f,
                        release,
                        20f,
                        ceiling,
                        0f
                    )
                )
            }

            processor.enabled = enabled

            val oldProcessor = dynamicsProcessors.put(sessionId, processor)
            oldProcessor?.release()

            configureVirtualizer(sessionId, advanced, advancedEnabled)

            true
        } catch (_: Throwable) {
            false
        }
    }

    fun releaseEqualizer(sessionId: Int) {
        dynamicsProcessors.remove(sessionId)?.release()
        virtualizers.remove(sessionId)?.release()
    }

    fun initAudioEffect(sessionId: Int, context: Context) {
        sendAudioEffectIntent(
            sessionId,
            AudioEffect.ACTION_OPEN_AUDIO_EFFECT_CONTROL_SESSION,
            context
        )
    }

    fun endAudioEffect(sessionId: Int, context: Context) {
        releaseEqualizer(sessionId)
        sendAudioEffectIntent(
            sessionId,
            AudioEffect.ACTION_CLOSE_AUDIO_EFFECT_CONTROL_SESSION,
            context
        )
    }

    private fun configureStereoBalance(
        builder: DynamicsProcessing.Config.Builder,
        channelCount: Int,
        advanced: JSONObject,
        advancedEnabled: Boolean,
        baseInputGainDb: Float
    ) {
        if (!advancedEnabled || channelCount < 2) return

        val balance = advanced.optDouble("stereoBalance", 0.0)
            .toFloat()
            .coerceIn(-1f, 1f)
        val (leftGainDb, rightGainDb) =
            NativeEqCurve.channelInputGains(baseInputGainDb, balance)

        // Preserve preamp/headroom compensation while attenuating only the
        // channel opposite the requested balance direction.
        builder.setInputGainByChannelIndex(0, leftGainDb)
        builder.setInputGainByChannelIndex(1, rightGainDb)
    }

    private fun configureAdvancedMbc(
        processor: DynamicsProcessing,
        channel: Int,
        advanced: JSONObject,
        advancedEnabled: Boolean
    ) {
        val compressorEnabled = advancedEnabled &&
            advanced.optBoolean("compressorEnabled", false)
        val dynamicBassEnabled = advancedEnabled &&
            advanced.optBoolean("dynamicBassEnabled", false)
        val mbcEnabled = compressorEnabled || dynamicBassEnabled

        val threshold = advanced.optDouble("compressorThresholdDb", -18.0)
            .toFloat().coerceIn(-60f, 0f)
        val ratio = advanced.optDouble("compressorRatio", 2.0)
            .toFloat().coerceIn(1f, 20f)
        val attack = advanced.optDouble("compressorAttackMs", 10.0)
            .toFloat().coerceIn(0.1f, 100f)
        val release = advanced.optDouble("compressorReleaseMs", 120.0)
            .toFloat().coerceIn(10f, 1000f)
        val knee = advanced.optDouble("compressorKneeDb", 6.0)
            .toFloat().coerceIn(0f, 40f)
        val makeup = advanced.optDouble("compressorMakeupGainDb", 0.0)
            .toFloat().coerceIn(-12f, 12f)
        val dynamicBass = advanced.optDouble("dynamicBassAmountDb", 0.0)
            .toFloat().coerceIn(0f, 12f)

        val cutoffs = floatArrayOf(120f, 1000f, 5000f, 20000f)
        for (band in cutoffs.indices) {
            val isLowBand = band == 0
            val preGain = if (dynamicBassEnabled && isLowBand) dynamicBass else 0f
            val postGain = if (compressorEnabled) makeup else 0f
            val bandRatio = if (compressorEnabled) ratio else 1f
            val bandThreshold = if (compressorEnabled) threshold else 0f
            val bandAttack = if (compressorEnabled) attack else 1f
            val bandRelease = if (compressorEnabled) release else 60f
            val bandKnee = if (compressorEnabled) knee else 0f

            processor.setMbcBandByChannelIndex(
                channel,
                band,
                DynamicsProcessing.MbcBand(
                    mbcEnabled,
                    cutoffs[band],
                    bandAttack,
                    bandRelease,
                    bandRatio,
                    bandThreshold,
                    bandKnee,
                    -60f,
                    1f,
                    preGain,
                    postGain
                )
            )
        }

        processor.setMbcByChannelIndex(
            channel,
            DynamicsProcessing.Mbc(
                true,
                mbcEnabled,
                cutoffs.size
            )
        )
    }

    private fun configureAdvancedPostEq(
        processor: DynamicsProcessing,
        channel: Int,
        advanced: JSONObject,
        advancedEnabled: Boolean
    ) {
        val bassBoost = if (advancedEnabled &&
            advanced.optBoolean("bassBoostEnabled", false)
        ) {
            advanced.optDouble("bassBoostAmountDb", 0.0).toFloat().coerceIn(0f, 12f)
        } else 0f

        val xBass = if (advancedEnabled &&
            advanced.optBoolean("soundFxEnabled", false)
        ) {
            advanced.optDouble("xBassAmountDb", 0.0).toFloat().coerceIn(0f, 12f)
        } else 0f

        val powerBass = if (advancedEnabled &&
            advanced.optBoolean("soundFxEnabled", false)
        ) {
            advanced.optDouble("powerBassAmountDb", 0.0).toFloat().coerceIn(0f, 12f)
        } else 0f

        val xTreble = if (advancedEnabled &&
            advanced.optBoolean("soundFxEnabled", false)
        ) {
            advanced.optDouble("xTrebleAmountDb", 0.0).toFloat().coerceIn(0f, 12f)
        } else 0f

        val loudness = if (advancedEnabled &&
            advanced.optBoolean("loudnessEnabled", false)
        ) {
            advanced.optDouble("loudnessAmountDb", 0.0).toFloat().coerceIn(0f, 12f)
        } else 0f

        val lowGain = (bassBoost + xBass + powerBass * 0.75f + loudness * 0.45f)
            .coerceIn(-15f, 15f)
        val lowMidGain = (powerBass * 0.35f + loudness * 0.15f)
            .coerceIn(-15f, 15f)
        val highMidGain = (xTreble * 0.35f + loudness * 0.15f)
            .coerceIn(-15f, 15f)
        val highGain = (xTreble + loudness * 0.45f)
            .coerceIn(-15f, 15f)

        val bassFrequency = advanced.optDouble("bassBoostFrequencyHz", 70.0)
            .toFloat().coerceIn(40f, 180f)
        val bassQ = advanced.optDouble("bassBoostQ", 0.9)
            .toFloat().coerceIn(0.2f, 2f)
        // DynamicsProcessing EqBand exposes cutoff rather than Q. Use the
        // next band edge to approximate the requested bass bandwidth.
        val bassWidthCutoff = (bassFrequency * (1f + 2f / bassQ))
            .coerceIn(bassFrequency + 0.1f, 350f)

        val cutoffs = floatArrayOf(
            bassFrequency,
            bassWidthCutoff,
            5000f,
            16000f
        )
        val gains = floatArrayOf(lowGain, lowMidGain, highMidGain, highGain)

        for (band in cutoffs.indices) {
            processor.setPostEqBandByChannelIndex(
                channel,
                band,
                DynamicsProcessing.EqBand(
                    true,
                    cutoffs[band],
                    gains[band]
                )
            )
        }

        processor.setPostEqByChannelIndex(
            channel,
            DynamicsProcessing.Eq(
                true,
                true,
                cutoffs.size
            )
        )
    }

    private fun configureVirtualizer(
        sessionId: Int,
        advanced: JSONObject,
        advancedEnabled: Boolean
    ) {
        val surroundEnabled = advancedEnabled &&
            advanced.optBoolean("surroundEnabled", false)
        val stereoWidth = advanced.optDouble("stereoWidth", 1.0)
            .toFloat().coerceIn(1f, 2f)
        val widthEnhancement = (stereoWidth - 1f).coerceIn(0f, 1f)
        val surroundAmount = if (surroundEnabled) {
            advanced.optDouble("surroundAmount", 0.0)
                .toFloat().coerceIn(0f, 1f)
        } else {
            0f
        }
        val effectiveAmount = maxOf(surroundAmount, widthEnhancement)
        if (effectiveAmount <= 0f) {
            virtualizers.remove(sessionId)?.release()
            return
        }

        try {
            val virtualizer = Virtualizer(0, sessionId)
            if (!virtualizer.getStrengthSupported()) {
                virtualizer.release()
                virtualizers.remove(sessionId)?.release()
                return
            }

            virtualizer.setStrength((effectiveAmount * 1000f).toInt().toShort())
            virtualizer.enabled = true

            val old = virtualizers.put(sessionId, virtualizer)
            old?.release()
        } catch (_: Throwable) {
            virtualizers.remove(sessionId)?.release()
        }
    }

    private fun calculateInputGain(
        preamp: Float,
        outputGain: Float,
        advanced: JSONObject,
        advancedEnabled: Boolean
    ): Float {
        var gain = preamp + outputGain

        if (advancedEnabled && advanced.optBoolean("loudnessEnabled", false)) {
            val loudness = advanced.optDouble("loudnessAmountDb", 0.0)
                .toFloat().coerceIn(0f, 12f)
            gain -= loudness
        }

        if (advancedEnabled && advanced.optBoolean("compressorEnabled", false)) {
            val makeup = advanced.optDouble("compressorMakeupGainDb", 0.0)
                .toFloat().coerceIn(-12f, 12f)
            if (makeup > 0f) gain -= makeup
        }

        var peakBoost = advanced.optDouble("nativeCurveMaxBoostDb", Double.NaN)
            .toFloat()
        if (!peakBoost.isFinite()) {
            peakBoost = 0f
            for (index in 0 until advanced.optJSONArray("bandsForHeadroom")?.length().orZero()) {
                val band = advanced.optJSONArray("bandsForHeadroom")?.optJSONObject(index)
                if (band != null && band.optBoolean("enabled", true)) {
                    peakBoost = maxOf(
                        peakBoost,
                        band.optDouble("gainDb", 0.0).toFloat().coerceIn(0f, 15f)
                    )
                }
            }
        } else {
            peakBoost = peakBoost.coerceIn(0f, 15f)
        }

        if (advancedEnabled && advanced.optBoolean("bassBoostEnabled", false)) {
            peakBoost += advanced.optDouble("bassBoostAmountDb", 0.0)
                .toFloat().coerceIn(0f, 12f)
        }
        if (advancedEnabled && advanced.optBoolean("soundFxEnabled", false)) {
            val xBass = advanced.optDouble("xBassAmountDb", 0.0)
                .toFloat().coerceIn(0f, 12f)
            val xTreble = advanced.optDouble("xTrebleAmountDb", 0.0)
                .toFloat().coerceIn(0f, 12f)
            val powerBass = advanced.optDouble("powerBassAmountDb", 0.0)
                .toFloat().coerceIn(0f, 12f)
            peakBoost += maxOf(xBass, xTreble, powerBass * 0.75f)
        }

        gain -= peakBoost.coerceAtMost(15f)
        return gain.coerceIn(-15f, 15f)
    }

    private fun Int?.orZero(): Int = this ?: 0

    private fun calculateCutoffs(curve: List<NativeEqPoint>): FloatArray =
        FloatArray(curve.size) { curve[it].frequencyHz }

    private fun sendAudioEffectIntent(
        sessionId: Int,
        action: String,
        context: Context
    ) {
        val intent = Intent(action).apply {
            putExtra(AudioEffect.EXTRA_PACKAGE_NAME, context.packageName)
            putExtra(AudioEffect.EXTRA_AUDIO_SESSION, sessionId)
            putExtra(AudioEffect.EXTRA_CONTENT_TYPE, AudioEffect.CONTENT_TYPE_MUSIC)
        }
        context.sendBroadcast(intent)
    }

    private fun openManufacturerEqualizer(
        sessionId: Int,
        context: Context,
        activity: Activity
    ): Boolean {
        val equalizerPackages = listOf(
            "com.android.settings.Settings\$SoundSettingsActivity",
            "com.android.settings.EqualizerSettings",
            "com.samsung.android.soundalive",
            "com.miui.audioeffect",
            "com.oneplus.sound.tuner"
        )

        for (packageName in equalizerPackages) {
            try {
                val intent = context.packageManager.getLaunchIntentForPackage(packageName)
                if (intent != null) {
                    intent.putExtra(AudioEffect.EXTRA_AUDIO_SESSION, sessionId)
                    intent.putExtra(AudioEffect.EXTRA_PACKAGE_NAME, context.packageName)
                    activity.startActivity(intent)
                    return true
                }
            } catch (_: Exception) {
            }
        }
        return false
    }

    private fun openSoundSettings(activity: Activity): Boolean {
        return try {
            activity.startActivity(Intent(android.provider.Settings.ACTION_SOUND_SETTINGS))
            true
        } catch (_: Exception) {
            false
        }
    }

    companion object {
        private const val MAX_PARAMETRIC_BANDS = 12
        private const val MAX_EQ_BANDS = 128
    }
}
