package com.proton.proton_denoise

import android.util.Log
import java.nio.ByteBuffer

/** JNI bridge to [proton_rnnoise_api.h] in `libproton_denoise.so`. */
internal object ProtonRnnoiseNative {
    private const val TAG = "ProtonRnnoiseNative"

    val isAvailable: Boolean by lazy {
        try {
            System.loadLibrary("proton_denoise")
            true
        } catch (e: UnsatisfiedLinkError) {
            Log.w(TAG, "libproton_denoise.so not loaded", e)
            false
        }
    }

    fun create(): Long {
        if (!isAvailable) {
            return 0L
        }
        return nativeCreate()
    }

    fun destroy(handle: Long) {
        if (handle == 0L || !isAvailable) {
            return
        }
        nativeDestroy(handle)
    }

    fun getFrameSize(): Int =
        if (isAvailable) {
            nativeGetFrameSize()
        } else {
            0
        }

    fun setEnabled(handle: Long, enabled: Boolean) {
        if (handle == 0L || !isAvailable) {
            return
        }
        nativeSetEnabled(handle, enabled)
    }

    fun processInterleaved(
        handle: Long,
        buffer: ByteBuffer,
        numFrames: Int,
        numChannels: Int,
    ): Float {
        if (handle == 0L || !isAvailable || !buffer.isDirect) {
            return 0f
        }
        return nativeProcessInterleaved(handle, buffer, numFrames, numChannels)
    }

    /** One RNNoise frame of mono PCM — matches iOS [RnnoiseProcessor] frame loop. */
    fun processMonoInPlace(
        handle: Long,
        samples: FloatArray,
        offset: Int,
        frameSize: Int,
    ): Float {
        if (handle == 0L || !isAvailable || frameSize <= 0) {
            return 0f
        }
        return nativeProcessMonoInPlace(handle, samples, offset, frameSize)
    }

    /** One RNNoise frame at a float offset inside a direct WebRTC capture buffer. */
    fun processInterleavedAt(
        handle: Long,
        buffer: ByteBuffer,
        floatOffset: Int,
        numFrames: Int,
        numChannels: Int,
    ): Float {
        if (handle == 0L || !isAvailable || !buffer.isDirect || numFrames <= 0) {
            return 0f
        }
        return nativeProcessInterleavedAt(
            handle,
            buffer,
            floatOffset,
            numFrames,
            numChannels,
        )
    }

    private external fun nativeCreate(): Long

    private external fun nativeDestroy(handle: Long)

    private external fun nativeGetFrameSize(): Int

    private external fun nativeSetEnabled(handle: Long, enabled: Boolean)

    private external fun nativeProcessInterleaved(
        handle: Long,
        buffer: ByteBuffer,
        numFrames: Int,
        numChannels: Int,
    ): Float

    private external fun nativeProcessMonoInPlace(
        handle: Long,
        samples: FloatArray,
        offset: Int,
        frameSize: Int,
    ): Float

    private external fun nativeProcessInterleavedAt(
        handle: Long,
        buffer: ByteBuffer,
        floatOffset: Int,
        numFrames: Int,
        numChannels: Int,
    ): Float
}
