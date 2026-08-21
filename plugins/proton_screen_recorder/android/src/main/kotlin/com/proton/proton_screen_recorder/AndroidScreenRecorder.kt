package com.proton.proton_screen_recorder

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import android.media.MediaRecorder
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.util.DisplayMetrics
import android.util.Log
import android.view.Surface
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Writes MediaProjection screen capture to an MP4 file (H.264 + optional AAC mic).
 *
 * Call [requestProjection] before [startRecording]. Android 14+ requires a
 * mediaProjection foreground service to be running before [getMediaProjection].
 */
class AndroidScreenRecorder(private val appContext: Context) {

    interface Callback {
        fun onInterrupted()
    }

    var callback: Callback? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var videoEncoder: MediaCodec? = null
    private var videoSurface: Surface? = null
    private var audioRecord: AudioRecord? = null
    private var audioEncoder: MediaCodec? = null
    private var muxer: MediaMuxer? = null

    private var videoTrackIndex = -1
    private var audioTrackIndex = -1
    private var muxerStarted = false
    private var videoFormatReady = false
    private var audioFormatReady = false
    private var enableMicrophone = true

    private var outputPath: String? = null
    private var captureWidth = 0
    private var captureHeight = 0
    private var captureDensity = 0

    private var videoDrainThread: HandlerThread? = null
    private var audioDrainThread: HandlerThread? = null
    private var audioCaptureThread: Thread? = null

    private val isRecording = AtomicBoolean(false)
    private var stopRequested = AtomicBoolean(false)
    private var muxerStartTimeUs: Long = -1L

    private val projectionCallback =
        object : MediaProjection.Callback() {
            override fun onStop() {
                Log.i(TAG, "MediaProjection stopped by system")
                mainHandler.post {
                    if (isRecording.get()) {
                        stopInternal(emitInterrupted = true)
                    }
                }
            }
        }

    fun isRecording(): Boolean = isRecording.get()

    fun requestProjection(activity: Activity): Intent {
        val manager =
            activity.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        return manager.createScreenCaptureIntent()
    }

    fun onProjectionResult(resultCode: Int, data: Intent?) {
        if (resultCode != Activity.RESULT_OK || data == null) {
            throw RecorderException("Screen capture permission denied")
        }
        val manager =
            appContext.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        mediaProjection?.stop()
        try {
            mediaProjection = manager.getMediaProjection(resultCode, data)?.also {
                it.registerCallback(projectionCallback, mainHandler)
            }
                ?: throw RecorderException("Failed to obtain MediaProjection")
        } catch (e: SecurityException) {
            Log.e(TAG, "getMediaProjection failed; is mediaProjection FGS running?", e)
            throw RecorderException(
                "Screen capture requires an active meeting notification. Stay in the call and try again.",
            )
        }
    }

