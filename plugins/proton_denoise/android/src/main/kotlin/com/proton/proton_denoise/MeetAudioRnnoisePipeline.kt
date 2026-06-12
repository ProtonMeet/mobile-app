package com.proton.proton_denoise

import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * RNNoise processing shared by [MeetAudioRnnoiseProcessor] and offline debug.
 * Frame loop matches iOS [RnnoiseProcessor] (480-sample RNNoise frames at 48 kHz).
 */
internal object MeetAudioRnnoisePipeline {
    fun processInterleavedInPlace(
        handle: Long,
        buffer: ByteBuffer,
        numFrames: Int,
        numChannels: Int,
    ) {
        if (handle == 0L || numFrames <= 0 || numChannels <= 0 || !buffer.isDirect) {
            return
        }
        val frameSize = ProtonRnnoiseNative.getFrameSize()
        if (frameSize <= 0) {
            return
        }
        buffer.order(ByteOrder.nativeOrder())
        var frameStart = 0
        while (frameStart + frameSize <= numFrames) {
            val floatOffset = frameStart * numChannels
            ProtonRnnoiseNative.processInterleavedAt(
                handle,
                buffer,
                floatOffset,
                frameSize,
                numChannels,
            )
            frameStart += frameSize
        }
    }

    /** Offline / mono: batch path via C++ (handles v0.2 frame delay + flush). */
    fun denoiseMono(samples: FloatArray, sampleRateHz: Int, handle: Long): FloatArray {
        if (handle == 0L || samples.isEmpty()) {
            return samples
        }
        if (sampleRateHz != MeetAudioPcm.WEBRTC_CAPTURE_SAMPLE_RATE_HZ) {
            // RNNoise expects 48 kHz; callers should resample first.
        }
        ProtonRnnoiseNative.setEnabled(handle, true)
        val out = samples.copyOf()
        ProtonRnnoiseNative.processMonoInPlace(handle, out, 0, out.size)
        return out
    }
}
