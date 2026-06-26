package com.proton.proton_denoise

import android.content.Context
import android.util.Log
import com.cloudwebrtc.webrtc.audio.AudioProcessingAdapter
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * DeepFilterNet 3 capture processor for flutter-webrtc's capture post-processing chain.
 *
 * df_create / df_destroy run on [sessionExecutor]; df_process runs there too via a blocking
 * hand-off from the WebRTC audio thread (same model as iOS [ProtonDeepFilterNative.sessionQueue]).
 */
internal class MeetAudioDeepFilterProcessor(
    private val appContext: Context,
    private var attenLimDb: Float = DEFAULT_ATTEN_LIM_DB,
) : MeetAudioCaptureProcessor {
    private val lock = Any()
    private val sessionExecutor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "meet-deepfilter-session").apply { isDaemon = true }
    }
    private var enabled = false
    private var numChannels = 1
    private var handle: Long = 0L

    override fun setEnabled(value: Boolean) {
        synchronized(lock) {
            enabled = value
            if (value) {
                sessionExecutor.execute { ensureHandleOnSessionThread() }
            }
            if (handle != 0L) {
                ProtonDeepFilterNative.setEnabled(handle, value)
            }
        }
    }

    fun setAttenLimDb(value: Float) {
        synchronized(lock) {
            attenLimDb = value
            if (handle != 0L) {
                ProtonDeepFilterNative.setAttenLim(handle, value)
            }
        }
    }

    override fun initialize(sampleRateHz: Int, numChannels: Int) {
        synchronized(lock) {
            this.numChannels = numChannels.coerceAtLeast(1)
        }
        sessionExecutor.execute { ensureHandleOnSessionThread() }
    }

    override fun reset(newRate: Int) {
        // DeepFilter frame size is fixed; sample rate changes do not require re-init today.
    }

    override fun process(numBands: Int, numFrames: Int, buffer: ByteBuffer) {
        val activeHandle: Long
        val channels: Int
        synchronized(lock) {
            if (!enabled || numFrames <= 0 || handle == 0L) {
                return
            }
            channels = effectiveChannels(numFrames, buffer)
            if (channels <= 0) {
                return
            }
            activeHandle = handle
        }
        buffer.order(ByteOrder.nativeOrder())
        try {
            // Block the audio thread for one frame — no timeout (500 ms caused TimeoutException crashes).
            sessionExecutor.submit {
                MeetAudioDeepFilterPipeline.processInterleavedInPlace(
                    activeHandle,
                    buffer,
                    numFrames,
                    channels,
                )
            }.get()
        } catch (e: InterruptedException) {
            Thread.currentThread().interrupt()
            Log.w(TAG, "DeepFilter process interrupted", e)
        } catch (e: Exception) {
            Log.e(TAG, "DeepFilter process failed", e)
        }
    }

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

    private fun ensureHandleOnSessionThread() {
        synchronized(lock) {
            if (handle != 0L) {
                return
            }
        }
        if (!ProtonDeepFilterNative.isAvailable) {
            Log.w(TAG, "DeepFilter native library unavailable")
            return
        }
        val model = DeepFilterModelStore.ensureModelFile(appContext)
        if (model == null) {
            Log.w(TAG, "DeepFilter model not staged")
            return
        }
        val created =
            try {
                Log.i(TAG, "Creating DeepFilter session from ${model.absolutePath}")
                ProtonDeepFilterNative.create(model.absolutePath)
            } catch (e: Throwable) {
                Log.e(TAG, "df_create threw", e)
                0L
            }
        if (created == 0L) {
            Log.e(TAG, "df_create returned null handle")
            return
        }
        synchronized(lock) {
            if (handle == 0L) {
                handle = created
                ProtonDeepFilterNative.setAttenLim(handle, attenLimDb)
                ProtonDeepFilterNative.setEnabled(handle, enabled)
                Log.i(
                    TAG,
                    "DeepFilter ready frameSize=${ProtonDeepFilterNative.getFrameSize(handle)}",
                )
            } else {
                ProtonDeepFilterNative.destroy(created)
            }
        }
    }

    override fun release() {
        val toDestroy: Long
        synchronized(lock) {
            enabled = false
            toDestroy = handle
            handle = 0L
        }
        if (toDestroy != 0L) {
            runCatching {
                sessionExecutor.submit {
                    ProtonDeepFilterNative.destroy(toDestroy)
                }.get(30, TimeUnit.SECONDS)
            }.onFailure { Log.w(TAG, "DeepFilter destroy failed", it) }
        }
        sessionExecutor.shutdown()
    }

    companion object {
        private const val TAG = "MeetAudioDeepFilter"
        const val DEFAULT_ATTEN_LIM_DB = 30f

        fun isNativeReady(context: Context): Boolean =
            ProtonDeepFilterNative.isAvailable &&
                DeepFilterModelStore.isModelAvailable(context)
    }
}
