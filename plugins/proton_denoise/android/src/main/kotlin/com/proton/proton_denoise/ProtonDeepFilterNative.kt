package com.proton.proton_denoise

import android.util.Log
import java.nio.ByteBuffer

/** JNI bridge to [proton_deepfilter_api.h] via dlopen'd libdeepfilter.so. */
internal object ProtonDeepFilterNative {
    private const val TAG = "ProtonDeepFilterNative"
    private const val LIB_DEEPFILTER = "deepfilter"

    private var protonDenoiseLoaded = false
    private var deepFilterLoaded = false

    val isAvailable: Boolean
        get() = ensureProtonDenoiseLoaded() && ensureDeepFilterLoaded()

    fun create(modelPath: String): Long {
        if (!isAvailable || modelPath.isBlank()) {
            return 0L
        }
        return nativeCreate(modelPath)
    }

    fun destroy(handle: Long) {
        if (handle == 0L || !ensureProtonDenoiseLoaded()) {
            return
        }
        nativeDestroy(handle)
    }

    fun getFrameSize(handle: Long): Int =
        if (handle != 0L && ensureProtonDenoiseLoaded()) {
            nativeGetFrameSize(handle)
        } else {
            0
        }

    fun setEnabled(handle: Long, enabled: Boolean) {
        if (handle == 0L || !ensureProtonDenoiseLoaded()) {
            return
        }
        nativeSetEnabled(handle, enabled)
    }

    fun processInterleavedAt(
        handle: Long,
        buffer: ByteBuffer,
        floatOffset: Int,
        numFrames: Int,
        numChannels: Int,
    ): Float {
        if (handle == 0L || !ensureProtonDenoiseLoaded() || !buffer.isDirect || numFrames <= 0) {
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

    private fun ensureProtonDenoiseLoaded(): Boolean {
        if (protonDenoiseLoaded) {
            return true
        }
        return try {
            System.loadLibrary("proton_denoise")
            protonDenoiseLoaded = true
            true
        } catch (e: UnsatisfiedLinkError) {
            Log.w(TAG, "libproton_denoise.so not loaded", e)
            false
        }
    }

    private fun ensureDeepFilterLoaded(): Boolean {
        if (deepFilterLoaded) {
            return true
        }
        if (!ensureProtonDenoiseLoaded()) {
            return false
        }
        return try {
            System.loadLibrary(LIB_DEEPFILTER)
            val bound = nativeEnsureLoaded()
            if (!bound) {
                Log.w(TAG, "libdeepfilter.so loaded but df_* symbols missing")
                return false
            }
            deepFilterLoaded = true
            true
        } catch (e: UnsatisfiedLinkError) {
            Log.w(TAG, "libdeepfilter.so not loaded", e)
            false
        }
    }

    private external fun nativeEnsureLoaded(): Boolean

    private external fun nativeCreate(modelPath: String): Long

    private external fun nativeDestroy(handle: Long)

    private external fun nativeGetFrameSize(handle: Long): Int

    private external fun nativeSetEnabled(handle: Long, enabled: Boolean)

    private external fun nativeProcessInterleavedAt(
        handle: Long,
        buffer: ByteBuffer,
        floatOffset: Int,
        numFrames: Int,
        numChannels: Int,
    ): Float
}
