package com.proton.proton_denoise

import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Web-parity DTLN (ProtonMeet/noise-suppression AudioWorklet).
 *
 * Active in-call path when [MeetAudioDtlnPipeline.USE_WEB_PARITY] is true:
 * linear 48↔16 resample, 512-sample ring-buffered `dtln_denoise`, silence until output ready.
 */
internal class MeetAudioDtlnWebParityState {
    val inputRing = ArrayList<Float>()
    val outputRing = ArrayList<Float>()

    fun reset() {
        inputRing.clear()
        outputRing.clear()
    }
}

internal object MeetAudioDtlnWebParity {
    /** Matches web [DENOISE_FRAME_SAMPLES] in audio-worklet-processor.ts */
    const val FRAME_SAMPLES = 512

    fun resampleTo16k(mono: FloatArray, sampleRateHz: Int): FloatArray {
        if (sampleRateHz == MeetAudioPcm.DTLN_SAMPLE_RATE_HZ || mono.isEmpty()) {
            return mono
        }
        return MeetAudioPcm.resample(mono, sampleRateHz, MeetAudioPcm.DTLN_SAMPLE_RATE_HZ)
    }

    fun resampleFrom16k(mono16k: FloatArray, sampleRateHz: Int, targetFrames: Int): FloatArray {
        if (sampleRateHz == MeetAudioPcm.DTLN_SAMPLE_RATE_HZ || mono16k.isEmpty()) {
            return MeetAudioPcm.fitToLength(mono16k, targetFrames)
        }
        val upsampled = MeetAudioPcm.resample(
            mono16k,
            MeetAudioPcm.DTLN_SAMPLE_RATE_HZ,
            sampleRateHz,
        )
        return MeetAudioPcm.fitToLength(upsampled, targetFrames)
    }

    fun processAt16k(
        handle: Long,
        at16k: FloatArray,
        state: MeetAudioDtlnWebParityState,
    ): FloatArray {
        if (handle == 0L || at16k.isEmpty()) {
            return at16k
        }
        state.inputRing.addAll(at16k.toList())
        while (state.inputRing.size >= FRAME_SAMPLES) {
            val block = FloatArray(FRAME_SAMPLES)
            for (i in 0 until FRAME_SAMPLES) {
                block[i] = state.inputRing.removeAt(0)
            }
            val direct = ByteBuffer.allocateDirect(block.size * 4).order(ByteOrder.nativeOrder())
            direct.asFloatBuffer().put(block)
            direct.rewind()
            if (!ProtonDtlnRsNative.denoiseInterleaved(handle, direct, block.size)) {
                return FloatArray(at16k.size)
            }
            direct.rewind()
            direct.asFloatBuffer().get(block)
            for (sample in block) {
                state.outputRing.add(sample)
            }
        }
        return drainSilencePadded(state.outputRing, at16k.size)
    }

    private fun drainSilencePadded(ring: ArrayList<Float>, count: Int): FloatArray {
        val out = FloatArray(count)
        val available = minOf(count, ring.size)
        for (i in 0 until available) {
            out[i] = ring.removeAt(0)
        }
        return out
    }
}
