package com.proton.proton_denoise

import com.cloudwebrtc.webrtc.audio.AudioProcessingAdapter
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * dtln-rs capture processor (16 kHz mono internally; resamples WebRTC PCM).
 */
internal class MeetAudioDtlnRsProcessor : MeetAudioCaptureProcessor {
    private val lock = Any()
    private var enabled = false
    private var numChannels = 1
    private var sampleRateHz = MeetAudioPcm.WEBRTC_CAPTURE_SAMPLE_RATE_HZ
    private var handle: Long = 0L
    private val streamState = MeetAudioDtlnStreamState()

    override fun setEnabled(value: Boolean) {
        synchronized(lock) {
            enabled = value
            if (value) {
                ensureHandleLocked()
            } else {
                streamState.reset()
            }
        }
    }

    override fun initialize(sampleRateHz: Int, numChannels: Int) {
        synchronized(lock) {
            this.sampleRateHz = sampleRateHz.coerceAtLeast(1)
            this.numChannels = numChannels.coerceAtLeast(1)
            streamState.reset()
            ensureHandleLocked()
        }
    }

    override fun reset(newRate: Int) {
        synchronized(lock) {
            sampleRateHz = newRate.coerceAtLeast(1)
        }
    }

    override fun process(numBands: Int, numFrames: Int, buffer: ByteBuffer) {
        synchronized(lock) {
            if (!enabled || numFrames <= 0 || handle == 0L || numChannels <= 0) {
                return
            }
            buffer.order(ByteOrder.nativeOrder())
            MeetAudioDtlnPipeline.processInterleavedInPlace(
                handle,
                sampleRateHz,
                numChannels,
                numFrames,
                buffer,
                streamState,
            )
        }
    }

    override fun release() {
        synchronized(lock) {
            enabled = false
            streamState.reset()
            if (handle != 0L) {
                ProtonDtlnRsNative.destroy(handle)
                handle = 0L
            }
        }
    }

    private fun ensureHandleLocked() {
        if (handle != 0L || !ProtonDtlnRsNative.isAvailable) {
            return
        }
        handle = ProtonDtlnRsNative.create()
    }

    companion object {
        val isNativeReady: Boolean
            get() = ProtonDtlnRsNative.isAvailable
    }
}