    fun startRecording(
        activity: Activity,
        outputPath: String,
        enableMicrophone: Boolean,
    ) {
        if (isRecording.get()) {
            throw RecorderException("Recording is already in progress")
        }
        val projection =
            mediaProjection ?: throw RecorderException("MediaProjection is not ready")

        this.outputPath = outputPath
        this.enableMicrophone = enableMicrophone
        stopRequested.set(false)
        muxerStartTimeUs = -1L

        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        activity.windowManager.defaultDisplay.getRealMetrics(metrics)
        captureWidth = metrics.widthPixels and 1.inv()
        captureHeight = metrics.heightPixels and 1.inv()
        captureDensity = metrics.densityDpi
        if (captureWidth <= 0 || captureHeight <= 0) {
            throw RecorderException("Invalid display size")
        }

        val file = File(outputPath)
        file.parentFile?.mkdirs()
        if (file.exists()) {
            file.delete()
        }

        setupVideoEncoder()
        setupMuxer(outputPath)

        virtualDisplay =
            projection.createVirtualDisplay(
                "ProtonMeetRecording",
                captureWidth,
                captureHeight,
                captureDensity,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                videoSurface,
                null,
                null,
            )

        if (enableMicrophone) {
            setupAudioEncoder()
        } else {
            audioFormatReady = true
        }

        try {
            isRecording.set(true)
            val video = videoEncoder ?: throw RecorderException("Video encoder unavailable")
            video.start()

            if (enableMicrophone && audioEncoder != null) {
                val record = audioRecord
                if (record == null || record.state != AudioRecord.STATE_INITIALIZED) {
                    Log.w(TAG, "Microphone unavailable; continuing with video only")
                    disableMicrophoneCapture()
                } else {
                    audioEncoder?.start()
                    record.startRecording()
                }
            }

            startVideoDrainLoop()
            if (enableMicrophone && audioEncoder != null) {
                startAudioCaptureLoop()
                startAudioDrainLoop()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start capture", e)
            cleanupFailedStart()
            throw if (e is RecorderException) {
                e
            } else {
                RecorderException(e.message ?: "Failed to start recording")
            }
        }
    }

    private fun disableMicrophoneCapture() {
        enableMicrophone = false
        audioFormatReady = true
        runCatching { audioRecord?.release() }
        audioRecord = null
        runCatching { audioEncoder?.release() }
        audioEncoder = null
    }

    private fun cleanupFailedStart() {
        isRecording.set(false)
        stopRequested.set(false)
        muxerStartTimeUs = -1L
        releaseVideoResources()
        releaseAudioResources()
        finalizeMuxer()
    }

    fun stopRecording(): String {
        if (!isRecording.get()) {
            return outputPath.orEmpty()
        }
        stopInternal(emitInterrupted = false)
        val path = outputPath.orEmpty()
        releaseProjection()
        return path
    }

    fun releaseProjection() {
        mediaProjection?.unregisterCallback(projectionCallback)
        mediaProjection?.stop()
        mediaProjection = null
    }

    private fun setupVideoEncoder() {
        val format =
            MediaFormat.createVideoFormat(
                MediaFormat.MIMETYPE_VIDEO_AVC,
                captureWidth,
                captureHeight,
            )
        format.setInteger(
            MediaFormat.KEY_COLOR_FORMAT,
            MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface,
        )
        format.setInteger(MediaFormat.KEY_BIT_RATE, 4_000_000)
        format.setInteger(MediaFormat.KEY_FRAME_RATE, 30)
        format.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
        format.setInteger(
            MediaFormat.KEY_PROFILE,
            MediaCodecInfo.CodecProfileLevel.AVCProfileBaseline,
        )
        format.setInteger(
            MediaFormat.KEY_LEVEL,
            MediaCodecInfo.CodecProfileLevel.AVCLevel31,
        )

        val encoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
        encoder.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        videoSurface = encoder.createInputSurface()
        videoEncoder = encoder
    }

    private fun setupAudioEncoder() {
        val sampleRate = 44_100
        val channelConfig = AudioFormat.CHANNEL_IN_MONO
        val encoding = AudioFormat.ENCODING_PCM_16BIT
        val minBuffer = AudioRecord.getMinBufferSize(sampleRate, channelConfig, encoding)
        if (minBuffer <= 0) {
            audioFormatReady = true
            return
        }

        audioRecord =
            AudioRecord(
                MediaRecorder.AudioSource.MIC,
                sampleRate,
                channelConfig,
                encoding,
                minBuffer * 4,
            )

        val format =
            MediaFormat.createAudioFormat(
                MediaFormat.MIMETYPE_AUDIO_AAC,
                sampleRate,
                1,
            )
        format.setInteger(
            MediaFormat.KEY_AAC_PROFILE,
            MediaCodecInfo.CodecProfileLevel.AACObjectLC,
        )
        format.setInteger(MediaFormat.KEY_BIT_RATE, 96_000)

        val encoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
        encoder.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        audioEncoder = encoder
    }

    private fun setupMuxer(path: String) {
        muxer = MediaMuxer(path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        videoTrackIndex = -1
        audioTrackIndex = -1
        muxerStarted = false
        videoFormatReady = false
        audioFormatReady = !enableMicrophone
    }

    private fun startVideoDrainLoop() {
        val thread = HandlerThread("ProtonRecorderVideoDrain")
        thread.start()
        videoDrainThread = thread
        val handler = Handler(thread.looper)
        handler.post(object : Runnable {
            override fun run() {
                if (videoEncoder == null) return
                val keepGoing = drainVideoEncoderOnce()
                if (keepGoing) {
                    handler.post(this)
                }
            }
        })
    }

    private fun startAudioDrainLoop() {
        val thread = HandlerThread("ProtonRecorderAudioDrain")
        thread.start()
        audioDrainThread = thread
        val handler = Handler(thread.looper)
        handler.post(object : Runnable {
            override fun run() {
                if (audioEncoder == null) return
                val keepGoing = drainAudioEncoderOnce()
                if (keepGoing) {
                    handler.post(this)
                }
            }
        })
    }

    private fun startAudioCaptureLoop() {
        val record = audioRecord ?: return
        val encoder = audioEncoder ?: return
        audioCaptureThread =
            Thread(
                {
                    try {
                        captureAudioLoop(record, encoder)
                    } catch (e: Exception) {
                        Log.e(TAG, "Audio capture failed", e)
                        mainHandler.post {
                            if (isRecording.get()) {
                                stopInternal(emitInterrupted = true)
                            }
                        }
                    }
                },
                "ProtonRecorderAudioCapture",
            ).also { it.start() }
    }

    private fun captureAudioLoop(record: AudioRecord, encoder: MediaCodec) {
        val sampleRate = 44_100
        val bytesPerFrame = 2 // 16-bit mono
        val pcmBuffer = ByteArray(4096)
        var audioTimestampUs = 0L

        while (isRecording.get() && !stopRequested.get()) {
            val read = record.read(pcmBuffer, 0, pcmBuffer.size)
            if (read <= 0) continue

            var offset = 0
            var remaining = read
            while (remaining > 0 && isRecording.get() && !stopRequested.get()) {
                val inputIndex = encoder.dequeueInputBuffer(TIMEOUT_US)
                if (inputIndex < 0) {
                    Thread.sleep(5)
                    continue
                }

                val inputBuffer = encoder.getInputBuffer(inputIndex) ?: continue
                val chunkSize = minOf(remaining, inputBuffer.capacity())
                inputBuffer.clear()
                inputBuffer.put(pcmBuffer, offset, chunkSize)
                encoder.queueInputBuffer(
                    inputIndex,
                    0,
                    chunkSize,
                    audioTimestampUs,
                    0,
                )

                val durationUs = (chunkSize * 1_000_000L) / (sampleRate * bytesPerFrame)
                audioTimestampUs += durationUs
                offset += chunkSize
                remaining -= chunkSize
            }
        }
    }

    private fun drainVideoEncoderOnce(): Boolean {
        val encoder = videoEncoder ?: return false
        val bufferInfo = MediaCodec.BufferInfo()
        val outputIndex = encoder.dequeueOutputBuffer(bufferInfo, TIMEOUT_US)
        when {
            outputIndex == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                return isRecording.get() || stopRequested.get()
            }
            outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                val mux = muxer ?: return isRecording.get()
                if (videoTrackIndex < 0) {
                    videoTrackIndex = mux.addTrack(encoder.outputFormat)
                    videoFormatReady = true
                    maybeStartMuxer()
                }
                return true
            }
            outputIndex >= 0 -> {
                writeSample(MEDIA_VIDEO, encoder, outputIndex, bufferInfo)
                val eos = (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0
                return !eos && (isRecording.get() || stopRequested.get())
            }
        }
        return isRecording.get()
    }

    private fun drainAudioEncoderOnce(): Boolean {
        val encoder = audioEncoder ?: return false
        val bufferInfo = MediaCodec.BufferInfo()
        val outputIndex = encoder.dequeueOutputBuffer(bufferInfo, TIMEOUT_US)
        when {
            outputIndex == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                return isRecording.get() || stopRequested.get()
            }
            outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                val mux = muxer ?: return isRecording.get()
                if (audioTrackIndex < 0) {
                    audioTrackIndex = mux.addTrack(encoder.outputFormat)
                    audioFormatReady = true
                    maybeStartMuxer()
                }
                return true
            }
            outputIndex >= 0 -> {
                writeSample(MEDIA_AUDIO, encoder, outputIndex, bufferInfo)
                val eos = (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0
                return !eos && (isRecording.get() || stopRequested.get())
            }
        }
        return isRecording.get()
    }

