package com.proton.proton_denoise

import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.min

/** Streaming state for live DTLN capture (see [MeetAudioDtlnWebParityState] for the active path). */
internal class MeetAudioDtlnStreamState {
    @Deprecated(
        "Legacy pipeline only (USE_WEB_PARITY = false). Remove with processLegacy.",
        level = DeprecationLevel.WARNING,
    )
    val pending16k = ArrayList<Float>()

    @Deprecated(
        "Legacy pipeline only (USE_WEB_PARITY = false). Remove with processLegacy.",
        level = DeprecationLevel.WARNING,
    )
    val ready16k = ArrayList<Float>()

    @Deprecated(
        "Legacy FIR resampler; web parity uses linear resample. Remove with processLegacy.",
        level = DeprecationLevel.WARNING,
    )
    val rateConverter = MeetAudioDtlnRateConverter()

    @Deprecated(
        "Mobile tail suppressor; not used in web-parity DTLN. Remove with MeetAudioTailSuppressor.",
        level = DeprecationLevel.WARNING,
    )
    val tail16k = MeetAudioTailSuppressorState()

    @Deprecated(
        "Mobile tail suppressor; not used in web-parity DTLN. Remove with MeetAudioTailSuppressor.",
        level = DeprecationLevel.WARNING,
    )
    val tailPostUpsample = MeetAudioTailSuppressorState()

    val webParity = MeetAudioDtlnWebParityState()

    @Suppress("DEPRECATION")
    fun reset() {
        pending16k.clear()
        ready16k.clear()
        rateConverter.reset()
        tail16k.reset()
        tailPostUpsample.reset()
        webParity.reset()
    }
}

/**
 * dtln-rs processing shared by [MeetAudioDtlnRsProcessor] and offline debug.
 *
 * **Active path** ([USE_WEB_PARITY] = true, mirrors ProtonMeet/noise-suppression worklet):
 * 1. Linear resample capture → 16 kHz mono
 * 2. Ring-buffer 512-sample `dtln_denoise` frames
 * 3. Drain output ring (silence until denoised samples ready)
 * 4. Linear resample → capture rate
 */
internal object MeetAudioDtlnPipeline {
    const val INTERNAL_SAMPLE_RATE_HZ = MeetAudioPcm.DTLN_SAMPLE_RATE_HZ

    /**
     * Match web [useAudioToggle] + ProtonMeet/noise-suppression worklet:
     * 16 kHz DTLN frames, ring buffers, no tail suppressor, no dry priming.
     */
    const val USE_WEB_PARITY = true

    @Deprecated(
        "Mobile tail expander; not in web DTLN. Only read when USE_WEB_PARITY is false.",
        level = DeprecationLevel.WARNING,
    )
    const val ENABLE_TAIL_SUPPRESSOR = false

    fun processInterleavedInPlace(
        handle: Long,
        sampleRateHz: Int,
        numChannels: Int,
        numFrames: Int,
        buffer: ByteBuffer,
        streamState: MeetAudioDtlnStreamState? = null,
    ) {
        if (handle == 0L || numFrames <= 0 || numChannels <= 0) {
            return
        }
        buffer.order(ByteOrder.nativeOrder())
        val frameCount = numFrames * numChannels
        val floats = FloatArray(frameCount)
        buffer.asFloatBuffer().get(floats, 0, frameCount)

        val mono = MeetAudioPcm.downmix(floats, numChannels)
        val state = streamState ?: MeetAudioDtlnStreamState()
        val denoisedAtRate =
            if (USE_WEB_PARITY) {
                processWebParity(handle, mono, sampleRateHz, state)
            } else {
                @Suppress("DEPRECATION")
                processLegacy(handle, mono, sampleRateHz, state)
            }
        val outInterleaved = MeetAudioPcm.upmixToChannels(
            denoisedAtRate,
            numChannels,
            mono.size,
        )

        buffer.rewind()
        buffer.asFloatBuffer().put(outInterleaved, 0, min(outInterleaved.size, frameCount))
    }

