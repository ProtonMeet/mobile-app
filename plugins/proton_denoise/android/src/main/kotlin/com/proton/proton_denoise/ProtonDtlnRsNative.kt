package com.proton.proton_denoise

import android.util.Log
import java.nio.ByteBuffer

/** JNI bridge to dtln-rs via [proton_dtln_api.h] in `libproton_denoise.so`. */
internal object ProtonDtlnRsNative {
    private const val TAG = "ProtonDtlnRsNative"

    val isAvailable: Boolean by lazy {
        try {
            System.loadLibrary("proton_denoise")
            val probe = nativeCreate()
            if (probe != 0L) {
                nativeDestroy(probe)
            }
            probe != 0L
        } catch (e: UnsatisfiedLinkError) {
            Log.w(TAG, "libproton_denoise.so not loaded", e)
            false
        } catch (e: Throwable) {
            Log.w(TAG, "dtln-rs create failed", e)
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
        if (handle == 0L) {
            return
        }
        nativeDestroy(handle)
    }

    fun getSampleRate(): Int =
        if (isAvailable) {
            nativeGetSampleRate()
        } else {
            0
        }

    fun getBlockShift(): Int =
        if (isAvailable) {
            nativeGetBlockShift()
        } else {
            0
        }

    fun denoiseInterleaved(handle: Long, buffer: ByteBuffer, sampleCount: Int): Boolean {
        if (handle == 0L || !buffer.isDirect || sampleCount <= 0) {
            return false
        }
        return nativeDenoiseInterleaved(handle, buffer, sampleCount) == 0
    }

    private external fun nativeCreate(): Long

    private external fun nativeDestroy(handle: Long)

    private external fun nativeGetSampleRate(): Int

    private external fun nativeGetBlockShift(): Int

    private external fun nativeDenoiseInterleaved(
        handle: Long,
        buffer: ByteBuffer,
        sampleCount: Int,
    ): Int
}