    private fun writeSample(
        mediaType: Int,
        encoder: MediaCodec,
        outputIndex: Int,
        bufferInfo: MediaCodec.BufferInfo,
    ) {
        if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0) {
            encoder.releaseOutputBuffer(outputIndex, false)
            return
        }
        maybeStartMuxer()
        val mux = muxer
        if (mux == null || !muxerStarted) {
            encoder.releaseOutputBuffer(outputIndex, false)
            return
        }
        val trackIndex = if (mediaType == MEDIA_VIDEO) videoTrackIndex else audioTrackIndex
        if (trackIndex < 0) {
            encoder.releaseOutputBuffer(outputIndex, false)
            return
        }
        val outputBuffer = encoder.getOutputBuffer(outputIndex) ?: return
        if (bufferInfo.size > 0) {
            outputBuffer.position(bufferInfo.offset)
            outputBuffer.limit(bufferInfo.offset + bufferInfo.size)
            val normalizedInfo = MediaCodec.BufferInfo()
            normalizedInfo.set(
                bufferInfo.offset,
                bufferInfo.size,
                normalizePresentationTimeUs(bufferInfo.presentationTimeUs),
                bufferInfo.flags,
            )
            mux.writeSampleData(trackIndex, outputBuffer, normalizedInfo)
        }
        encoder.releaseOutputBuffer(outputIndex, false)
    }

    private fun normalizePresentationTimeUs(presentationTimeUs: Long): Long {
        if (muxerStartTimeUs < 0) {
            muxerStartTimeUs = presentationTimeUs
        }
        val normalized = presentationTimeUs - muxerStartTimeUs
        return if (normalized < 0) 0 else normalized
    }

    private fun maybeStartMuxer() {
        if (muxerStarted || muxer == null) return
        if (!videoFormatReady) return
        if (enableMicrophone && !audioFormatReady) return
        muxer?.start()
        muxerStarted = true
    }

    private fun stopInternal(emitInterrupted: Boolean) {
        if (!isRecording.getAndSet(false)) return
        stopRequested.set(true)

        runCatching { audioRecord?.stop() }
        runCatching { videoEncoder?.signalEndOfInputStream() }
        signalAudioEndOfStream()

        joinThread(audioCaptureThread)
        audioCaptureThread = null

        // Allow drain loops to finalize muxer samples.
        // TODO: temperay solution later we will change to use CountDownLatch to wait for the drain loops to complete.
        Thread.sleep(500)

        releaseVideoResources()
        releaseAudioResources()
        finalizeMuxer()

        if (emitInterrupted) {
            callback?.onInterrupted()
        }
    }

    private fun releaseVideoResources() {
        runCatching { virtualDisplay?.release() }
        virtualDisplay = null
        runCatching { videoSurface?.release() }
        videoSurface = null
        runCatching { videoEncoder?.stop() }
        runCatching { videoEncoder?.release() }
        videoEncoder = null
        videoDrainThread?.quitSafely()
        videoDrainThread = null
    }

    private fun releaseAudioResources() {
        runCatching { audioRecord?.release() }
        audioRecord = null
        runCatching { audioEncoder?.stop() }
        runCatching { audioEncoder?.release() }
        audioEncoder = null
        audioDrainThread?.quitSafely()
        audioDrainThread = null
    }

    private fun finalizeMuxer() {
        runCatching {
            if (muxerStarted) {
                muxer?.stop()
            }
        }
        runCatching { muxer?.release() }
        muxer = null
        muxerStarted = false
    }

    private fun signalAudioEndOfStream() {
        val encoder = audioEncoder ?: return
        val inputIndex = encoder.dequeueInputBuffer(TIMEOUT_US)
        if (inputIndex >= 0) {
            encoder.queueInputBuffer(
                inputIndex,
                0,
                0,
                System.nanoTime() / 1000,
                MediaCodec.BUFFER_FLAG_END_OF_STREAM,
            )
        }
    }

    private fun joinThread(thread: Thread?) {
        runCatching { thread?.join(500) }
    }

    class RecorderException(message: String) : Exception(message)

    companion object {
        private const val TAG = "AndroidScreenRecorder"
        private const val TIMEOUT_US = 10_000L
        private const val MEDIA_VIDEO = 0
        private const val MEDIA_AUDIO = 1
    }
}
