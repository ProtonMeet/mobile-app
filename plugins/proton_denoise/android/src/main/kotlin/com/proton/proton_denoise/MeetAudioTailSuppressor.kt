package com.proton.proton_denoise

import kotlin.math.abs
import kotlin.math.exp

/**
 * Mobile-only DTLN post-process (not in web / web-parity path).
 *
 * @deprecated Disabled via [MeetAudioDtlnPipeline.ENABLE_TAIL_SUPPRESSOR]. Remove with
 *   [MeetAudioDtlnPipeline.processLegacy].
 */
@Deprecated(
    "Mobile-only DTLN tail expander; not used in web-parity path. Remove with processLegacy.",
    level = DeprecationLevel.WARNING,
)
internal data class MeetAudioTailSuppressorState(
    var levelEnvelope: Float = 0f,
    var tailLowpass: Float = 0f,
) {
    fun reset() {
        levelEnvelope = 0f
        tailLowpass = 0f
    }
}

@Deprecated(
    "Mobile-only DTLN tail expander; not used in web-parity path. Remove with processLegacy.",
    level = DeprecationLevel.WARNING,
)
internal data class MeetAudioTailSuppressorConfig(
    val openLevel: Float,
    val minGain: Float,
    val speechReleaseSec: Double,
    val tailReleaseSec: Double,
    val tailLowpassBlend: Float,
    val lowpassGainThreshold: Float,
) {
    companion object {
        /** Primary DTLN pass at 16 kHz — targets word-tail electrical / musical noise. */
        val dtln16k = MeetAudioTailSuppressorConfig(
            openLevel = 0.006f,
            minGain = 0.02f,
            speechReleaseSec = 0.038,
            tailReleaseSec = 0.01,
            tailLowpassBlend = 0.45f,
            lowpassGainThreshold = 0.94f,
        )

        /** Light second pass after 48 kHz upsample — catches residual hash without dulling speech. */
        val dtlnPostUpsample = MeetAudioTailSuppressorConfig(
            openLevel = 0.0045f,
            minGain = 0.07f,
            speechReleaseSec = 0.035,
            tailReleaseSec = 0.008,
            tailLowpassBlend = 0.38f,
            lowpassGainThreshold = 0.9f,
        )
    }
}

/** @deprecated See [MeetAudioTailSuppressorState]. */
@Deprecated(
    "Mobile-only DTLN tail expander; not used in web-parity path. Remove with processLegacy.",
    level = DeprecationLevel.WARNING,
)
internal object MeetAudioTailSuppressor {
    fun apply(
        samples: FloatArray,
        sampleRateHz: Int,
        state: MeetAudioTailSuppressorState,
        config: MeetAudioTailSuppressorConfig,
    ) {
        if (samples.isEmpty() || sampleRateHz <= 0) {
            return
        }
        val releaseSpeech = releaseCoeff(config.speechReleaseSec, sampleRateHz)
        val releaseTail = releaseCoeff(config.tailReleaseSec, sampleRateHz)
        var envelope = state.levelEnvelope
        var lowpass = state.tailLowpass

        for (i in samples.indices) {
            val magnitude = abs(samples[i])
            envelope =
                if (magnitude > envelope) {
                    0.1f * magnitude + 0.9f * envelope
                } else {
                    val release = if (envelope < config.openLevel) releaseTail else releaseSpeech
                    release * envelope + (1f - release) * magnitude
                }

            val gain =
                if (envelope >= config.openLevel) {
                    1f
                } else {
                    val ratio = (envelope / config.openLevel).coerceIn(0f, 1f)
                    config.minGain + (1f - config.minGain) * ratio * ratio * ratio
                }

            var sample = samples[i] * gain
            if (gain < config.lowpassGainThreshold) {
                lowpass = (1f - config.tailLowpassBlend) * lowpass + config.tailLowpassBlend * sample
                sample = lowpass
            } else {
                lowpass = sample
            }
            samples[i] = sample
        }

        state.levelEnvelope = envelope
        state.tailLowpass = lowpass
    }

    private fun releaseCoeff(seconds: Double, sampleRateHz: Int): Float {
        return exp(-1.0 / (seconds * sampleRateHz)).toFloat()
    }
}
