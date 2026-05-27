package com.proton.proton_denoise

import com.cloudwebrtc.webrtc.audio.AudioProcessingAdapter
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * RNNoise capture processor for flutter-webrtc's capture post-processing chain.
 */
internal class MeetAudioRnnoiseProcessor : AudioProcessingAdapter.ExternalAudioFrameProcessing {
    private var enabled = false
    private var numChannels = 1
    private var handle: Long = 0L

    fun setEnabled(value: Boolean) {
        enabled = value
        if (handle != 0L) {
            ProtonRnnoiseNative.setEnabled(handle, value)
        }
    }

    override fun initialize(sampleRateHz: Int, numChannels: Int) {
        this.numChannels = numChannels.coerceAtLeast(1)
        ensureHandle()
    }

    override fun reset(newRate: Int) {
        // RNNoise frame size is fixed; sample rate changes do not require re-init today.
    }

    override fun process(numBands: Int, numFrames: Int, buffer: ByteBuffer) {
        if (!enabled || handle == 0L || numFrames <= 0 || numChannels <= 0) {
            return
        }
        // WebRTC capture post-processing uses a single full-band buffer on Android.
        if (numBands != 1) {
            return
        }
        buffer.order(ByteOrder.nativeOrder())
        ProtonRnnoiseNative.processInterleaved(handle, buffer, numFrames, numChannels)
    }

    private fun ensureHandle() {
        if (handle != 0L) {
            return
        }
        if (!ProtonRnnoiseNative.isAvailable) {
            return
        }
        val created = ProtonRnnoiseNative.create()
        if (created == 0L) {
            return
        }
        handle = created
        ProtonRnnoiseNative.setEnabled(handle, enabled)
    }

    fun release() {
        if (handle != 0L) {
            ProtonRnnoiseNative.destroy(handle)
            handle = 0L
        }
    }

    companion object {
        val isNativeReady: Boolean
            get() = ProtonRnnoiseNative.isAvailable
    }
}
