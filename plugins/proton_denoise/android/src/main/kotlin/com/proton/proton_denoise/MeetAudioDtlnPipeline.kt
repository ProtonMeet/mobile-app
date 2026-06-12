package com.proton.proton_denoise

import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.min

/** Streaming state for 16 kHz mono blocks (DTLN hop = 128 samples). */
internal class MeetAudioDtlnStreamState {
    val pending16k = ArrayList<Float>()
    val ready16k = ArrayList<Float>()
    val rateConverter = MeetAudioDtlnRateConverter()
    val tail16k = MeetAudioTailSuppressorState()
    val tailPostUpsample = MeetAudioTailSuppressorState()

    fun reset() {
        pending16k.clear()
        ready16k.clear()
        rateConverter.reset()
        tail16k.reset()
        tailPostUpsample.reset()
    }
}

/**
 * dtln-rs processing shared by [MeetAudioDtlnRsProcessor] and offline debug.
 * Internal rate is 16 kHz mono; resamples to/from WebRTC capture rate.
 */
internal object MeetAudioDtlnPipeline {
    const val INTERNAL_SAMPLE_RATE_HZ = MeetAudioPcm.DTLN_SAMPLE_RATE_HZ

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
        val blockShift = ProtonDtlnRsNative.getBlockShift().coerceAtLeast(128)
        val state = streamState ?: MeetAudioDtlnStreamState()
        val at16k = state.rateConverter.downsample(mono, sampleRateHz, INTERNAL_SAMPLE_RATE_HZ)

        // Feed real samples only — never zero-pad per WebRTC buffer (breaks overlap + adds noise).
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
                return
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

        MeetAudioTailSuppressor.apply(
            samples = out16k,
            sampleRateHz = INTERNAL_SAMPLE_RATE_HZ,
            state = state.tail16k,
            config = MeetAudioTailSuppressorConfig.dtln16k,
        )

        // 100% denoised — blending with undelayed dry causes a light echo (DTLN latency).
        val denoisedAtRate = state.rateConverter.upsample(
            out16k,
            INTERNAL_SAMPLE_RATE_HZ,
            sampleRateHz,
        )
        MeetAudioTailSuppressor.apply(
            samples = denoisedAtRate,
            sampleRateHz = sampleRateHz,
            state = state.tailPostUpsample,
            config = MeetAudioTailSuppressorConfig.dtlnPostUpsample,
        )
        val outInterleaved = MeetAudioPcm.upmixToChannels(
            denoisedAtRate,
            numChannels,
            frameCount / numChannels,
        )

        buffer.rewind()
        buffer.asFloatBuffer().put(outInterleaved, 0, min(outInterleaved.size, frameCount))
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
