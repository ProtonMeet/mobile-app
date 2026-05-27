package com.proton.proton_denoise

import com.cloudwebrtc.webrtc.audio.AudioProcessingAdapter
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * DeepFilter stub — compiles and runs in the capture chain without changing samples.
 */
internal class MeetAudioDeepFilterProcessor : AudioProcessingAdapter.ExternalAudioFrameProcessing {
    private var enabled = false

    fun setEnabled(value: Boolean) {
        enabled = value
    }

    override fun initialize(sampleRateHz: Int, numChannels: Int) {
        // Stub until DeepFilter model ships.
    }

    override fun reset(newRate: Int) {}

    override fun process(numBands: Int, numFrames: Int, buffer: ByteBuffer) {
        if (!enabled) {
            return
        }
        buffer.order(ByteOrder.nativeOrder())
    }

    companion object {
        const val isNativeReady: Boolean = true
    }
}
