package com.proton.proton_denoise

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin

/**
 * Legacy 48 kHz ↔ 16 kHz FIR resamplers for the pre-web-parity DTLN path.
 *
 * @deprecated Web-parity DTLN uses [MeetAudioPcm.resample] instead. The decimator here also
 *   produced fewer samples than expected per WebRTC buffer (length mismatch). Remove with
 *   [MeetAudioDtlnPipeline.processLegacy].
 */
@Deprecated(
    "Legacy DTLN resampler; web parity uses linear resample. Remove with processLegacy.",
    level = DeprecationLevel.WARNING,
)
internal object MeetAudioFirResampler {
    private const val TAPS = 45
    internal const val FACTOR = 3

    private val decimateKernel: FloatArray = buildLowpassKernel(gain = 1f)
    private val interpolatePhases: Array<FloatArray> = buildInterpolatePhases()

    fun createDecimator(): FirDecimateBy3 = FirDecimateBy3(decimateKernel)

    fun createInterpolator(): FirInterpolateBy3 = FirInterpolateBy3(interpolatePhases)

    private fun buildLowpassKernel(gain: Float): FloatArray {
        val cutoffHz = 7_600.0
        val sampleRateHz = MeetAudioPcm.WEBRTC_CAPTURE_SAMPLE_RATE_HZ.toDouble()
        val fc = cutoffHz / sampleRateHz
        val mid = (TAPS - 1) / 2.0
        val raw = DoubleArray(TAPS)
        for (n in 0 until TAPS) {
            val x = n - mid
            val sinc =
                if (kotlin.math.abs(x) < 1e-9) {
                    2.0 * PI * fc
                } else {
                    sin(2.0 * PI * fc * x) / x
                }
            val window = 0.54 - 0.46 * cos(2.0 * PI * n / (TAPS - 1))
            raw[n] = sinc * window
        }
        val sum = raw.sum().toFloat().coerceAtLeast(1e-6f)
        return FloatArray(TAPS) { i -> raw[i].toFloat() / sum * gain }
    }

    private fun buildInterpolatePhases(): Array<FloatArray> {
        val kernel = buildLowpassKernel(gain = FACTOR.toFloat())
        val phaseLen = TAPS / FACTOR
        return Array(FACTOR) { phase ->
            FloatArray(phaseLen) { tap -> kernel[tap * FACTOR + phase] }
        }
    }
}

/** @deprecated See [MeetAudioFirResampler]. */
@Deprecated(
    "Legacy DTLN decimator; remove with MeetAudioFirResampler.",
    level = DeprecationLevel.WARNING,
)
internal class FirDecimateBy3(
    private val kernel: FloatArray,
) {
    private val window = FloatArray(kernel.size)
    private var windowFill = 0
    private var samplesSinceOutput = 0

    fun reset() {
        window.fill(0f)
        windowFill = 0
        samplesSinceOutput = 0
    }

    fun process(input: FloatArray): FloatArray {
        if (input.isEmpty()) {
            return FloatArray(0)
        }
        val out = ArrayList<Float>(input.size / MeetAudioFirResampler.FACTOR + 1)
        for (sample in input) {
            if (windowFill < kernel.size) {
                window[windowFill++] = sample
                if (windowFill == kernel.size) {
                    samplesSinceOutput = 0
                    out.add(convolve(window))
                    samplesSinceOutput = 1
                }
                continue
            }
            window.copyInto(window, destinationOffset = 0, startIndex = 1, endIndex = kernel.size)
            window[kernel.size - 1] = sample
            samplesSinceOutput++
            if (samplesSinceOutput >= MeetAudioFirResampler.FACTOR) {
                out.add(convolve(window))
                samplesSinceOutput = 0
            }
        }
        return out.toFloatArray()
    }

    private fun convolve(samples: FloatArray): Float {
        var sum = 0f
        for (i in kernel.indices) {
            sum += samples[i] * kernel[i]
        }
        return sum
    }
}