    private fun processWebParity(
        handle: Long,
        mono: FloatArray,
        sampleRateHz: Int,
        state: MeetAudioDtlnStreamState,
    ): FloatArray {
        val at16k = MeetAudioDtlnWebParity.resampleTo16k(mono, sampleRateHz)
        val out16k = MeetAudioDtlnWebParity.processAt16k(handle, at16k, state.webParity)
        return MeetAudioDtlnWebParity.resampleFrom16k(out16k, sampleRateHz, mono.size)
    }

    @Deprecated(
        "Pre-web-parity mobile pipeline (128-sample blocks, FIR resample, dry priming). " +
            "Remove when USE_WEB_PARITY is permanently true.",
        level = DeprecationLevel.WARNING,
    )
    @Suppress("DEPRECATION")
    private fun processLegacy(
        handle: Long,
        mono: FloatArray,
        sampleRateHz: Int,
        state: MeetAudioDtlnStreamState,
    ): FloatArray {
        val blockShift = ProtonDtlnRsNative.getBlockShift().coerceAtLeast(128)
        val at16k = state.rateConverter.downsample(mono, sampleRateHz, INTERNAL_SAMPLE_RATE_HZ)

        state.pending16k.addAll(at16k.toList())
        while (state.pending16k.size >= blockShift) {
            val block = FloatArray(blockShift)
            for (i in 0 until blockShift) {
                block[i] = state.pending16k.removeAt(0)
            }
            val direct = ByteBuffer.allocateDirect(block.size * 4).order(ByteOrder.nativeOrder())
            direct.asFloatBuffer().put(block)
            direct.rewind()
            if (!ProtonDtlnRsNative.denoiseInterleaved(handle, direct, block.size)) {
                return mono
            }
            direct.rewind()
            direct.asFloatBuffer().get(block)
            for (sample in block) {
                state.ready16k.add(sample)
            }
        }

        val out16k: FloatArray =
            if (state.ready16k.size >= at16k.size) {
                val out = FloatArray(at16k.size)
                for (i in out.indices) {
                    out[i] = state.ready16k.removeAt(0)
                }
                out
            } else {
                val denoisedCount = state.ready16k.size
                val blended = FloatArray(at16k.size)
                for (i in 0 until denoisedCount) {
                    blended[i] = state.ready16k.removeAt(0)
                }
                for (i in denoisedCount until at16k.size) {
                    blended[i] = at16k[i]
                }
                blended
            }

        if (ENABLE_TAIL_SUPPRESSOR) {
            MeetAudioTailSuppressor.apply(
                samples = out16k,
                sampleRateHz = INTERNAL_SAMPLE_RATE_HZ,
                state = state.tail16k,
                config = MeetAudioTailSuppressorConfig.dtln16k,
            )
        }

        var denoisedAtRate = state.rateConverter.upsample(
            out16k,
            INTERNAL_SAMPLE_RATE_HZ,
            sampleRateHz,
        )
        if (ENABLE_TAIL_SUPPRESSOR) {
            MeetAudioTailSuppressor.apply(
                samples = denoisedAtRate,
                sampleRateHz = sampleRateHz,
                state = state.tailPostUpsample,
                config = MeetAudioTailSuppressorConfig.dtlnPostUpsample,
            )
        }
        return MeetAudioPcm.fitToLength(denoisedAtRate, mono.size)
    }

    /** Offline mono file at [sampleRateHz] (use [MeetAudioPcm.WEBRTC_CAPTURE_SAMPLE_RATE_HZ] to match meetings). */
    fun denoiseMono(samples: FloatArray, sampleRateHz: Int, handle: Long): FloatArray {
        if (handle == 0L || samples.isEmpty()) {
            return samples
        }
        val buffer = ByteBuffer.allocateDirect(samples.size * 4).order(ByteOrder.nativeOrder())
        buffer.asFloatBuffer().put(samples)
        buffer.rewind()
        processInterleavedInPlace(handle, sampleRateHz, 1, samples.size, buffer)
        buffer.rewind()
        val out = FloatArray(samples.size)
        buffer.asFloatBuffer().get(out)
        return out
    }
}
