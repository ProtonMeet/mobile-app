package com.proton.proton_denoise

import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * DeepFilterNet processing shared by [MeetAudioDeepFilterProcessor].
 * Frame loop matches iOS [DeepFilterProcessor] (per-channel df_process_frame chunks).
 */
internal object MeetAudioDeepFilterPipeline {
    fun processInterleavedInPlace(
        handle: Long,
        buffer: ByteBuffer,
        numFrames: Int,
        numChannels: Int,
    ) {
        if (handle == 0L || numFrames <= 0 || numChannels <= 0 || !buffer.isDirect) {
            return
        }
        val frameSize = ProtonDeepFilterNative.getFrameSize(handle)
        if (frameSize <= 0) {
            return
        }
        buffer.order(ByteOrder.nativeOrder())
        var frameStart = 0
        while (frameStart + frameSize <= numFrames) {
            val floatOffset = frameStart * numChannels
            ProtonDeepFilterNative.processInterleavedAt(
                handle,
                buffer,
                floatOffset,
                frameSize,
                numChannels,
            )
            frameStart += frameSize
        }
    }
}