/** @deprecated See [MeetAudioFirResampler]. */
@Deprecated(
    "Legacy DTLN interpolator; remove with MeetAudioFirResampler.",
    level = DeprecationLevel.WARNING,
)
internal class FirInterpolateBy3(
    private val phases: Array<FloatArray>,
) {
    private val history = FloatArray(phases[0].size - 1)
    private var historyFill = 0

    fun reset() {
        history.fill(0f)
        historyFill = 0
    }

    fun process(input: FloatArray): FloatArray {
        if (input.isEmpty()) {
            return FloatArray(0)
        }
        val out = FloatArray(input.size * MeetAudioFirResampler.FACTOR)
        var outIndex = 0
        for (sample in input) {
            for (phase in phases.indices) {
                out[outIndex++] = convolvePhase(sample, phases[phase])
            }
            pushHistory(sample)
        }
        return out
    }

    private fun pushHistory(sample: Float) {
        if (historyFill < history.size) {
            history[historyFill++] = sample
            return
        }
        history.copyInto(history, destinationOffset = 0, startIndex = 1, endIndex = history.size)
        history[history.size - 1] = sample
    }

    private fun convolvePhase(sample: Float, phaseKernel: FloatArray): Float {
        var sum = 0f
        for (i in phaseKernel.indices) {
            val rel = i - (phaseKernel.size - 1)
            val value =
                when {
                    rel < -historyFill -> 0f
                    rel < 0 -> history[historyFill + rel]
                    rel == 0 -> sample
                    else -> 0f
                }
            sum += value * phaseKernel[i]
        }
        return sum
    }
}

/** @deprecated See [MeetAudioFirResampler]. */
@Deprecated(
    "Legacy DTLN rate converter; remove with processLegacy.",
    level = DeprecationLevel.WARNING,
)
internal class MeetAudioDtlnRateConverter {
    private var decimator: FirDecimateBy3? = null
    private var interpolator: FirInterpolateBy3? = null

    fun downsample(mono: FloatArray, fromRate: Int, toRate: Int): FloatArray {
        if (fromRate == toRate || mono.isEmpty()) {
            return mono
        }
        if (fromRate == MeetAudioPcm.WEBRTC_CAPTURE_SAMPLE_RATE_HZ &&
            toRate == MeetAudioPcm.DTLN_SAMPLE_RATE_HZ
        ) {
            val d = decimator ?: MeetAudioFirResampler.createDecimator().also { decimator = it }
            return d.process(mono)
        }
        return MeetAudioPcm.resample(mono, fromRate, toRate)
    }

    fun upsample(mono: FloatArray, fromRate: Int, toRate: Int): FloatArray {
        if (fromRate == toRate || mono.isEmpty()) {
            return mono
        }
        if (fromRate == MeetAudioPcm.DTLN_SAMPLE_RATE_HZ &&
            toRate == MeetAudioPcm.WEBRTC_CAPTURE_SAMPLE_RATE_HZ
        ) {
            val i = interpolator ?: MeetAudioFirResampler.createInterpolator().also { interpolator = it }
            val upsampled = i.process(mono)
            return fitLength(upsampled, expectedLength(mono.size, fromRate, toRate))
        }
        return MeetAudioPcm.resample(mono, fromRate, toRate)
    }

    fun reset() {
        decimator?.reset()
        interpolator?.reset()
        decimator = null
        interpolator = null
    }

    private fun expectedLength(inputLen: Int, fromRate: Int, toRate: Int): Int =
        ((inputLen.toLong() * toRate) / fromRate).toInt().coerceAtLeast(1)

    private fun fitLength(samples: FloatArray, targetLen: Int): FloatArray {
        if (samples.size == targetLen) {
            return samples
        }
        if (samples.size > targetLen) {
            return samples.copyOf(targetLen)
        }
        val out = samples.copyOf(targetLen)
        val last = samples.lastOrNull() ?: 0f
        for (i in samples.size until targetLen) {
            out[i] = last
        }
        return out
    }
}
