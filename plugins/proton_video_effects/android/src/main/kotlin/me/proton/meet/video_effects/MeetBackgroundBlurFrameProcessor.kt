/*
 * Copyright (c) 2026 Proton AG
 * This file is part of Proton AG and Proton Meet.
 *
 * Proton Meet is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * Proton Meet is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with Proton Meet. If not, see <https://www.gnu.org/licenses/>.
 */

package me.proton.meet.video_effects

import android.content.Context
import com.cloudwebrtc.webrtc.video.LocalVideoTrack
import org.webrtc.VideoFrame
import android.util.Log


/**
 * WebRTC frame processor wrapping a long-lived [MeetBackgroundBlurMediaPipeEngine].
 * Direct counterpart to `MeetBackgroundBlurProcessor` in `BackgroundBlurBridge.swift`.
 *
 * One instance is reused across attach/detach cycles ([BackgroundBlurChannel.sharedProcessor]);
 * [setEnabled] gates processing without tearing down the segmenter.
 */
internal class MeetBackgroundBlurFrameProcessor(
    context: Context,
) : LocalVideoTrack.ExternalVideoFrameProcessing {

    private companion object {
        /** First N frames are logged at INFO so the very first arrival is always visible. */
        private const val FIRST_FRAMES_LOG_LIMIT = 5L
        /** After the first-frame burst, log every Nth frame at DEBUG so logcat stays readable. */
        private const val LOG_EVERY_NTH_FRAME = 30L
    }

    /** Identity hash matches the value logged by `BackgroundBlurChannel.attach: created processor=…`
     *  so we can correlate this processor's lifecycle across the channel and the frame pipeline. */
    private val instanceId: Int = System.identityHashCode(this)

    // Use the application context so the engine never outlives an Activity by accident.
    private val engine = MeetBackgroundBlurMediaPipeEngine(context.applicationContext)

    private val createdAtNs: Long = System.nanoTime()
    @Volatile
    private var isEnabled: Boolean = true
    @Volatile
    private var framesReceived: Long = 0L
    @Volatile
    private var firstFrameAtNs: Long = 0L

    fun setEnabled(enabled: Boolean) {
        isEnabled = enabled
    }

    fun applyBlurConfig(blurSigma: Float, backgroundObscureOpacity: Float) {
        engine.setBlurConfig(blurSigma, backgroundObscureOpacity)
    }

    fun setReplacementBackgroundImagePath(path: String?): Boolean =
        engine.setReplacementBackgroundImagePath(path)

    fun setReplacementBackgroundImageBytes(bytes: ByteArray?): Boolean =
        engine.setReplacementBackgroundImageBytes(bytes)

    fun clearReplacementBackground() {
        engine.clearReplacementBackground()
    }

    fun setSegmentationModelPreference(model: String) {
        engine.setSegmentationModelPreference(model)
    }

    fun segmentationModelDebugInfo(): Map<String, Any> = engine.segmentationModelDebugInfo()

    init {
        Log.i("ProtonVideoEffects", "FrameProcessor: constructed instance=$instanceId thread=${Thread.currentThread().name}",
        )
    }

    override fun onFrame(frame: VideoFrame): VideoFrame {
        if (!isEnabled) {
            return frame
        }
        framesReceived++
        if (framesReceived == 1L) {
            firstFrameAtNs = System.nanoTime()
            val firstFrameLatencyMs = (firstFrameAtNs - createdAtNs) / 1_000_000
            Log.i("ProtonVideoEffects", "FrameProcessor: FIRST frame for instance=$instanceId arrived ${firstFrameLatencyMs}ms " +
                    "after construction on thread=${Thread.currentThread().name}",
            )
        }

        val out = try {
            engine.process(frame)
        } catch (t: Throwable) {
            Log.w(
                "ProtonVideoEffects",
                "FrameProcessor: engine.process failed; passing original frame through",
                t,
            )
            frame
        }

        // Never call `frame.release()` here. `VideoProcessor.onFrameCaptured` already retains the
        // capturer frame, runs processors, then releases the *input* frame before forwarding the
        // result. Releasing in our code double-frees TextureBufferImpl (refcount < 1 crash).

        if (framesReceived <= FIRST_FRAMES_LOG_LIMIT) {
            Log.i("ProtonVideoEffects", frameLogLine(frame, out))
        } else if (framesReceived % LOG_EVERY_NTH_FRAME == 0L) {
            Log.d("ProtonVideoEffects", frameLogLine(frame, out))
        }
        return out
    }

    private fun frameLogLine(frame: VideoFrame, out: VideoFrame): String {
        val bufferType = frame.buffer.javaClass.simpleName
        val passthrough = out === frame
        return "FrameProcessor.onFrame instance=$instanceId #$framesReceived " +
            "buffer=$bufferType ${frame.buffer.width}x${frame.buffer.height} rot=${frame.rotation} " +
            "ts=${frame.timestampNs} thread=${Thread.currentThread().name} passthrough=$passthrough"
    }

    /** Release MediaPipe + cached resources. Call only when the Flutter engine is torn down. */
    fun release() {
        val uptimeMs = (System.nanoTime() - createdAtNs) / 1_000_000
        val firstFrameLatencyMs = if (firstFrameAtNs == 0L) -1L else (firstFrameAtNs - createdAtNs) / 1_000_000
        Log.i("ProtonVideoEffects", "FrameProcessor: released instance=$instanceId framesReceived=$framesReceived " +
                "uptimeMs=$uptimeMs firstFrameLatencyMs=$firstFrameLatencyMs " +
                "(${if (framesReceived == 0L) "NEVER received a frame" else "ok"})",
        )
        engine.release()
    }
}
