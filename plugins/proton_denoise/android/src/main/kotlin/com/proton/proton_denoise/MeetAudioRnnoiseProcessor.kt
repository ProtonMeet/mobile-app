package com.proton.proton_denoise

import com.cloudwebrtc.webrtc.audio.AudioProcessingAdapter
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * RNNoise capture processor for flutter-webrtc's capture post-processing chain.
 */
internal class MeetAudioRnnoiseProcessor :
    MeetAudioCaptureProcessor {
    private val lock = Any()
    private var enabled = false
    private var numChannels = 1
    private var handle: Long = 0L

    override fun setEnabled(value: Boolean) {
        synchronized(lock) {
            enabled = value
            if (value) {
                ensureHandleLocked()
            }
            if (handle != 0L) {
                ProtonRnnoiseNative.setEnabled(handle, value)
            }
        }
    }

    override fun initialize(sampleRateHz: Int, numChannels: Int) {
        synchronized(lock) {
            this.numChannels = numChannels.coerceAtLeast(1)
            ensureHandleLocked()
        }
    }

    override fun reset(newRate: Int) {
        // RNNoise frame size is fixed; sample rate changes do not require re-init today.
    }

    override fun process(numBands: Int, numFrames: Int, buffer: ByteBuffer) {
        synchronized(lock) {
            if (!enabled || numFrames <= 0 || handle == 0L) {
                return
            }
            val channels = effectiveChannels(numFrames, buffer)
            if (channels <= 0) {
                return
            }
            buffer.order(ByteOrder.nativeOrder())
            MeetAudioRnnoisePipeline.processInterleavedInPlace(
                handle,
                buffer,
                numFrames,
                channels,
            )
        }
    }

    /** WebRTC may call [initialize] before attach; infer channels from the buffer when needed. */
    private fun effectiveChannels(numFrames: Int, buffer: ByteBuffer): Int {
        if (numChannels > 0) {
            return numChannels
        }
        val floatCount = buffer.capacity() / Float.SIZE_BYTES
        if (numFrames <= 0 || floatCount % numFrames != 0) {
            return 1
        }
        return (floatCount / numFrames).coerceAtLeast(1)
    }

    private fun ensureHandleLocked() {
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

    override fun release() {
        synchronized(lock) {
            enabled = false
            if (handle != 0L) {
                ProtonRnnoiseNative.destroy(handle)
                handle = 0L
            }
        }
    }

    companion object {
        val isNativeReady: Boolean
            get() {
                if (!ProtonRnnoiseNative.isAvailable) {
                    return false
                }
                val handle = ProtonRnnoiseNative.create()
                if (handle == 0L) {
                    return false
                }
                val frameSize = ProtonRnnoiseNative.getFrameSize()
                ProtonRnnoiseNative.destroy(handle)
                return frameSize > 0
            }
    }
}
