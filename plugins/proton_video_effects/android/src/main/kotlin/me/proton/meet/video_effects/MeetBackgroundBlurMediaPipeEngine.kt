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
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.util.Log
import androidx.exifinterface.media.ExifInterface
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.framework.image.ByteBufferExtractor
import com.google.mediapipe.framework.image.MPImage
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.imagesegmenter.ImageSegmenter
import com.google.mediapipe.tasks.vision.imagesegmenter.ImageSegmenterResult
import org.webrtc.JavaI420Buffer
import org.webrtc.VideoFrame
import org.tensorflow.lite.DataType
import org.tensorflow.lite.Interpreter
import org.tensorflow.lite.gpu.GpuDelegate
import org.tensorflow.lite.gpu.GpuDelegateFactory
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.Callable
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.Locale

/**
 * Android blur engine — counterpart to `MeetBackgroundBlurMediaPipeEngine.swift`.
 *
 * Per frame: async person mask (one inference in flight) → box-blur background + mask blend
 * onto a fresh [VideoFrame]. Unlike iOS we round-trip through [Bitmap] (no in-place pixel buffer).
 *
 * Segmentation: raw TFLite + GpuDelegate when possible; MediaPipe Tasks CPU otherwise. GPU Tasks
 * output conversion is avoided — MediaPipe 0.10.35 can abort on Adreno when reading GPU images.
 * Multiclass masks invert background confidence so snapshots are always "person = high alpha".
 *
 * [maskLock] guards [currentMask] and [inferenceInFlight]; compositing runs on the WebRTC thread.
 */
internal class MeetBackgroundBlurMediaPipeEngine(
    private val context: Context,
) {
    companion object {
        private const val TAG = "MeetBgBlur"

        private const val MULTICLASS_MODEL_ASSET = "selfie_multiclass_256x256.tflite"
        private const val SINGLECLASS_MODEL_ASSET = "selfie_segmenter.tflite"
        private const val LANDSCAPE_MODEL_ASSET = "selfie_segmenter_landscape.tflite"

        /**
         * Extra quarter turn the mask needs on top of undoing [MaskSnapshot.sourceRotation].
         *
         * Empirical, not derived. Rotating the frame upright for inference and un-rotating the
         * mask by the same angle should cancel exactly, and reading the transform by hand says it
         * does — but on device the silhouette lands a quarter turn off, and neither the tensor
         * layout (plain row-major on both the write and the read) nor the compositing matrix
         * accounts for it. Measured against the debug mask overlay on front and rear cameras,
         * whose frame rotations differ by 180°; both need this same turn, so it is a fixed offset
         * between mask space and buffer space rather than anything that tracks frame rotation.
         *
         * If you touch the rotation path, re-check this with the overlay rather than trusting it.
         */
        private const val MASK_UNROTATE_BIAS_DEGREES = 270

        private const val SQUARE_SEGMENTER_SIZE = 256
        private const val LANDSCAPE_INPUT_WIDTH = 256
        private const val LANDSCAPE_INPUT_HEIGHT = 144

        /**
         * Compositing resolution cap on the long edge.
         *
         * Android round-trips every frame through Bitmap + I420 (unlike iOS in-place CVPixelBuffer).
         * `0` keeps full camera resolution and allocates several full-frame bitmaps per frame —
         * even with correct `VideoFrame.release()` that still pins hundreds of MiB/s through the
         * allocator. 720 matches the typical Meet publish preset and keeps blur visually acceptable.
         */
        private const val PROCESSING_LONG_SIDE = 720

        /** Background blur runs at this fraction of the processing resolution. */
        private const val BACKGROUND_BLUR_DOWNSAMPLE = 0.2f

        private const val BACKGROUND_BLUR_PASSES = 2

        /**
         * Box-blur iterations per pass. Repeated box blurs converge on a Gaussian, and three is
         * the usual point of diminishing returns; the extra two buy a little more smoothness on
         * the hard edges the downsample leaves behind.
         */
        private const val BOX_BLUR_PASSES_PER_ROUND = 5

        /** Box-blur radius when [blurSigma] equals [DEFAULT_BLUR_SIGMA] (calibration anchor, not Dart default). */
        private const val DEFAULT_BLUR_RADIUS = 8

        /** Anchor for [backgroundBlurRadius]; Dart production σ is 128 via [setBlurConfig]. */
        private const val DEFAULT_BLUR_SIGMA = 24f
        private const val MIN_BLUR_SIGMA = 4f
        private const val MAX_BLUR_SIGMA = 256f

        /** Desaturate blurred plate (0 = full color, 1 = grayscale). Matches iOS `backgroundDesaturation`. */
        private const val BACKGROUND_DESATURATION = 0.5f

        /**
         * Floors for the mask feather σ, in mask pixels. The tuned
         * [MaskEdgeTuning.featherHeightFraction] is used when it asks for more than the floor.
         *
         * Two values, because the two segmenter outputs start from very different edges:
         *   * [MASK_FEATHER_SIGMA_MIN_CONFIDENCE] — small. The mask is already a continuous
         *     probability so most of the smoothness comes from the source; this only guarantees
         *     the upscale has about a pixel of ramp to interpolate.
         *   * [MASK_FEATHER_SIGMA_CATEGORY] — larger. The mask is hard binary 0/255 from the
         *     argmax category output, with no ramp of its own, so it needs a wider Gaussian to
         *     produce an edge comparable to the confidence path after upscale. This one is a hard
         *     floor rather than a default: below it the category path visibly staircases.
         */
        private const val MASK_FEATHER_SIGMA_MIN_CONFIDENCE = 0.9f
        private const val MASK_FEATHER_SIGMA_CATEGORY = 3.0f

        /** Per-class index 0 (background) in the multiclass model. */
        private const val MULTICLASS_BACKGROUND_INDEX = 0

        /** Maximum time `release()` waits for an in-flight inference to drain before force-closing
         *  the segmenter. 250 ms is conservatively long enough for the slowest CPU inference on
         *  budget devices (~150 ms) while still keeping detach responsive. */
        private const val INFERENCE_DRAIN_TIMEOUT_NS: Long = 250_000_000L

        /** Throttle for crash-stage logs in `process()`. Logging every stage on every frame would
         *  flood logcat at camera FPS; we log details every Nth frame and on each error. */
        private const val STAGE_LOG_EVERY_NTH_FRAME = 120L

        /** Maximum time we wait during construction for the raw TFLite GPU backend to compile its
         *  delegate graph and complete a one-frame probe inference. If this times out, setup falls
         *  through to the MediaPipe CPU backend so blur still works. */
        private const val TFLITE_GPU_INIT_TIMEOUT_MS = 3_000L
    }

    /** Frame counter for `process()` rate-limited stage logging. */
    @Volatile
    private var processFrameCount: Long = 0L

    // MARK: - Snapshot of the latest mask, shared between threads.
    private data class MaskSnapshot(
        val width: Int,
        val height: Int,
        /** Foreground alpha (high = person), normalised to `0..255`. The snapshot is always built
         *  as the foreground mask regardless of which model produced it, so the compositing path
         *  doesn't need to branch. */
        val foregroundAlpha: ByteArray,
        /**
         * Frame rotation the segmenter analysed this mask under, so compositing can turn it back
         * into buffer space.
         *
         * Inference is asynchronous and the device can rotate between dispatch and result, so the
         * angle has to travel with the mask rather than be re-read from the current frame.
         */
        val sourceRotation: Int = 0,
    )

    private enum class SegmenterBackendKind {
        TFLITE_GPU,
        MEDIAPIPE_CPU,
    }

    private data class SegmenterModelConfig(
        val asset: String,
        val inputWidth: Int,
        val inputHeight: Int,
        val isMulticlass: Boolean,
        val modelKey: String,
    )

    private data class SegmenterAttempt(
        val config: SegmenterModelConfig,
        val backend: SegmenterBackendKind,
    ) {
        val modelAsset: String get() = config.asset
        val inputWidth: Int get() = config.inputWidth
        val inputHeight: Int get() = config.inputHeight
        val isMulticlass: Boolean get() = config.isMulticlass
        val modelKey: String get() = config.modelKey
    }

    private data class PerfSnapshot(
        val framesSeen: Long,
        val dispatchStarted: Long,
        val dispatchSkipped: Long,
        val inferencesCompleted: Long,
        val inferencesFailed: Long,
        val dispatchHitRate: Double,
        val inferenceLastMs: Long,
        val inferenceAvgMs: Double,
        val inferenceMaxMs: Long,
    )

    @Volatile
    private var segmenter: ImageSegmenter? = null
    @Volatile
    private var tfliteBackend: TfliteGpuSegmenterBackend? = null
    private var isMulticlassModel: Boolean = false
    private var segmenterInputWidth: Int = SQUARE_SEGMENTER_SIZE
    private var segmenterInputHeight: Int = SQUARE_SEGMENTER_SIZE
    private var activeModelKey: String = "single"

    @Volatile
    private var preferredModel: String? = null

    /** `true` when the active segmenter was configured with `setOutputCategoryMask(true)` rather
     *  than `setOutputConfidenceMasks(true)`. Drives both the result-listener decoding path
     *  ([onSegmenterResult]) and the feather σ ([composeWithMask]). Set together with [segmenter]
     *  in [setupSegmenter] under the same try block so it can never refer to a different
     *  segmenter than the one we're actually using. */
    @Volatile
    private var usesCategoryMaskOutput: Boolean = false

    private val maskLock = Any()
    private var currentMask: MaskSnapshot? = null

    /** Rotation applied to the frame handed to the in-flight inference; see [MaskSnapshot.sourceRotation]. */
    @Volatile
    private var pendingInferenceRotation: Int = 0

    /**
     * Debug: paint the shaped mask over the sharp frame instead of blending a background.
     *
     * The mask is otherwise only observable through where the blur lands, which conflates a
     * misplaced mask with a badly shaped one. Tinting it directly separates the two.
     */
    @Volatile
    private var debugMaskOverlay: Boolean = false

    fun setDebugMaskOverlay(enabled: Boolean) {
        debugMaskOverlay = enabled
    }


    // Matches Dart BackgroundBlurConfig until setBlurConfig runs.
    @Volatile
    private var blurSigma: Float = 128f

    @Volatile
    private var backgroundObscureOpacity: Float = 0.1f

    private val replacementLock = Any()
    private var replacementBackgroundBitmap: Bitmap? = null

    /**
     * Replacement scaled and pre-rotated for one (width, height, rotation) triple. Without this the
     * cover-scale plus the quarter turn would rebuild a full-frame bitmap on every frame.
     */
    private var orientedReplacementBitmap: Bitmap? = null
    private var orientedReplacementWidth: Int = 0
    private var orientedReplacementHeight: Int = 0
    private var orientedReplacementRotation: Int = -1

    @Volatile
    private var maskEdge: MaskEdgeTuning = MaskEdgeTuning()

    fun setBlurConfig(blurSigma: Float, backgroundObscureOpacity: Float) {
        this.blurSigma = blurSigma.coerceIn(MIN_BLUR_SIGMA, MAX_BLUR_SIGMA)
        this.backgroundObscureOpacity = backgroundObscureOpacity.coerceIn(0f, 1f)
    }

    fun setMaskEdgeTuning(tuning: MaskEdgeTuning) {
        maskEdge = tuning.clamped()
    }

    fun maskEdgeDebugInfo(): Map<String, Any> = maskEdge.let {
        mapOf(
            "maskFeatherHeightFraction" to it.featherHeightFraction,
            "maskErodeHeightFraction" to it.erodeHeightFraction,
            "maskSolidifySlope" to it.solidifySlope,
            "maskSolidifyMidpoint" to it.solidifyMidpoint,
            "maskForegroundGamma" to it.foregroundGamma,
        )
    }

    fun setReplacementBackgroundImagePath(path: String?): Boolean {
        if (path.isNullOrEmpty()) {
            clearReplacementBackground()
            return true
        }
        val decoded = BitmapFactory.decodeFile(path) ?: return false
        return storeReplacementBitmap(applyExifOrientation(decoded, path))
    }

    fun setReplacementBackgroundImageBytes(bytes: ByteArray?): Boolean {
        if (bytes == null || bytes.isEmpty()) {
            clearReplacementBackground()
            return true
        }
        val decoded = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return false
        return storeReplacementBitmap(applyExifOrientation(decoded, bytes))
    }

    fun clearReplacementBackground() {
        synchronized(replacementLock) {
            replacementBackgroundBitmap?.recycle()
            replacementBackgroundBitmap = null
            invalidateOrientedReplacementLocked()
        }
    }

    private fun storeReplacementBitmap(bitmap: Bitmap): Boolean {
        synchronized(replacementLock) {
            replacementBackgroundBitmap?.recycle()
            replacementBackgroundBitmap = bitmap
            invalidateOrientedReplacementLocked()
        }
        return true
    }

    /**
     * Drops the reference without recycling: compositing hands this bitmap out and then draws it
     * outside [replacementLock], so picking a new background mid-call could otherwise recycle a
     * bitmap the WebRTC thread is still reading. Letting GC reclaim it costs one frame-sized
     * allocation and cannot crash.
     */
    private fun invalidateOrientedReplacementLocked() {
        orientedReplacementBitmap = null
        orientedReplacementWidth = 0
        orientedReplacementHeight = 0
        orientedReplacementRotation = -1
    }

    /** BitmapFactory ignores JPEG/HEIC EXIF rotation — upright the pixels for display. */
    private fun applyExifOrientation(bitmap: Bitmap, path: String): Bitmap {
        val orientation =
            runCatching {
                ExifInterface(path).getAttributeInt(
                    ExifInterface.TAG_ORIENTATION,
                    ExifInterface.ORIENTATION_NORMAL,
                )
            }.getOrDefault(ExifInterface.ORIENTATION_NORMAL)
        return rotateBitmapForExif(bitmap, orientation)
    }

    private fun applyExifOrientation(bitmap: Bitmap, bytes: ByteArray): Bitmap {
        val orientation =
            runCatching {
                ExifInterface(bytes.inputStream()).getAttributeInt(
                    ExifInterface.TAG_ORIENTATION,
                    ExifInterface.ORIENTATION_NORMAL,
                )
            }.getOrDefault(ExifInterface.ORIENTATION_NORMAL)
        return rotateBitmapForExif(bitmap, orientation)
    }

    private fun rotateBitmapForExif(bitmap: Bitmap, orientation: Int): Bitmap {
        val matrix = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.postScale(-1f, 1f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.postScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> {
                matrix.postRotate(90f)
                matrix.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_TRANSVERSE -> {
                matrix.postRotate(270f)
                matrix.postScale(-1f, 1f)
            }
            else -> return bitmap
        }
        val rotated =
            Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
        if (rotated !== bitmap) {
            bitmap.recycle()
        }
        return rotated
    }

    private fun backgroundBlurRadius(): Int =
        (blurSigma / DEFAULT_BLUR_SIGMA * DEFAULT_BLUR_RADIUS).toInt().coerceIn(1, 96)

    /** Single-slot pipeline guard: `true` between handing a frame to MediaPipe and receiving the
     *  result callback. While `true`, new frames are skipped (we don't queue them), which keeps
     *  inference cadence as high as the model can sustain and avoids stale backlog. */
    private var inferenceInFlight: Boolean = false
    private var currentInferenceStartNs: Long = 0L
    /** Last MediaPipe LIVE_STREAM input image currently owned by the segmenter callback lifecycle. */
    private var pendingMpInputImage: MPImage? = null

    // Performance counters (all guarded by [maskLock]).
    private var perfFramesSeen: Long = 0L
    private var perfDispatchStarted: Long = 0L
    private var perfDispatchSkipped: Long = 0L
    private var perfInferencesCompleted: Long = 0L
    private var perfInferencesFailed: Long = 0L
    private var perfInferenceTotalMs: Long = 0L
    private var perfInferenceLastMs: Long = 0L
    private var perfInferenceMaxMs: Long = 0L

    /** Monotonic clock for MediaPipe's LIVE_STREAM API. Timestamps must be strictly increasing. */
    private var segmentClockMs: Long = 0L
    /** Reused ARGB scratch for I420 → Bitmap conversion to avoid per-frame large IntArray churn. */
    private var i420ArgbScratch: IntArray? = null
    /**
     * Plane-sized byte scratch for the I420 ↔ ARGB conversions.
     *
     * Both directions used to address the `ByteBuffer` one sample at a time — ~2.8 M bounds-checked
     * direct-buffer accesses per frame at 720p in each direction. Bulk `get`/`put` is a single
     * memcpy per plane, after which the conversion loops run over plain byte arrays.
     *
     * Shared by both directions: the import fills them at the top of `process()` and nothing reads
     * them again by the time the output packing overwrites them at the bottom.
     */
    private var i420YScratch: ByteArray? = null
    private var i420UScratch: ByteArray? = null
    private var i420VScratch: ByteArray? = null
    /** Reused ARGB scratch for Bitmap → I420 conversion to avoid per-frame large IntArray churn. */
    private var bitmapToI420Scratch: IntArray? = null
    /** Reused downscaled blur scratch (pixels + tmp) to reduce repeated allocations. */
    private var blurPixelsScratch: IntArray? = null
    private var blurTmpScratch: IntArray? = null
    /** Downscale target for the blur plate; pooled so the plate costs no allocation per frame. */
    private var blurDownscaleBitmap: Bitmap? = null
    private var blurDownscaleCanvas: Canvas? = null
    private val blurDownscaleRect = android.graphics.Rect()
    /** Reused ARGB scratch for packing the 256² alpha mask before upscale. */
    private var maskSrcArgbScratch: IntArray? = null
    /** Reused separable feather passes on the 256² mask (two × 64 KiB, not worth reallocating). */
    private var featherPass1Scratch: ByteArray? = null
    private var featherOutScratch: ByteArray? = null
    /** Reused separable erosion passes on the 256² mask. */
    private var erodePass1Scratch: ByteArray? = null
    private var erodeOutScratch: ByteArray? = null
    /** Holds the solidify result when erosion was skipped and would otherwise alias the cache. */
    private var maskToneScratch: ByteArray? = null

    /**
     * 256-entry lookup tables for the solidify and gamma stages.
     *
     * Both are pure per-sample functions of the alpha byte, so evaluating them per mask pixel —
     * 65 536 `Math.pow` calls a frame for gamma alone — is wasted work. Rebuilt only when the
     * tuning it was derived from stops matching.
     */
    @Volatile
    private var maskToneLut: MaskToneLut? = null

    /** Mask upscale scratch. Reused across frames; sizes track the processing resolution. */
    private var maskSrcBitmap: Bitmap? = null
    private val maskUpscaleMatrix = Matrix()

    /**
     * The shaped mask currently held by [maskSrcBitmap], identified by the snapshot it came from.
     *
     * Inference runs slower than capture, so the same snapshot is composited onto several frames
     * in a row. Erode, solidify, feather and gamma depend only on the snapshot and the tuning, so
     * re-running them per frame recomputes an identical mask — four separable passes over 65 k
     * samples thrown away every time. Identity comparison is enough: snapshots are never mutated
     * after publication, a new inference always produces a new instance.
     */
    private var shapedMaskSource: MaskSnapshot? = null
    private var shapedMaskEdge: MaskEdgeTuning? = null

    /**
     * Segmenter input, rotated upright and scaled to the model's input size by a single filtered
     * draw.
     *
     * The previous shape rotated the whole frame into a new full-size bitmap and then scaled that
     * into a second one, so every frame allocated ~3 MB and resampled 900 k pixels twice before
     * the model saw anything — all on the capture thread, ahead of the inference it gates.
     */
    private var segmenterInputBitmap: Bitmap? = null
    private var segmenterInputCanvas: Canvas? = null
    private val segmenterInputMatrix = Matrix()
    private var segmenterPixelScratch: IntArray? = null

    /**
     * Off-screen layer holding the mask-cut foreground, reused across frames.
     *
     * `Canvas.saveLayer` allocates and frees a frame-sized layer on every call, which on a software
     * canvas is a full ARGB_8888 buffer per frame. Keeping our own layer makes the same composite
     * allocation-free, and lets the mask upscale target it directly instead of going through a
     * separate frame-sized mask bitmap.
     */
    private var pooledForegroundBitmap: Bitmap? = null
    private var pooledForegroundCanvas: Canvas? = null

    /**
     * SRC rather than the default SRC_OVER: the destination is a cached bitmap still holding the
     * previous frame's mask, and compositing over it would blend the two alphas together instead
     * of replacing them. SRC also makes an explicit clear unnecessary, since the scaled draw
     * covers the destination exactly.
     */
    private val maskUpscalePaint = Paint().apply {
        isFilterBitmap = true
        isAntiAlias = false
        xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC)
    }

    /** Composites the sharp frame through the mask alpha. Allocation-free across frames. */
    private val srcInPaint = Paint().apply {
        xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
        isAntiAlias = false
        isFilterBitmap = true
    }

    private val desaturateFilter = ColorMatrixColorFilter(
        ColorMatrix().apply { setSaturation(1f - BACKGROUND_DESATURATION.coerceIn(0f, 1f)) },
    )

    /**
     * Draws the background plate. Filtering matters here: the blurred plate is a fraction of the
     * frame and this draw is what scales it up, so without it the plate arrives blocky rather than
     * blurred.
     */
    private val plateDrawPaint = Paint().apply {
        isFilterBitmap = true
        isAntiAlias = false
    }

    private val veilPaint = Paint()

    /**
     * SRC for the same reason as [maskUpscalePaint]: the plate scratch still holds the previous
     * frame and the draw covers it exactly, so replacing is both correct and cheaper than a clear.
     */
    private val plateDownscalePaint = Paint().apply {
        isFilterBitmap = true
        isAntiAlias = false
        xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC)
    }

    /** Colour filter only applies to the blurred camera plate; see [BackgroundPlate]. */
    private fun platePaint(wantsDesaturation: Boolean): Paint = plateDrawPaint.apply {
        colorFilter =
            if (wantsDesaturation && BACKGROUND_DESATURATION > 0f) desaturateFilter else null
    }

    private class MaskToneLut(
        /** The tuning these tables were derived from; see [shapeMaskAlpha] for why it is stored. */
        val edge: MaskEdgeTuning,
        val solidify: ByteArray,
        /** Null when gamma is neutral, so the caller can skip the pass entirely. */
        val gamma: ByteArray?,
    )
    /** Mutable ARGB bitmap reused for I420→ARGB import (camera frames are TextureBuffer, not in-place). */
    private var pooledArgbBitmap: Bitmap? = null
    private var pooledArgbBitmapW: Int = 0
    private var pooledArgbBitmapH: Int = 0
    /** Mutable ARGB bitmap reused for compositing output before packing into I420. */
    private var pooledComposedBitmap: Bitmap? = null
    private var pooledComposedCanvas: Canvas? = null
    private var pooledComposedBitmapW: Int = 0
    private var pooledComposedBitmapH: Int = 0

    /** Destination for the background plate draw; reused so the plate scale costs no allocation. */
    private val plateDstRect = android.graphics.Rect()
    /**
     * Reused I420 sink written every composed frame. WebRTC owns the returned `VideoFrame` and
     * releases it after encode; we keep one buffer allocation per resolution instead of
     * `JavaI420Buffer.allocate` per frame.
     */
    private var pooledOutputI420: JavaI420Buffer? = null

    init {
        setupSegmenter()
    }

    private fun setupSegmenter() {
        Log.i(
            TAG,
            "setupSegmenter: starting on device API=${android.os.Build.VERSION.SDK_INT} " +
                "model=${android.os.Build.MODEL} abis=${android.os.Build.SUPPORTED_ABIS.joinToString(",")}",
        )
        // Hybrid fallback chain:
        //   1. single-class + raw TFLite GPU — preferred fast path. It bypasses MediaPipe Tasks's
        //      crashing GPU result-conversion layer and reads output tensors directly.
        //   2. multiclass + raw TFLite GPU — defensive GPU fallback if the single-class model is
        //      missing or rejected by the delegate.
        //   3. single-class + MediaPipe CPU — stable fallback. This is fast enough to keep the mask
        //      reasonably fresh even on budget devices.
        //   4. multiclass + MediaPipe CPU — last resort for APK/model packaging oddities.
        val attempts = buildSegmenterAttemptChain()
        if (attempts.isEmpty()) {
            Log.w(TAG, "setupSegmenter: no selfie segmenter model found in assets — blur disabled")
            return
        }

        for (attempt in attempts) {
            val isGpu = attempt.backend == SegmenterBackendKind.TFLITE_GPU
            val delegate = if (isGpu) "GPU" else "CPU"
            val outputMode = if (isGpu) "tensor" else "confidence"
            val label = "backend=${attempt.backend} model=${attempt.modelAsset} " +
                "multiclass=${attempt.isMulticlass} delegate=$delegate output=$outputMode"
            Log.i(TAG, "setupSegmenter: trying $label")
            try {
                if (isGpu) {
                    val created = TfliteGpuSegmenterBackend(
                        modelAsset = attempt.modelAsset,
                        isMulticlassModel = attempt.isMulticlass,
                        inputWidth = attempt.inputWidth,
                        inputHeight = attempt.inputHeight,
                        modelBuffer = loadModelBuffer(attempt.modelAsset),
                        serializationDir = gpuSerializationDir(),
                    )
                    tfliteBackend = created
                    segmenter = null
                    usesCategoryMaskOutput = false
                } else {
                    val created = createSegmenter(attempt.modelAsset, Delegate.CPU, useCategoryMask = false)
                    segmenter = created
                    tfliteBackend = null
                    usesCategoryMaskOutput = false
                }
                isMulticlassModel = attempt.isMulticlass
                segmenterInputWidth = attempt.inputWidth
                segmenterInputHeight = attempt.inputHeight
                activeModelKey = attempt.modelKey
                Log.i(TAG, "setupSegmenter: ready ($label)")
                Log.i(TAG, "setupSegmenter: done, segmenter=ready")
                return
            } catch (error: Throwable) {
                // INFO at first failure level, ERROR only when the whole chain is exhausted so we
                // don't spam Sentry with the (expected) intermediate failures on older devices.
                Log.w(TAG, "setupSegmenter: failed $label — ${error.message?.take(160)}", error)
            }
        }

        Log.e(TAG, "setupSegmenter: ALL fallbacks failed — blur disabled (segmenter=null)")
        segmenter = null
        tfliteBackend = null
        Log.i(TAG, "setupSegmenter: done, segmenter=null")
    }

    /**
     * Build the ordered fallback chain of (modelAsset, isMulticlass, delegate) tuples to try. Only
     * includes combinations whose model asset actually exists in the APK so we don't waste cycles
     * on missing bundles.
     */
    fun setSegmentationModelPreference(model: String) {
        preferredModel = model
        closeSegmenterForReload()
        setupSegmenter()
    }

    fun segmentationModelDebugInfo(): Map<String, Any> {
        val backend = when {
            tfliteBackend != null -> "tflite_gpu"
            segmenter != null -> "mediapipe_cpu"
            else -> "none"
        }
        return mapOf(
            "model" to activeModelKey,
            "backend" to backend,
            "forced" to (preferredModel != null),
            "supported" to true,
        )
    }

    private fun modelConfig(modelKey: String): SegmenterModelConfig? =
        when (modelKey) {
            "single" ->
                SegmenterModelConfig(
                    SINGLECLASS_MODEL_ASSET,
                    SQUARE_SEGMENTER_SIZE,
                    SQUARE_SEGMENTER_SIZE,
                    isMulticlass = false,
                    modelKey = "single",
                )
            "landscape" ->
                SegmenterModelConfig(
                    LANDSCAPE_MODEL_ASSET,
                    LANDSCAPE_INPUT_WIDTH,
                    LANDSCAPE_INPUT_HEIGHT,
                    isMulticlass = false,
                    modelKey = "landscape",
                )
            "multiclass" ->
                SegmenterModelConfig(
                    MULTICLASS_MODEL_ASSET,
                    SQUARE_SEGMENTER_SIZE,
                    SQUARE_SEGMENTER_SIZE,
                    isMulticlass = true,
                    modelKey = "multiclass",
                )
            else -> null
        }

    private fun closeSegmenterForReload() {
        val toClose = segmenter
        val tfliteToClose = tfliteBackend
        segmenter = null
        tfliteBackend = null
        val drainUntilNs = System.nanoTime() + INFERENCE_DRAIN_TIMEOUT_NS
        while (System.nanoTime() < drainUntilNs) {
            val stillInFlight = synchronized(maskLock) { inferenceInFlight }
            if (!stillInFlight) break
            try {
                Thread.sleep(5)
            } catch (ie: InterruptedException) {
                Thread.currentThread().interrupt()
                break
            }
        }
        try {
            toClose?.close()
        } catch (e: Throwable) {
            Log.w(TAG, "closeSegmenterForReload: segmenter.close failed", e)
        }
        try {
            tfliteToClose?.close()
        } catch (e: Throwable) {
            Log.w(TAG, "closeSegmenterForReload: tflite.close failed", e)
        }
        synchronized(maskLock) {
            currentMask = null
            inferenceInFlight = false
            pendingMpInputImage = null
        }
    }

    private fun buildSegmenterAttemptChain(): List<SegmenterAttempt> {
        val assets = try {
            context.assets.list("")?.toSet().orEmpty()
        } catch (_: Throwable) {
            emptySet()
        }
        preferredModel?.let { modelKey ->
            val config = modelConfig(modelKey) ?: return emptyList()
            if (config.asset in assets) {
                return listOf(
                    SegmenterAttempt(config, SegmenterBackendKind.TFLITE_GPU),
                    SegmenterAttempt(config, SegmenterBackendKind.MEDIAPIPE_CPU),
                )
            }
            return emptyList()
        }
        val chain = mutableListOf<SegmenterAttempt>()
        listOf("landscape", "single").forEach { key ->
            val config = modelConfig(key) ?: return@forEach
            if (config.asset in assets) {
                chain += SegmenterAttempt(config, SegmenterBackendKind.TFLITE_GPU)
            }
        }
        listOf("landscape", "single").forEach { key ->
            val config = modelConfig(key) ?: return@forEach
            if (config.asset in assets) {
                chain += SegmenterAttempt(config, SegmenterBackendKind.MEDIAPIPE_CPU)
            }
        }
        return chain
    }

    private fun createSegmenter(
        modelAsset: String,
        delegate: Delegate,
        useCategoryMask: Boolean,
    ): ImageSegmenter {
        // Load model into a direct ByteBuffer — APK mmap via setModelAssetPath can misalign TFLite
        // metadata (AGP 4-byte vs 16-byte) and fail Open() with bogus "batch size mismatch".
        val modelBuffer = loadModelBuffer(modelAsset)
        val base = BaseOptions.builder()
            .setModelAssetBuffer(modelBuffer)
            .setDelegate(delegate)
            .build()
        // CPU chain uses confidence masks; category-mask branch kept for a future MediaPipe GPU fix.
        val opts = ImageSegmenter.ImageSegmenterOptions.builder()
            .setBaseOptions(base)
            .setRunningMode(RunningMode.LIVE_STREAM)
            .setOutputCategoryMask(useCategoryMask)
            .setOutputConfidenceMasks(!useCategoryMask)
            .setResultListener { result, _ -> onSegmenterResult(result) }
            .setErrorListener { error ->
                Log.w(TAG, "Segmenter error callback", error)
                clearInferenceInFlight()
            }
            .build()
        return ImageSegmenter.createFromOptions(context, opts)
    }

    /** Asset → direct ByteBuffer sized to declaredLength (see [createSegmenter]). */
    private fun loadModelBuffer(modelAsset: String): ByteBuffer {
        return context.assets.openFd(modelAsset).use { fd ->
            val size = fd.declaredLength.toInt().also {
                check(it > 0) { "$modelAsset has unknown declaredLength" }
            }
            val buffer = ByteBuffer.allocateDirect(size).order(ByteOrder.nativeOrder())
            fd.createInputStream().use { input ->
                val tmp = ByteArray(64 * 1024)
                var totalRead = 0
                while (totalRead < size) {
                    val read = input.read(tmp, 0, minOf(tmp.size, size - totalRead))
                    if (read <= 0) break
                    buffer.put(tmp, 0, read)
                    totalRead += read
                }
                check(totalRead == size) { "Short read for $modelAsset: $totalRead/$size" }
            }
            buffer.rewind()
            Log.i(TAG, "loadModelBuffer: $modelAsset loaded ${size / 1024} KiB into direct buffer")
            buffer
        }
    }

    /**
     * Cache directory for the GPU delegate's compiled kernels.
     *
     * `codeCacheDir` is the right home: the platform already clears it on app upgrade, which is
     * exactly when a cached kernel binary could go stale. Null if it cannot be created, which only
     * costs us the compile on next attach.
     */
    private fun gpuSerializationDir(): String? = try {
        java.io.File(context.codeCacheDir, "tflite_gpu")
            .takeIf { it.isDirectory || it.mkdirs() }
            ?.absolutePath
    } catch (e: Throwable) {
        Log.w(TAG, "gpuSerializationDir: unavailable", e)
        null
    }

    /** TFLite + GpuDelegate — bypasses MediaPipe Tasks GPU image conversion (Adreno CHECK crash). */
    private class TfliteGpuSegmenterBackend(
        private val modelAsset: String,
        private val isMulticlassModel: Boolean,
        private val inputWidth: Int,
        private val inputHeight: Int,
        private val modelBuffer: ByteBuffer,
        private val serializationDir: String?,
    ) : AutoCloseable {
        private enum class OutputLayout {
            NHWC,
            NCHW,
            HWC,
            HW,
        }

        private val executor: ExecutorService = Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "MeetBgBlur-TFLiteGpu").apply { isDaemon = true }
        }

        private var gpuDelegate: GpuDelegate? = null
        private var interpreter: Interpreter? = null
        private var inputBuffer: ByteBuffer? = null
        private var outputBuffer: ByteBuffer? = null
        private var outputLayout: OutputLayout = OutputLayout.NHWC
        private var outputWidth: Int = inputWidth
        private var outputHeight: Int = inputHeight
        private val inputPixelCount: Int = inputWidth * inputHeight
        private var outputChannels: Int = 1
        private var inputDataType: DataType = DataType.FLOAT32
        private var outputDataType: DataType = DataType.FLOAT32
        private var inputScale: Float = 1f
        private var inputZeroPoint: Int = 0
        private var outputScale: Float = 1f
        private var outputZeroPoint: Int = 0
        /** Staging arrays for the input tensor; see [runOnGpuThread] for why they exist. */
        private var inputFloatScratch: FloatArray? = null
        private var inputByteScratch: ByteArray? = null
        @Volatile
        private var isClosed: Boolean = false

        init {
            val future = executor.submit(Callable {
                initialiseOnGpuThread()
                // Probe one empty frame so delegate compilation and output tensor reads fail here,
                // where setupSegmenter can fall through to MediaPipe CPU, rather than on the first
                // camera frame.
                runOnGpuThread(IntArray(inputPixelCount))
            })
            try {
                future.get(TFLITE_GPU_INIT_TIMEOUT_MS, TimeUnit.MILLISECONDS)
            } catch (error: Throwable) {
                future.cancel(true)
                close()
                throw IllegalStateException("TFLite GPU backend init failed for $modelAsset", error)
            }
        }

        /**
         * [pixels] stays owned by the caller and must not be written again until one of the
         * callbacks fires — the single in-flight guard in the engine is what guarantees that.
         */
        fun segmentAsync(
            pixels: IntArray,
            onResult: (MaskSnapshot?) -> Unit,
            onError: (Throwable) -> Unit,
        ) {
            if (isClosed) {
                onError(IllegalStateException("TFLite backend is closed"))
                return
            }

            executor.execute {
                if (isClosed) {
                    onError(IllegalStateException("TFLite backend is closed"))
                    return@execute
                }
                try {
                    onResult(runOnGpuThread(pixels))
                } catch (error: Throwable) {
                    onError(error)
                }
            }
        }

        private fun initialiseOnGpuThread() {
            modelBuffer.rewind()
            val delegateOptions = GpuDelegateFactory.Options().apply {
                // Prefer throughput/latency over exact FP32 parity for a segmentation mask. The
                // mask is already feathered and upscaled in compositing, so FP16 precision loss is
                // visually negligible but can materially reduce GPU inference time on Adreno.
                setPrecisionLossAllowed(true)
                // We run the same graph on every camera frame for the whole call, which is exactly
                // what SUSTAINED_SPEED is for: the delegate keeps its compiled program and
                // intermediate GPU buffers alive between invocations. FAST_SINGLE_ANSWER optimises
                // for a one-shot answer and lets the delegate tear that state down, so a streaming
                // workload pays setup cost again on every frame.
                setInferencePreference(GpuDelegateFactory.Options.INFERENCE_PREFERENCE_SUSTAINED_SPEED)
                // No-op for FLOAT models, but enables delegate support for quantized paths where
                // available. Keeps one backend binary for both model families.
                setQuantizedModelsAllowed(true)
                // Cache the compiled kernels. Building them takes long enough that attach can hit
                // [TFLITE_GPU_INIT_TIMEOUT_MS] on slower GPUs and silently fall back to the CPU
                // segmenter for the whole call — a cache hit turns that into a load.
                serializationDir?.let { setSerializationParams(it, modelAsset) }
            }
            val delegate = GpuDelegate(delegateOptions)
            val options = Interpreter.Options()
                .addDelegate(delegate)
                // Delegation is usually partial — ops the GPU backend does not implement stay on
                // the CPU and run on these threads, in the middle of the graph. One thread makes
                // that fallback the bottleneck; two keeps it off the critical path without
                // competing with the capture thread for the whole little cluster.
                .setNumThreads(2)
            val created = Interpreter(modelBuffer, options)

            val inputTensor = created.getInputTensor(0)
            inputDataType = inputTensor.dataType()
            require(inputDataType == DataType.FLOAT32 || inputDataType == DataType.UINT8) {
                "Unsupported input tensor type=${inputTensor.dataType()}"
            }
            inputTensor.quantizationParams()?.let { qp ->
                inputScale = qp.scale
                inputZeroPoint = qp.zeroPoint
            }
            val inputShape = inputTensor.shape()
            require(inputShape.size == 4 && inputShape[0] == 1 && inputShape[3] == 3) {
                "Unsupported input tensor shape=${inputShape.joinToString(prefix = "[", postfix = "]")}"
            }
            require(inputShape[1] == inputHeight && inputShape[2] == inputWidth) {
                "Unsupported input size=${inputShape.joinToString(prefix = "[", postfix = "]")} " +
                    "expected [1,$inputHeight,$inputWidth,3]"
            }

            val outputTensor = created.getOutputTensor(0)
            outputDataType = outputTensor.dataType()
            require(outputDataType == DataType.FLOAT32 || outputDataType == DataType.UINT8) {
                "Unsupported output tensor type=${outputTensor.dataType()}"
            }
            outputTensor.quantizationParams()?.let { qp ->
                outputScale = qp.scale
                outputZeroPoint = qp.zeroPoint
            }
            configureOutputShape(outputTensor.shape())

            inputBuffer = ByteBuffer
                .allocateDirect(
                    inputPixelCount * 3 *
                        if (inputDataType == DataType.FLOAT32) java.lang.Float.BYTES else 1,
                )
                .order(ByteOrder.nativeOrder())
            outputBuffer = ByteBuffer
                .allocateDirect(outputTensor.numBytes())
                .order(ByteOrder.nativeOrder())
            gpuDelegate = delegate
            interpreter = created

            Log.i(
                TAG,
                "TFLiteGpuBackend: initialised model=$modelAsset output=${outputWidth}x$outputHeight" +
                    "x$outputChannels layout=$outputLayout bytes=${outputTensor.numBytes()} " +
                    "inputType=$inputDataType outputType=$outputDataType",
            )
        }

        private fun configureOutputShape(shape: IntArray) {
            when (shape.size) {
                4 -> {
                    require(shape[0] == 1) {
                        "Unsupported output batch shape=${shape.joinToString(prefix = "[", postfix = "]")}"
                    }
                    if (shape[1] == inputHeight && shape[2] == inputWidth) {
                        outputLayout = OutputLayout.NHWC
                        outputHeight = shape[1]
                        outputWidth = shape[2]
                        outputChannels = shape[3]
                    } else if (shape[2] == inputHeight && shape[3] == inputWidth) {
                        outputLayout = OutputLayout.NCHW
                        outputChannels = shape[1]
                        outputHeight = shape[2]
                        outputWidth = shape[3]
                    } else {
                        throw IllegalArgumentException(
                            "Unsupported output shape=${shape.joinToString(prefix = "[", postfix = "]")}",
                        )
                    }
                }
                3 -> {
                    if (shape[0] == 1) {
                        outputLayout = OutputLayout.HW
                        outputHeight = shape[1]
                        outputWidth = shape[2]
                        outputChannels = 1
                    } else {
                        outputLayout = OutputLayout.HWC
                        outputHeight = shape[0]
                        outputWidth = shape[1]
                        outputChannels = shape[2]
                    }
                }
                2 -> {
                    outputLayout = OutputLayout.HW
                    outputHeight = shape[0]
                    outputWidth = shape[1]
                    outputChannels = 1
                }
                else -> {
                    throw IllegalArgumentException(
                        "Unsupported output shape=${shape.joinToString(prefix = "[", postfix = "]")}",
                    )
                }
            }
            require(outputWidth > 0 && outputHeight > 0 && outputChannels > 0) {
                "Invalid output dims width=$outputWidth height=$outputHeight channels=$outputChannels"
            }
        }

        private fun runOnGpuThread(pixels: IntArray): MaskSnapshot? {
            val interp = interpreter ?: error("TFLite interpreter is not initialised")
            val input = inputBuffer ?: error("TFLite input buffer is not initialised")
            val output = outputBuffer ?: error("TFLite output buffer is not initialised")

            require(pixels.size == inputPixelCount) {
                "Unexpected input pixels=${pixels.size} expected=$inputPixelCount"
            }
            // Fill a plain array and hand it over in one bulk copy. Writing the tensor sample by
            // sample costs ~200 k bounds-checked direct-buffer writes per inference, which lands
            // squarely in the mask's end-to-end latency.
            input.rewind()
            val sampleCount = pixels.size * 3
            if (inputDataType == DataType.FLOAT32) {
                val staging = inputFloatScratch?.takeIf { it.size == sampleCount }
                    ?: FloatArray(sampleCount).also { inputFloatScratch = it }
                var i = 0
                var o = 0
                while (i < pixels.size) {
                    val px = pixels[i]
                    staging[o] = ((px ushr 16) and 0xFF) / 255f
                    staging[o + 1] = ((px ushr 8) and 0xFF) / 255f
                    staging[o + 2] = (px and 0xFF) / 255f
                    i++
                    o += 3
                }
                input.asFloatBuffer().put(staging)
            } else {
                val staging = inputByteScratch?.takeIf { it.size == sampleCount }
                    ?: ByteArray(sampleCount).also { inputByteScratch = it }
                var i = 0
                var o = 0
                while (i < pixels.size) {
                    val px = pixels[i]
                    staging[o] =
                        quantizeToUint8(((px ushr 16) and 0xFF) / 255f, inputScale, inputZeroPoint).toByte()
                    staging[o + 1] =
                        quantizeToUint8(((px ushr 8) and 0xFF) / 255f, inputScale, inputZeroPoint).toByte()
                    staging[o + 2] =
                        quantizeToUint8((px and 0xFF) / 255f, inputScale, inputZeroPoint).toByte()
                    i++
                    o += 3
                }
                input.put(staging)
            }
            input.rewind()
            output.rewind()
            interp.run(input, output)
            output.rewind()
            return if (outputDataType == DataType.FLOAT32) {
                makeSnapshotFromFloatOutput(output.asFloatBuffer())
            } else {
                makeSnapshotFromUint8Output(output.duplicate())
            }
        }

        private fun makeSnapshotFromFloatOutput(floatBuffer: java.nio.FloatBuffer): MaskSnapshot? {
            val n = outputWidth * outputHeight
            if (floatBuffer.capacity() < n * outputChannels) {
                Log.w(
                    TAG,
                    "TFLiteGpuBackend: short output buffer capacity=${floatBuffer.capacity()} expected=${n * outputChannels}",
                )
                return null
            }
            val alpha = ByteArray(n)
            var y = 0
            while (y < outputHeight) {
                var x = 0
                while (x < outputWidth) {
                    val outIndex = y * outputWidth + x
                    val p = foregroundProbabilityFloat(floatBuffer, x, y)
                    alpha[outIndex] = (p.coerceIn(0f, 1f) * 255f + 0.5f).toInt().toByte()
                    x++
                }
                y++
            }
            return MaskSnapshot(outputWidth, outputHeight, alpha)
        }

        private fun makeSnapshotFromUint8Output(buffer: ByteBuffer): MaskSnapshot? {
            val n = outputWidth * outputHeight
            if (buffer.remaining() < n * outputChannels) {
                Log.w(
                    TAG,
                    "TFLiteGpuBackend: short uint8 output remaining=${buffer.remaining()} expected=${n * outputChannels}",
                )
                return null
            }
            val alpha = ByteArray(n)
            var y = 0
            while (y < outputHeight) {
                var x = 0
                while (x < outputWidth) {
                    val outIndex = y * outputWidth + x
                    val p = foregroundProbabilityUint8(buffer, x, y)
                    alpha[outIndex] = (p.coerceIn(0f, 1f) * 255f + 0.5f).toInt().toByte()
                    x++
                }
                y++
            }
            return MaskSnapshot(outputWidth, outputHeight, alpha)
        }

        private fun foregroundProbabilityFloat(floatBuffer: java.nio.FloatBuffer, x: Int, y: Int): Float {
            return when {
                outputChannels == 1 -> valueAtFloat(floatBuffer, x, y, channel = 0)
                isMulticlassModel -> {
                    // Multiclass channel 0 is background, same convention as MediaPipe Tasks.
                    1f - valueAtFloat(floatBuffer, x, y, channel = MULTICLASS_BACKGROUND_INDEX)
                }
                else -> {
                    // Defensive for single-class models that expose [background, foreground]
                    // instead of a single foreground channel.
                    valueAtFloat(floatBuffer, x, y, channel = outputChannels - 1)
                }
            }
        }

        private fun foregroundProbabilityUint8(buffer: ByteBuffer, x: Int, y: Int): Float {
            return when {
                outputChannels == 1 -> valueAtUint8(buffer, x, y, channel = 0)
                isMulticlassModel -> {
                    1f - valueAtUint8(buffer, x, y, channel = MULTICLASS_BACKGROUND_INDEX)
                }
                else -> {
                    valueAtUint8(buffer, x, y, channel = outputChannels - 1)
                }
            }
        }

        private fun valueAtFloat(floatBuffer: java.nio.FloatBuffer, x: Int, y: Int, channel: Int): Float {
            val c = channel.coerceIn(0, outputChannels - 1)
            val index = when (outputLayout) {
                OutputLayout.NHWC -> (y * outputWidth + x) * outputChannels + c
                OutputLayout.NCHW -> c * outputWidth * outputHeight + y * outputWidth + x
                OutputLayout.HWC -> (y * outputWidth + x) * outputChannels + c
                OutputLayout.HW -> y * outputWidth + x
            }
            return floatBuffer.get(index)
        }

        private fun valueAtUint8(buffer: ByteBuffer, x: Int, y: Int, channel: Int): Float {
            val c = channel.coerceIn(0, outputChannels - 1)
            val index = when (outputLayout) {
                OutputLayout.NHWC -> (y * outputWidth + x) * outputChannels + c
                OutputLayout.NCHW -> c * outputWidth * outputHeight + y * outputWidth + x
                OutputLayout.HWC -> (y * outputWidth + x) * outputChannels + c
                OutputLayout.HW -> y * outputWidth + x
            }
            val q = buffer.get(index).toInt() and 0xFF
            return if (outputScale > 0f) {
                (q - outputZeroPoint) * outputScale
            } else {
                q / 255f
            }
        }

        private fun quantizeToUint8(real: Float, scale: Float, zeroPoint: Int): Int {
            val q = if (scale > 0f) {
                (real / scale + zeroPoint).toInt()
            } else {
                (real * 255f).toInt()
            }
            return q.coerceIn(0, 255)
        }

        override fun close() {
            isClosed = true
            val future = try {
                executor.submit(Callable {
                    try {
                        interpreter?.close()
                    } finally {
                        interpreter = null
                        try {
                            gpuDelegate?.close()
                        } finally {
                            gpuDelegate = null
                            inputBuffer = null
                            outputBuffer = null
                        }
                    }
                })
            } catch (_: Throwable) {
                null
            }
            try {
                future?.get(500, TimeUnit.MILLISECONDS)
            } catch (error: Throwable) {
                Log.w(TAG, "TFLiteGpuBackend: close timed out/failed", error)
            } finally {
                executor.shutdownNow()
            }
        }
    }

    /** Releases all native resources. Call from `detach`. */
    fun release() {
        clearReplacementBackground()
        Log.i(TAG, "release: draining inference before closing segmenter")
        // Null refs first so process() passthroughs; then poll in-flight until drain timeout.
        val toClose = segmenter
        val tfliteToClose = tfliteBackend
        segmenter = null
        tfliteBackend = null
        val drainUntilNs = System.nanoTime() + INFERENCE_DRAIN_TIMEOUT_NS
        var drainSpins = 0
        while (System.nanoTime() < drainUntilNs) {
            val stillInFlight = synchronized(maskLock) { inferenceInFlight }
            if (!stillInFlight) break
            drainSpins++
            try {
                Thread.sleep(5)
            } catch (ie: InterruptedException) {
                // If detach runs on an interrupted thread, don't crash — restore interruption
                // status and stop waiting; we'll close with the same safety fallback as timeout.
                Thread.currentThread().interrupt()
                Log.w(TAG, "release: drain sleep interrupted", ie)
                break
            }
        }
        val drained = synchronized(maskLock) { !inferenceInFlight }
        if (drained) {
            Log.i(TAG, "release: drained after $drainSpins spins")
        } else {
            Log.w(TAG, "release: inference still in flight after timeout — closing anyway (may SIGSEGV)")
        }

        try {
            toClose?.close()
        } catch (e: Throwable) {
            Log.w(TAG, "release: segmenter.close failed", e)
        }
        try {
            tfliteToClose?.close()
        } catch (e: Throwable) {
            Log.w(TAG, "release: tflite.close failed", e)
        }
        synchronized(maskLock) {
            currentMask = null
            inferenceInFlight = false
            currentInferenceStartNs = 0L
            closePendingMpInputImageLocked()
        }
        // Drop large reusable arrays on detach so process lifetime doesn't pin peak sizes forever.
        i420ArgbScratch = null
        i420YScratch = null
        i420UScratch = null
        i420VScratch = null
        bitmapToI420Scratch = null
        blurPixelsScratch = null
        blurTmpScratch = null
        maskSrcArgbScratch = null
        segmenterPixelScratch = null
        featherPass1Scratch = null
        featherOutScratch = null
        erodePass1Scratch = null
        erodeOutScratch = null
        maskToneScratch = null
        shapedMaskSource = null
        shapedMaskEdge = null
        maskSrcBitmap?.recycle()
        maskSrcBitmap = null
        segmenterInputCanvas = null
        segmenterInputBitmap?.recycle()
        segmenterInputBitmap = null
        blurDownscaleCanvas = null
        blurDownscaleBitmap?.recycle()
        blurDownscaleBitmap = null
        pooledForegroundCanvas = null
        pooledForegroundBitmap?.recycle()
        pooledForegroundBitmap = null
        pooledArgbBitmap?.recycle()
        pooledArgbBitmap = null
        pooledComposedCanvas = null
        pooledComposedBitmap?.recycle()
        pooledComposedBitmap = null
        try {
            pooledOutputI420?.release()
        } catch (_: Throwable) {
            // ignore
        }
        pooledOutputI420 = null
        Log.i(TAG, "release: done")
    }

    // MARK: - Public entry point (called from the WebRTC video-processing thread).

    fun process(frame: VideoFrame): VideoFrame {
        // One backend read per frame — safe if release() nulls refs concurrently.
        val tflite = tfliteBackend
        val seg = segmenter
        if (tflite == null && seg == null) return frame
        val frameId = ++processFrameCount
        val shouldStageLog = frameId == 1L || frameId % STAGE_LOG_EVERY_NTH_FRAME == 0L

        // Stage 0: dispatch only when idle — one inference in flight, no queued mask lag.
        val canDispatch: Boolean
        val snapshot: MaskSnapshot?
        val perfSnapshot: PerfSnapshot
        synchronized(maskLock) {
            perfFramesSeen++
            canDispatch = !inferenceInFlight
            if (canDispatch) {
                inferenceInFlight = true
                currentInferenceStartNs = System.nanoTime()
                perfDispatchStarted++
            } else {
                perfDispatchSkipped++
            }
            snapshot = currentMask
            perfSnapshot = buildPerfSnapshotLocked()
        }

        // Stage 1: VideoFrame → ARGB bitmap (optional downscale via [PROCESSING_LONG_SIDE]).
        val inputBitmap = try {
            frameToBitmap(frame, capLongSide = PROCESSING_LONG_SIDE)
        } catch (oom: OutOfMemoryError) {
            Log.e(TAG, "process[frameToBitmap]: OOM at frame=$frameId — passthrough", oom)
            if (canDispatch) clearInferenceInFlight()
            return frame
        } catch (t: Throwable) {
            Log.e(TAG, "process[frameToBitmap]: threw at frame=$frameId — passthrough", t)
            if (canDispatch) clearInferenceInFlight()
            return frame
        }
        if (inputBitmap == null) {
            if (canDispatch) clearInferenceInFlight()
            return frame
        }
        if (shouldStageLog) {
            Log.d(
                TAG,
                "process: frame=$frameId input=${inputBitmap.width}x${inputBitmap.height} " +
                    "rot=${frame.rotation} model=${segmenterInputWidth}x$segmenterInputHeight " +
                    "snapshot=${snapshot?.let { "${it.width}x${it.height}@${it.sourceRotation}" } ?: "null"} " +
                    "canDispatch=$canDispatch",
            )
            Log.d(
                TAG,
                "perf: frames=${perfSnapshot.framesSeen} dispatch=${perfSnapshot.dispatchStarted}/" +
                    "${perfSnapshot.dispatchStarted + perfSnapshot.dispatchSkipped} " +
                    "hit=${formatPct(perfSnapshot.dispatchHitRate)} " +
                    "infer(last/avg/max)=${perfSnapshot.inferenceLastMs}/" +
                    "${String.format(Locale.US, "%.1f", perfSnapshot.inferenceAvgMs)}/" +
                    "${perfSnapshot.inferenceMaxMs}ms " +
                    "done=${perfSnapshot.inferencesCompleted} fail=${perfSnapshot.inferencesFailed}",
            )
        }

        // Stage 2: hand the bitmap to the active segmenter async if we're allowed. Failures clear
        // in-flight slot and fall through to the compositing path with whatever stale mask we have
        // — never leaves the pipeline stuck.
        if (canDispatch) {
            try {
                dispatchAsyncSegmentation(tflite, seg, inputBitmap, frame.rotation)
            } catch (oom: OutOfMemoryError) {
                Log.e(TAG, "process[dispatchAsyncSegmentation]: OOM at frame=$frameId", oom)
                clearInferenceInFlight()
            } catch (t: Throwable) {
                Log.e(TAG, "process[dispatchAsyncSegmentation]: threw at frame=$frameId", t)
                clearInferenceInFlight()
            }
        }

        if (snapshot == null) {
            // No mask yet (first inference still in flight) — pass the original frame through
            // unchanged. Mirrors iOS behaviour of leaving the frame untouched on warmup.
            return frame
        }

        // Stage 3: composite the input frame with the latest mask + blurred background.
        val composed = try {
            composeWithMask(inputBitmap, snapshot, frame.rotation)
        } catch (oom: OutOfMemoryError) {
            Log.e(TAG, "process[composeWithMask]: OOM at frame=$frameId — passthrough", oom)
            return frame
        } catch (t: Throwable) {
            Log.e(TAG, "process[composeWithMask]: threw at frame=$frameId — passthrough", t)
            return frame
        }
        if (composed == null) return frame

        // Stage 4: pack ARGB into the pooled I420 buffer (edit buffer bytes, not `VideoFrame.release`).
        return try {
            writeBitmapIntoPooledI420(composed, frame)
        } catch (oom: OutOfMemoryError) {
            Log.e(TAG, "process[writeBitmapIntoPooledI420]: OOM at frame=$frameId — passthrough", oom)
            frame
        } catch (t: Throwable) {
            Log.e(TAG, "process[writeBitmapIntoPooledI420]: threw at frame=$frameId — passthrough", t)
            frame
        }
    }

    /**
     * Renders [source] upright and squashed to the model's input size in one filtered draw.
     *
     * [rotationDegrees] is the angle the renderer will apply downstream, so applying it here puts
     * the pixels in the orientation the viewer will eventually see — which is the orientation the
     * model was trained on. Feeding the model a sideways subject is what made the mask track while
     * you held still and fall apart as soon as you moved; `MeetBackgroundBlurMediaPipeEngine.swift`
     * applies the same correction through `visionOrientation(forRotationDegrees:)`.
     *
     * Rotation and downscale are a single matrix because doing them as two `Bitmap.createBitmap`
     * calls meant a frame-sized allocation and a 900 k-pixel resample per step, on the capture
     * thread, before the inference this gates could even start.
     *
     * Squashing the aspect ratio is intentional — masks are upscaled back to the camera aspect at
     * compositing time.
     */
    private fun renderSegmenterInput(source: Bitmap, rotationDegrees: Int): Bitmap? {
        val dstW = segmenterInputWidth
        val dstH = segmenterInputHeight
        val bitmap = segmenterInputBitmap
            ?.takeIf { !it.isRecycled && it.width == dstW && it.height == dstH }
            ?: try {
                segmenterInputBitmap?.recycle()
                Bitmap.createBitmap(dstW, dstH, Bitmap.Config.ARGB_8888).also {
                    segmenterInputBitmap = it
                    segmenterInputCanvas = Canvas(it)
                }
            } catch (e: OutOfMemoryError) {
                Log.w(TAG, "renderSegmenterInput: OOM allocating ${dstW}x$dstH input", e)
                segmenterInputBitmap = null
                segmenterInputCanvas = null
                return null
            }
        val canvas = segmenterInputCanvas ?: Canvas(bitmap).also { segmenterInputCanvas = it }

        val rotation = ((rotationDegrees % 360) + 360) % 360
        // A quarter turn swaps the axes, so the scale has to be measured against the rotated
        // extent or the frame ends up squashed along the wrong one.
        val quarterTurned = rotation == 90 || rotation == 270
        val rotatedW = if (quarterTurned) source.height else source.width
        val rotatedH = if (quarterTurned) source.width else source.height
        if (rotatedW <= 0 || rotatedH <= 0) return null

        segmenterInputMatrix.reset()
        segmenterInputMatrix.postTranslate(-source.width / 2f, -source.height / 2f)
        segmenterInputMatrix.postRotate(rotation.toFloat())
        segmenterInputMatrix.postTranslate(rotatedW / 2f, rotatedH / 2f)
        segmenterInputMatrix.postScale(dstW.toFloat() / rotatedW, dstH.toFloat() / rotatedH)
        // SRC so the previous frame's content is replaced rather than blended; the draw covers the
        // destination exactly, which also makes an explicit clear unnecessary.
        canvas.drawBitmap(source, segmenterInputMatrix, maskUpscalePaint)
        return bitmap
    }

    /**
     * Hands the current frame to the active async segmentation backend. Returns immediately; the
     * result is delivered later via the backend listener/callback. Caller must have already set
     * `inferenceInFlight = true`. Failure paths clear the flag again so the pipeline never gets
     * stuck with no in-flight inference.
     */
    private fun dispatchAsyncSegmentation(
        tflite: TfliteGpuSegmenterBackend?,
        seg: ImageSegmenter?,
        srcBitmap: Bitmap,
        rotationDegrees: Int,
    ) {
        try {
            val small = renderSegmenterInput(srcBitmap, rotationDegrees)
            if (small == null) {
                clearInferenceInFlight()
                return
            }
            // Un-rotating a mask by an angle the frame was never turned by would put the silhouette
            // a quarter turn away from the person, so stamp the angle the draw actually applied.
            pendingInferenceRotation = ((rotationDegrees % 360) + 360) % 360

            segmentClockMs += 33L
            if (tflite != null) {
                // Read the pixels out here rather than handing the pooled bitmap to the backend:
                // the single in-flight guard means nothing else can touch this array until the
                // result lands, and it keeps the pooled bitmap out of the backend's ownership.
                val needed = small.width * small.height
                val pixels = segmenterPixelScratch?.takeIf { it.size == needed }
                    ?: IntArray(needed).also { segmenterPixelScratch = it }
                small.getPixels(pixels, 0, small.width, 0, 0, small.width, small.height)
                tflite.segmentAsync(
                    pixels,
                    onResult = { snapshot -> completeInference(success = true, newSnapshot = snapshot) },
                    onError = { error ->
                        Log.w(TAG, "TFLite segmentAsync failed", error)
                        clearInferenceInFlight()
                    },
                )
            } else if (seg != null) {
                // MediaPipe holds the bitmap until its result callback fires, and that callback is
                // also what releases the in-flight slot — so handing it the pooled bitmap would let
                // the next dispatch redraw pixels it is still reading. This path is the CPU
                // fallback and the copy is only 256 KiB, so pay for the isolation.
                val mpImage = BitmapImageBuilder(
                    small.copy(Bitmap.Config.ARGB_8888, /* isMutable = */ false)
                        ?: run {
                            Log.w(TAG, "dispatchAsyncSegmentation: segmenter input copy returned null")
                            clearInferenceInFlight()
                            return
                        },
                ).build()
                synchronized(maskLock) {
                    // Defensive: there should be only one in-flight image due to inferenceInFlight
                    // gating, but if callbacks are delayed we still close any stale input here.
                    closePendingMpInputImageLocked()
                    pendingMpInputImage = mpImage
                }
                seg.segmentAsync(mpImage, segmentClockMs)
            } else {
                clearInferenceInFlight()
            }
        } catch (e: Throwable) {
            Log.w(TAG, "segmentAsync failed", e)
            clearInferenceInFlight()
        }
    }

    private fun onSegmenterResult(result: ImageSegmenterResult) {
        // Build the new snapshot if we got a valid mask; otherwise fall through to the unlock
        // block at the bottom so the in-flight slot is always released — otherwise a MediaPipe
        // error would stall the pipeline forever.
        //
        // Note: `ImageSegmenterResult` itself is **not** AutoCloseable on Android (unlike a
        // CVPixelBuffer on iOS). The native resources are held by the `MPImage` objects inside
        // `confidenceMasks()` / `categoryMask()` — those implement `AutoCloseable` and **must**
        // be closed once we're done extracting data, otherwise the JNI buffer reference count
        // keeps growing.
        var newSnapshot: MaskSnapshot? = null
        val masks: List<MPImage> = try {
            if (usesCategoryMaskOutput) {
                listOfNotNull(result.categoryMask().orElse(null))
            } else {
                result.confidenceMasks().orElse(null).orEmpty()
            }
        } catch (e: Throwable) {
            Log.w(
                TAG,
                "onSegmenterResult: ${if (usesCategoryMaskOutput) "categoryMask()" else "confidenceMasks()"} failed",
                e,
            )
            emptyList()
        }
        try {
            val first = masks.firstOrNull()
            if (first != null) {
                newSnapshot = if (usesCategoryMaskOutput) {
                    makeForegroundSnapshotFromCategory(first)
                } else {
                    // For multiclass `confidenceMasks[0]` is background probability, for single-
                    // class it's foreground probability. `makeForegroundSnapshot` normalises to
                    // "foreground alpha" so the compositing path doesn't have to branch.
                    makeForegroundSnapshot(first)
                }
            }
        } catch (e: Throwable) {
            Log.w(TAG, "onSegmenterResult: snapshot conversion failed", e)
        } finally {
            // Always release every mask MediaPipe handed us, even if we couldn't read one.
            masks.forEach { mask ->
                try {
                    mask.close()
                } catch (_: Throwable) {
                    // ignore
                }
            }
        }

        synchronized(maskLock) {
            if (newSnapshot != null) currentMask = newSnapshot
        }
        completeInference(success = true)
    }

    /**
     * Copies the Float32 confidence mask out of MediaPipe's transient buffer and converts it to
     * a UInt8 foreground-alpha array in a single pass. For multiclass models we invert here
     * (`1 - p_background = p_foreground`); for single-class we use the raw probability.
     *
     * MediaPipe owns the mask buffer only for the duration of the listener call — copy it before
     * the function returns.
     */
    private fun makeForegroundSnapshot(mask: MPImage): MaskSnapshot? {
        val w = mask.width
        val h = mask.height
        if (w <= 0 || h <= 0) return null

        val byteBuffer = ByteBufferExtractor.extract(mask).order(ByteOrder.nativeOrder())
        val floatBuffer = byteBuffer.asFloatBuffer()
        val n = w * h
        val alpha = ByteArray(n)
        val invert = isMulticlassModel
        var i = 0
        while (i < n) {
            val c = floatBuffer.get(i)
            val p = if (invert) 1f - c else c
            val byte = (p.coerceIn(0f, 1f) * 255f + 0.5f).toInt()
            alpha[i] = byte.toByte()
            i++
        }
        return MaskSnapshot(w, h, alpha)
    }

    /**
     * Reads MediaPipe's UInt8 category-mask buffer (one byte per pixel = argmax class index) and
     * converts it to a binary foreground-alpha array. Class 0 is background for both supported
     * models (single-class: `{0=bg, 1=person}`; multiclass: `{0=bg, 1..5=person parts}`), so the
     * rule collapses to `fg = (class != 0) ? 255 : 0` regardless of [isMulticlassModel].
     *
     * The hard 0/255 transitions get smoothed back into a soft edge by the larger
     * [MASK_FEATHER_SIGMA_CATEGORY] applied in [composeWithMask] plus the bilinear upscale to
     * processing resolution.
     */
    private fun makeForegroundSnapshotFromCategory(mask: MPImage): MaskSnapshot? {
        val w = mask.width
        val h = mask.height
        if (w <= 0 || h <= 0) return null

        val srcBuffer = ByteBufferExtractor.extract(mask)
        val n = w * h
        if (srcBuffer.remaining() < n) {
            Log.w(
                TAG,
                "makeForegroundSnapshotFromCategory: short buffer ${srcBuffer.remaining()} < $n " +
                    "(pos=${srcBuffer.position()} lim=${srcBuffer.limit()})",
            )
            return null
        }
        val alpha = ByteArray(n)
        // `duplicate()` gives us a thread-local view of MediaPipe's buffer (independent
        // position/limit) so a relative bulk read is safe AND correct regardless of where
        // MediaPipe left the original buffer's position. Bulk `get(byte[], offset, length)` is
        // a single JNI memcpy on direct buffers — much cheaper than a per-byte loop.
        try {
            srcBuffer.duplicate().get(alpha, 0, n)
        } catch (e: Throwable) {
            // Defensive: if the buffer had limit < position + n (despite remaining() saying
            // otherwise) or some other malformed state, fall back to passing the previous mask
            // through rather than corrupting the snapshot.
            Log.w(TAG, "makeForegroundSnapshotFromCategory: bulk read failed", e)
            return null
        }
        var i = 0
        while (i < n) {
            // After bulk read, `alpha[i]` holds the raw class-index byte. `Byte.toInt()` sign-
            // extends (so 0xFF reads as -1); `and 0xFF` keeps it in `0..255`. Class 0 is
            // background for both supported models — see file header.
            val cls = alpha[i].toInt() and 0xFF
            alpha[i] = if (cls == 0) 0.toByte() else 0xFF.toByte()
            i++
        }
        return MaskSnapshot(w, h, alpha)
    }

    private fun clearInferenceInFlight() {
        completeInference(success = false)
    }

    private fun completeInference(success: Boolean, newSnapshot: MaskSnapshot? = null) {
        val endNs = System.nanoTime()
        synchronized(maskLock) {
            closePendingMpInputImageLocked()
            // Stamp the angle the frame was rotated by before inference. Only one inference is ever
            // in flight, so this still describes the frame that produced `newSnapshot`.
            if (newSnapshot != null) {
                currentMask = newSnapshot.copy(sourceRotation = pendingInferenceRotation)
            }

            val hadInFlight = inferenceInFlight || currentInferenceStartNs > 0L
            val startedNs = currentInferenceStartNs
            inferenceInFlight = false
            currentInferenceStartNs = 0L

            if (!hadInFlight) return

            if (success) {
                perfInferencesCompleted++
            } else {
                perfInferencesFailed++
            }

            if (startedNs > 0L) {
                val durMs = ((endNs - startedNs) / 1_000_000L).coerceAtLeast(0L)
                perfInferenceLastMs = durMs
                perfInferenceTotalMs += durMs
                if (durMs > perfInferenceMaxMs) perfInferenceMaxMs = durMs
            }
        }
    }

    private fun closePendingMpInputImageLocked() {
        val pending = pendingMpInputImage ?: return
        pendingMpInputImage = null
        try {
            pending.close()
        } catch (_: Throwable) {
            // ignore
        }
    }

    private fun buildPerfSnapshotLocked(): PerfSnapshot {
        val dispatchDecisions = perfDispatchStarted + perfDispatchSkipped
        val hitRate = if (dispatchDecisions > 0L) {
            perfDispatchStarted.toDouble() / dispatchDecisions.toDouble()
        } else {
            0.0
        }
        val avgMs = if (perfInferencesCompleted > 0L) {
            perfInferenceTotalMs.toDouble() / perfInferencesCompleted.toDouble()
        } else {
            0.0
        }
        return PerfSnapshot(
            framesSeen = perfFramesSeen,
            dispatchStarted = perfDispatchStarted,
            dispatchSkipped = perfDispatchSkipped,
            inferencesCompleted = perfInferencesCompleted,
            inferencesFailed = perfInferencesFailed,
            dispatchHitRate = hitRate,
            inferenceLastMs = perfInferenceLastMs,
            inferenceAvgMs = avgMs,
            inferenceMaxMs = perfInferenceMaxMs,
        )
    }

    private fun formatPct(value: Double): String =
        String.format(Locale.US, "%.1f%%", value * 100.0)

    // MARK: - Compositing.

    /**
     * Produces the final `original × foreground + blurred × background` bitmap.
     *
     * Build order, mirroring iOS:
     *   1. Feather the 256² mask with a small Gaussian (run on the small mask, ~30× cheaper than
     *      feathering at compositing resolution; the σ then stretches during upscale into a
     *      ~σ × upscaleFactor pixel-wide soft edge — exactly what hides 1-2 frames of inference
     *      lag without bleeding into the subject).
     *   2. Background blur — downscale, box-blur.
     *   3. Composite via `Canvas` + `PorterDuff.SRC_IN`: keep the sharp `input` where the mask
     *      is foreground, fall back to `blurred` elsewhere.
     *
     * Both the mask and the blurred plate stay at their own small resolutions until the
     * compositing draws, which scale them as they fill the frame. Resizing either into a
     * frame-sized bitmap first was an allocation and a resample for pixels about to be resampled.
     */
    private fun composeWithMask(
        input: Bitmap,
        snapshot: MaskSnapshot,
        rotationDegrees: Int,
    ): Bitmap? {
        val w = input.width
        val h = input.height

        val maskBitmap = shapedMaskBitmap(snapshot) ?: return null
        // The segmenter analysed an upright frame, so its mask is in upright space. Undo that turn
        // to land back in buffer space, which is what the sharp frame and the blurred plate are in.
        val maskMatrix = maskDrawMatrix(
            snapshot.width,
            snapshot.height,
            w,
            h,
            snapshot.sourceRotation + MASK_UNROTATE_BIAS_DEGREES,
        )

        if (debugMaskOverlay) {
            return drawMaskOverlay(input, maskBitmap, maskMatrix, w, h)
        }

        val plate = makeBackgroundPlate(input, w, h, rotationDegrees)
            ?: return null

        // 1) Off-screen layer: draw the foreground-alpha mask, then composite the sharp `input` on
        //    top with SRC_IN so it survives only where the mask is opaque. This is the equivalent
        //    of iOS's `CIBlendWithMask(input=sharp, bg=blurred, mask=foreground)`, built into a
        //    pooled layer instead of a `saveLayer` so it costs no frame-sized allocation. The mask
        //    upscales straight into this layer — going through a frame-sized mask bitmap first
        //    would be an extra full-frame draw for the same pixels.
        val foreground = ensureForegroundBitmap(w, h) ?: return null
        val foregroundCanvas = pooledForegroundCanvas ?: return null
        foregroundCanvas.drawBitmap(maskBitmap, maskMatrix, maskUpscalePaint)
        foregroundCanvas.drawBitmap(input, 0f, 0f, srcInPaint)

        val out = ensureComposedBitmap(w, h)
        val canvas = pooledComposedCanvas ?: return null

        // 2) Fill output with the background plate, optionally veiled for extra privacy.
        //    Desaturation rides on the draw as a colour filter so Skia does it while it is already
        //    touching these pixels, instead of a getPixels/setPixels round trip over the frame.
        //    The blurred plate is smaller than the frame and Skia scales it up as part of this
        //    draw — it has to touch every destination pixel either way, so resampling it into a
        //    frame-sized bitmap beforehand was a wasted allocation and a wasted pass.
        plateDstRect.set(0, 0, w, h)
        canvas.drawBitmap(plate.bitmap, null, plateDstRect, platePaint(plate.wantsDesaturation))
        if (plate.wantsObscureVeil && backgroundObscureOpacity > 0f) {
            val alpha = (backgroundObscureOpacity * 255f).toInt().coerceIn(0, 255)
            veilPaint.color = android.graphics.Color.argb(alpha, 115, 115, 122)
            canvas.drawRect(0f, 0f, w.toFloat(), h.toFloat(), veilPaint)
        }

        // 3) Lay the masked foreground over the background.
        canvas.drawBitmap(foreground, 0f, 0f, null)

        return out
    }

    /**
     * Debug view: the sharp frame with the foreground mask tinted red over it.
     *
     * Deliberately skips the background plate, so what you see is the mask itself rather than its
     * effect on a blur. Red where the mask calls foreground, untinted where it calls background,
     * and the tint tracks the mask's alpha so the feathered edge stays visible. A correct mask is
     * a red silhouette sitting exactly on the subject.
     */
    private fun drawMaskOverlay(
        input: Bitmap,
        maskBitmap: Bitmap,
        maskMatrix: Matrix,
        w: Int,
        h: Int,
    ): Bitmap? {
        // SRC_IN in the pooled layer keeps the mask's alpha and swaps its colour for red; drawing
        // the layer over the frame then leaves the tint translucent where the mask is feathered.
        val foreground = ensureForegroundBitmap(w, h) ?: return null
        val foregroundCanvas = pooledForegroundCanvas ?: return null
        foregroundCanvas.drawBitmap(maskBitmap, maskMatrix, maskUpscalePaint)
        foregroundCanvas.drawColor(android.graphics.Color.argb(150, 255, 0, 0), PorterDuff.Mode.SRC_IN)

        val out = ensureComposedBitmap(w, h)
        val canvas = pooledComposedCanvas ?: return null
        canvas.drawBitmap(input, 0f, 0f, null)
        canvas.drawBitmap(foreground, 0f, 0f, null)
        return out
    }

    /**
     * Shapes the raw segmentation alpha into the mask used for blending.
     *
     * Runs Apple's stages in Apple's order — erode, solidify, feather, gamma — because the order
     * is what keeps the dials independent. The previous Android order (gamma, then feather, with a
     * fixed σ and no erode or solidify) is what produced the two long-standing complaints:
     *
     *  * **Body partly erased.** The segmenter reports *confidence*, not coverage, so the interior
     *    of a person routinely sits below 1.0. Without a solidify step those samples blend as
     *    translucent, and the hardcoded `gamma = 1.35` then pushed them further toward background,
     *    actively eating the subject. Solidify now makes the interior opaque and gamma defaults to
     *    the neutral 1.0.
     *  * **Background bleeding into the edge.** With no erosion the outline sat on (or outside) the
     *    true silhouette, and the feather spread it wider still, so a band of real background
     *    survived around the subject. Erosion pulls the outline in before the feather widens it.
     *
     * Apple runs all of this after upscaling to frame resolution. Doing that here would mean
     * per-pixel Kotlin loops over ~900 k pixels every frame, so we work in mask space and convert
     * the frame-height fractions to mask pixels — see [MaskEdgeTuning] for why the two are
     * equivalent. The cost is quantisation: one mask pixel is ~2.8 frame pixels at 720p, so
     * sub-pixel erosion radii round away rather than shifting the outline slightly.
     */
    private fun shapeMaskAlpha(snapshot: MaskSnapshot, edge: MaskEdgeTuning): ByteArray {
        // [edge] is read once by the caller and keys both the cached tables and the shaped-mask
        // cache. `setMaskEdgeTuning` runs on the platform thread while this runs on the capture
        // thread, so re-reading the field — or invalidating a cache separately from the value —
        // could shape one frame with the new erode radius and the old solidify curve.
        val maskH = snapshot.height
        val lut = maskToneLut?.takeIf { it.edge == edge }
            ?: buildMaskToneLut(edge).also { maskToneLut = it }

        val eroded = erodeMask(
            snapshot.foregroundAlpha,
            snapshot.width,
            maskH,
            radius = edge.erodeHeightFraction * maskH,
        )
        // A sub-pixel erode radius short-circuits and hands back the snapshot's own array. That
        // array is the cached mask, reused until the next inference lands, so mapping the LUT over
        // it in place would re-solidify the same mask on every frame until it saturated.
        val solidified = applyLut(detachIfShared(eroded, snapshot.foregroundAlpha), lut.solidify)

        // The binary category mask has no ramp of its own to widen, so it needs a floor well above
        // the confidence path's; below it the upscale produces a staircase instead of an edge.
        val featherFloor = if (usesCategoryMaskOutput) {
            MASK_FEATHER_SIGMA_CATEGORY
        } else {
            MASK_FEATHER_SIGMA_MIN_CONFIDENCE
        }
        val feathered = featherMask(
            snapshot.copy(foregroundAlpha = solidified),
            maxOf(edge.featherHeightFraction * maskH, featherFloor),
        )
        return lut.gamma?.let { applyLut(feathered, it) } ?: feathered
    }

    private fun buildMaskToneLut(edge: MaskEdgeTuning): MaskToneLut {
        // Same linear stretch about the midpoint that `solidifyMask` runs as a CIColorMatrix on
        // Apple, clamped for the same reason: the stretch pushes values past 0 and 1, and an
        // out-of-range alpha survives into the blend.
        val solidify = ByteArray(256)
        val slope = edge.solidifySlope
        val bias = 0.5f - slope * edge.solidifyMidpoint
        for (i in 0..255) {
            val v = if (slope > 1f) slope * (i / 255f) + bias else i / 255f
            solidify[i] = (v * 255f).toInt().coerceIn(0, 255).toByte()
        }

        val gamma = if (edge.foregroundGamma == 1f) {
            null
        } else {
            ByteArray(256).also { table ->
                for (i in 0..255) {
                    val v = Math.pow((i / 255f).toDouble(), edge.foregroundGamma.toDouble())
                    table[i] = (v * 255.0).toInt().coerceIn(0, 255).toByte()
                }
            }
        }
        return MaskToneLut(edge, solidify, gamma)
    }

    /** Copies into engine-owned scratch when [candidate] still aliases the cached mask. */
    private fun detachIfShared(candidate: ByteArray, shared: ByteArray): ByteArray {
        if (candidate !== shared) return candidate
        val scratch = maskToneScratch?.takeIf { it.size == candidate.size }
            ?: ByteArray(candidate.size).also { maskToneScratch = it }
        candidate.copyInto(scratch)
        return scratch
    }

    /** In-place table map; the mask arrays are already engine-owned scratch. */
    private fun applyLut(alpha: ByteArray, lut: ByteArray): ByteArray {
        var i = 0
        while (i < alpha.size) {
            alpha[i] = lut[alpha[i].toInt() and 0xFF]
            i++
        }
        return alpha
    }

    /**
     * Separable minimum filter — the counterpart of `CIMorphologyMinimum` in `erodeMask` on Apple.
     *
     * Erosion by a square structuring element is separable, so this is two O(w × h × radius)
     * passes rather than a 2-D window. Radii under half a pixel are dropped, matching the
     * `radius >= 0.5` guard on the Apple side.
     */
    private fun erodeMask(src: ByteArray, w: Int, h: Int, radius: Float): ByteArray {
        val r = (radius + 0.5f).toInt()
        if (r < 1) return src

        val needed = w * h
        val pass1 = erodePass1Scratch?.takeIf { it.size == needed }
            ?: ByteArray(needed).also { erodePass1Scratch = it }
        var y = 0
        while (y < h) {
            val rowOffset = y * w
            var x = 0
            while (x < w) {
                var m = 255
                var k = -r
                while (k <= r) {
                    val xx = (x + k).coerceIn(0, w - 1)
                    val v = src[rowOffset + xx].toInt() and 0xFF
                    if (v < m) m = v
                    k++
                }
                pass1[rowOffset + x] = m.toByte()
                x++
            }
            y++
        }

        val out = erodeOutScratch?.takeIf { it.size == needed }
            ?: ByteArray(needed).also { erodeOutScratch = it }
        var x = 0
        while (x < w) {
            var yy = 0
            while (yy < h) {
                var m = 255
                var k = -r
                while (k <= r) {
                    val ny = (yy + k).coerceIn(0, h - 1)
                    val v = pass1[ny * w + x].toInt() and 0xFF
                    if (v < m) m = v
                    k++
                }
                out[yy * w + x] = m.toByte()
                yy++
            }
            x++
        }
        return out
    }

    /**
     * Separable Gaussian-ish feather on the 256² mask. We approximate a Gaussian with a 1-D
     * separable kernel of radius `≈ 3σ` (clamped to `[1, 12]` so even the binary category-mask
     * path with `σ = 3.0` gets a full kernel). Mirrors the `applyingGaussianBlur` before the
     * upscale on the iOS side.
     */
    private fun featherMask(snapshot: MaskSnapshot, sigma: Float): ByteArray {
        val w = snapshot.width
        val h = snapshot.height
        val src = snapshot.foregroundAlpha
        if (sigma <= 0f) return src

        // 3σ covers ~99.7% of the Gaussian — enough for a smooth fade without artifacts at the
        // kernel edge. Cap at 12 so a runaway sigma can't make the per-frame cost explode.
        val radius = (sigma * 3f + 0.5f).toInt().coerceIn(1, 12)
        val kernel = FloatArray(radius * 2 + 1)
        var ksum = 0f
        for (i in -radius..radius) {
            val v = Math.exp(-(i * i) / (2.0 * sigma * sigma)).toFloat()
            kernel[i + radius] = v
            ksum += v
        }
        for (k in kernel.indices) kernel[k] /= ksum

        val pass1Needed = w * h
        val pass1 = featherPass1Scratch?.takeIf { it.size == pass1Needed }
            ?: ByteArray(pass1Needed).also { featherPass1Scratch = it }
        // Horizontal pass.
        var y = 0
        while (y < h) {
            val rowOffset = y * w
            var x = 0
            while (x < w) {
                var acc = 0f
                var k = -radius
                while (k <= radius) {
                    val xx = (x + k).coerceIn(0, w - 1)
                    acc += (src[rowOffset + xx].toInt() and 0xFF) * kernel[k + radius]
                    k++
                }
                pass1[rowOffset + x] = acc.toInt().coerceIn(0, 255).toByte()
                x++
            }
            y++
        }
        val out = featherOutScratch?.takeIf { it.size == pass1Needed }
            ?: ByteArray(pass1Needed).also { featherOutScratch = it }
        // Vertical pass.
        var x = 0
        while (x < w) {
            var yy = 0
            while (yy < h) {
                var acc = 0f
                var k = -radius
                while (k <= radius) {
                    val ny = (yy + k).coerceIn(0, h - 1)
                    acc += (pass1[ny * w + x].toInt() and 0xFF) * kernel[k + radius]
                    k++
                }
                out[yy * w + x] = acc.toInt().coerceIn(0, 255).toByte()
                yy++
            }
            x++
        }
        return out
    }

    /**
     * The shaped mask as an alpha-only ARGB bitmap at mask resolution (the RGB channels are
     * irrelevant — `PorterDuff.Mode.SRC_IN` only looks at alpha).
     *
     * Reuses the previous result while the snapshot and the tuning are unchanged. Inference is
     * slower than capture, so the same snapshot is composited onto several frames in a row and
     * re-shaping it each time recomputes an identical mask.
     */
    private fun shapedMaskBitmap(snapshot: MaskSnapshot): Bitmap? {
        val srcW = snapshot.width
        val srcH = snapshot.height
        if (srcW <= 0 || srcH <= 0) return null

        val edge = maskEdge
        val cached = maskSrcBitmap
        if (cached != null && !cached.isRecycled &&
            cached.width == srcW && cached.height == srcH &&
            shapedMaskSource === snapshot && shapedMaskEdge == edge
        ) {
            return cached
        }
        // Drop the stale marks first: a failure below must not leave the cache claiming that
        // `maskSrcBitmap` holds a mask it never got around to writing.
        shapedMaskSource = null
        shapedMaskEdge = null

        val alpha = shapeMaskAlpha(snapshot, edge)
        val srcNeeded = srcW * srcH
        val srcPixels = maskSrcArgbScratch?.takeIf { it.size == srcNeeded }
            ?: IntArray(srcNeeded).also { maskSrcArgbScratch = it }
        var i = 0
        while (i < srcPixels.size) {
            val a = alpha[i].toInt() and 0xFF
            srcPixels[i] = a shl 24 // RGB=0, alpha-only
            i++
        }

        // Cached rather than rebuilt per frame: `createBitmap` used to allocate a 256² ARGB_8888
        // buffer every frame, pure allocator churn feeding the GC.
        val src = reuseBitmap(maskSrcBitmap, srcW, srcH)?.also { maskSrcBitmap = it } ?: return null
        src.setPixels(srcPixels, 0, srcW, 0, 0, srcW, srcH)
        shapedMaskSource = snapshot
        shapedMaskEdge = edge
        return src
    }

    /**
     * Transform that lays the mask-resolution bitmap over the frame, undoing [sourceRotation].
     *
     * Returns the shared [maskUpscaleMatrix], so the caller must consume it before the next call.
     */
    private fun maskDrawMatrix(
        srcW: Int,
        srcH: Int,
        dstW: Int,
        dstH: Int,
        sourceRotation: Int,
    ): Matrix {
        val rotation = ((sourceRotation % 360) + 360) % 360
        // A quarter turn swaps the axes, so the scale has to be measured against the rotated
        // extent rather than the raw mask, or the mask ends up stretched along the wrong axis.
        val quarterTurned = rotation == 90 || rotation == 270
        val rotatedW = if (quarterTurned) srcH else srcW
        val rotatedH = if (quarterTurned) srcW else srcH

        maskUpscaleMatrix.reset()
        maskUpscaleMatrix.postTranslate(-srcW / 2f, -srcH / 2f)
        maskUpscaleMatrix.postRotate(-rotation.toFloat())
        maskUpscaleMatrix.postTranslate(rotatedW / 2f, rotatedH / 2f)
        maskUpscaleMatrix.postScale(dstW.toFloat() / rotatedW, dstH.toFloat() / rotatedH)
        return maskUpscaleMatrix
    }

    /** Returns [cached] when it already matches, otherwise a fresh mutable ARGB bitmap. */
    private fun reuseBitmap(cached: Bitmap?, w: Int, h: Int): Bitmap? {
        if (cached != null && !cached.isRecycled && cached.width == w && cached.height == h) {
            return cached
        }
        cached?.recycle()
        return try {
            Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        } catch (e: OutOfMemoryError) {
            Log.w(TAG, "reuseBitmap: OOM allocating ${w}x$h mask scratch", e)
            null
        }
    }

    /**
     * [wantsObscureVeil] is false for replacement images: the veil hides the real room, so tinting
     * a picture the user deliberately chose only mutes it. Mirrors iOS `makeBackgroundPlate`,
     * which returns the replacement before `applyObscureVeil` runs.
     */
    /** Both plate sources are engine-owned and outlive the frame, so neither is recycled here. */
    private class BackgroundPlate(
        val bitmap: Bitmap,
        val wantsObscureVeil: Boolean,
    ) {
        /** Desaturation exists to mute the real room, so it follows the veil, not the plate. */
        val wantsDesaturation: Boolean get() = wantsObscureVeil
    }

    private fun makeBackgroundPlate(
        input: Bitmap,
        dstW: Int,
        dstH: Int,
        rotationDegrees: Int,
    ): BackgroundPlate? {
        val oriented = orientedReplacement(dstW, dstH, rotationDegrees)
        if (oriented != null) {
            return BackgroundPlate(oriented, wantsObscureVeil = false)
        }
        val blurred = makeBlurredBackgroundPlate(input) ?: return null
        return BackgroundPlate(blurred, wantsObscureVeil = true)
    }

    /**
     * Fits the replacement into the buffer so it reads upright *after* the renderer applies
     * `rotationDegrees`.
     *
     * The capture buffer is landscape even when the phone is portrait; the frame carries the
     * rotation and the renderer applies it downstream. Camera pixels are authored in that rotated
     * space, so they come out right, but a still image is authored the way the user saw it in the
     * picker. Cover-fitting it to the raw buffer therefore hands the renderer an upright image and
     * gets a sideways one back. Fitting in display space and pre-rotating by the inverse cancels
     * out. Aspect is preserved by cover-cropping — the image never stretches to the frame.
     */
    private fun orientedReplacement(dstW: Int, dstH: Int, rotationDegrees: Int): Bitmap? {
        val rotation = ((rotationDegrees % 360) + 360) % 360
        synchronized(replacementLock) {
            val source = replacementBackgroundBitmap
            if (source == null || source.isRecycled) {
                return null
            }
            val cached = orientedReplacementBitmap
            if (cached != null && !cached.isRecycled &&
                orientedReplacementWidth == dstW &&
                orientedReplacementHeight == dstH &&
                orientedReplacementRotation == rotation
            ) {
                return cached
            }

            // Quarter turns swap which buffer axis the viewer perceives as width.
            val quarterTurned = rotation == 90 || rotation == 270
            val displayW = if (quarterTurned) dstH else dstW
            val displayH = if (quarterTurned) dstW else dstH
            val covered = scaleBitmapCover(source, displayW, displayH) ?: return null
            val result = if (rotation == 0) {
                covered
            } else {
                val matrix = Matrix().apply { postRotate(-rotation.toFloat()) }
                val rotated = Bitmap.createBitmap(
                    covered, 0, 0, covered.width, covered.height, matrix, true,
                )
                if (rotated !== covered) covered.recycle()
                rotated
            }

            invalidateOrientedReplacementLocked()
            orientedReplacementBitmap = result
            orientedReplacementWidth = dstW
            orientedReplacementHeight = dstH
            orientedReplacementRotation = rotation
            return result
        }
    }

    /** Null when the cover-scaled copy cannot be allocated; the caller falls back to blur. */
    private fun scaleBitmapCover(source: Bitmap, dstW: Int, dstH: Int): Bitmap? {
        val srcW = source.width
        val srcH = source.height
        if (srcW <= 0 || srcH <= 0) {
            return Bitmap.createBitmap(dstW, dstH, Bitmap.Config.ARGB_8888)
        }
        val scale = maxOf(dstW.toFloat() / srcW, dstH.toFloat() / srcH)
        val scaledW = (srcW * scale).toInt().coerceAtLeast(1)
        val scaledH = (srcH * scale).toInt().coerceAtLeast(1)
        val scaled = Bitmap.createScaledBitmap(source, scaledW, scaledH, true)
        val x = ((scaledW - dstW) / 2).coerceAtLeast(0)
        val y = ((scaledH - dstH) / 2).coerceAtLeast(0)
        val cropW = dstW.coerceAtMost(scaledW)
        val cropH = dstH.coerceAtMost(scaledH)
        val cropped = Bitmap.createBitmap(scaled, x, y, cropW, cropH)
        if (scaled !== cropped && scaled !== source) {
            scaled.recycle()
        }
        // Both createScaledBitmap and createBitmap hand back the source itself when the requested
        // subset already matches it, so an image that happens to be exactly the processing size
        // would alias the cached replacement — which the caller then recycles, permanently
        // dropping the user's background. Hand back a copy the caller can own.
        //
        // Failing the copy must not fall back to the source: that is the alias this guard exists
        // to prevent, and it ends in the render thread drawing a bitmap the platform thread has
        // already recycled. Report failure and let the caller use the blurred plate instead.
        if (cropped === source) {
            return source.copy(source.config ?: Bitmap.Config.ARGB_8888, /* isMutable = */ false)
        }
        return cropped
    }

    /**
     * Blurred camera plate when no replacement image is set, at [BACKGROUND_BLUR_DOWNSAMPLE] of the
     * frame size. The compositing draw scales it up as it fills the output, so producing a
     * frame-sized copy here would be an allocation and a resample for pixels that get resampled
     * again immediately.
     *
     * Every box-blur pass runs at the downsampled size, with a single scale down around the whole
     * set. The previous shape called a self-contained downscale/blur/upscale helper
     * [BACKGROUND_BLUR_PASSES] times, so each extra pass upscaled to full frame resolution only for
     * the next one to immediately throw that away.
     *
     * Desaturation moved out to a colour filter on the compositing draw; doing it here meant a
     * full-resolution `getPixels`/`setPixels` round trip on top.
     */
    private fun makeBlurredBackgroundPlate(input: Bitmap): Bitmap? {
        val w = input.width
        val h = input.height
        val dsW = (w * BACKGROUND_BLUR_DOWNSAMPLE).toInt().coerceAtLeast(8)
        val dsH = (h * BACKGROUND_BLUR_DOWNSAMPLE).toInt().coerceAtLeast(8)

        val downscaled = ensureBlurDownscaleBitmap(dsW, dsH) ?: return null
        val downscaleCanvas = blurDownscaleCanvas ?: return null
        blurDownscaleRect.set(0, 0, dsW, dsH)
        downscaleCanvas.drawBitmap(input, null, blurDownscaleRect, plateDownscalePaint)

        val needed = dsW * dsH
        val pixels = blurPixelsScratch?.takeIf { it.size == needed }
            ?: IntArray(needed).also { blurPixelsScratch = it }
        val tmp = blurTmpScratch?.takeIf { it.size == needed }
            ?: IntArray(needed).also { blurTmpScratch = it }

        downscaled.getPixels(pixels, 0, dsW, 0, 0, dsW, dsH)
        val radius = backgroundBlurRadius()
        repeat(BACKGROUND_BLUR_PASSES * BOX_BLUR_PASSES_PER_ROUND) {
            boxBlurPixelsInPlace(pixels, tmp, dsW, dsH, radius)
        }
        downscaled.setPixels(pixels, 0, dsW, 0, 0, dsW, dsH)
        return downscaled
    }

    private fun ensureBlurDownscaleBitmap(dsW: Int, dsH: Int): Bitmap? {
        blurDownscaleBitmap
            ?.takeIf { !it.isRecycled && it.width == dsW && it.height == dsH }
            ?.let { return it }
        blurDownscaleBitmap?.recycle()
        blurDownscaleCanvas = null
        return try {
            Bitmap.createBitmap(dsW, dsH, Bitmap.Config.ARGB_8888).also {
                blurDownscaleBitmap = it
                blurDownscaleCanvas = Canvas(it)
            }
        } catch (e: OutOfMemoryError) {
            Log.w(TAG, "makeBlurredBackgroundPlate: OOM allocating ${dsW}x$dsH plate", e)
            blurDownscaleBitmap = null
            null
        }
    }

    /**
     * In-place box blur on a packed ARGB pixel array. Two-pass separable: horizontal then
     * vertical, both using a sliding accumulator so the cost is `O(width × height)` regardless
     * of radius.
     */
    private fun boxBlurPixelsInPlace(pixels: IntArray, tmp: IntArray, w: Int, h: Int, radius: Int) {
        if (radius < 1) return
        val div = (radius * 2 + 1)
        // Horizontal.
        var y = 0
        while (y < h) {
            val rowOffset = y * w
            var rSum = 0
            var gSum = 0
            var bSum = 0
            for (k in -radius..radius) {
                val xx = k.coerceIn(0, w - 1)
                val px = pixels[rowOffset + xx]
                rSum += (px ushr 16) and 0xFF
                gSum += (px ushr 8) and 0xFF
                bSum += px and 0xFF
            }
            var x = 0
            while (x < w) {
                tmp[rowOffset + x] = 0xFF.shl(24) or
                    ((rSum / div) shl 16) or
                    ((gSum / div) shl 8) or
                    (bSum / div)
                val xOut = (x - radius).coerceIn(0, w - 1)
                val xIn = (x + radius + 1).coerceIn(0, w - 1)
                val pxOut = pixels[rowOffset + xOut]
                val pxIn = pixels[rowOffset + xIn]
                rSum += ((pxIn ushr 16) and 0xFF) - ((pxOut ushr 16) and 0xFF)
                gSum += ((pxIn ushr 8) and 0xFF) - ((pxOut ushr 8) and 0xFF)
                bSum += (pxIn and 0xFF) - (pxOut and 0xFF)
                x++
            }
            y++
        }
        // Vertical.
        var x = 0
        while (x < w) {
            var rSum = 0
            var gSum = 0
            var bSum = 0
            for (k in -radius..radius) {
                val yy = k.coerceIn(0, h - 1)
                val px = tmp[yy * w + x]
                rSum += (px ushr 16) and 0xFF
                gSum += (px ushr 8) and 0xFF
                bSum += px and 0xFF
            }
            var yy = 0
            while (yy < h) {
                pixels[yy * w + x] = 0xFF.shl(24) or
                    ((rSum / div) shl 16) or
                    ((gSum / div) shl 8) or
                    (bSum / div)
                val yOut = (yy - radius).coerceIn(0, h - 1)
                val yIn = (yy + radius + 1).coerceIn(0, h - 1)
                val pxOut = tmp[yOut * w + x]
                val pxIn = tmp[yIn * w + x]
                rSum += ((pxIn ushr 16) and 0xFF) - ((pxOut ushr 16) and 0xFF)
                gSum += ((pxIn ushr 8) and 0xFF) - ((pxOut ushr 8) and 0xFF)
                bSum += (pxIn and 0xFF) - (pxOut and 0xFF)
                yy++
            }
            x++
        }
    }

    // MARK: - VideoFrame ↔ Bitmap.

    /**
     * Pulls an ARGB Bitmap out of a `VideoFrame`. If the frame's long side is larger than
     * [capLongSide], we use `Buffer.cropAndScale` (texture-accelerated when the source is a
     * texture buffer) to downscale first, so the slow CPU YUV→ARGB conversion only ever runs at
     * the capped size.
     */
    private fun frameToBitmap(frame: VideoFrame, capLongSide: Int): Bitmap? {
        val srcBuf = frame.buffer
        val srcW = srcBuf.width
        val srcH = srcBuf.height
        if (srcW <= 0 || srcH <= 0) return null

        val (targetW, targetH) = computeTargetSize(srcW, srcH, capLongSide)
        val scaledBuf = if (targetW == srcW && targetH == srcH) {
            srcBuf.also { it.retain() }
        } else {
            // cropAndScale takes ownership of the returned buffer; release after toI420.
            srcBuf.cropAndScale(0, 0, srcW, srcH, targetW, targetH)
        }

        val i420 = try {
            scaledBuf.toI420()
        } catch (e: Throwable) {
            Log.w(TAG, "toI420 failed", e)
            scaledBuf.release()
            return null
        }
        scaledBuf.release()
        if (i420 == null) return null

        return try {
            i420ToBitmap(i420)
        } finally {
            i420.release()
        }
    }

    private fun computeTargetSize(w: Int, h: Int, cap: Int): Pair<Int, Int> {
        if (cap <= 0) return w to h
        val longSide = maxOf(w, h)
        if (longSide <= cap) return w to h
        val s = cap.toFloat() / longSide.toFloat()
        // Round to even — encoders generally prefer even dimensions.
        val tw = ((w * s).toInt() / 2) * 2
        val th = ((h * s).toInt() / 2) * 2
        return tw.coerceAtLeast(2) to th.coerceAtLeast(2)
    }

    /**
     * I420 → ARGB Bitmap via BT.601 limited-range matrix. Camera frames from WebRTC are
     * captured in BT.601 video range, so the matrix below matches what the iOS side uses
     * (`CGColorSpace.itur_709` is close enough for our purposes — both are limited range).
     */
    private fun i420ToBitmap(i420: VideoFrame.I420Buffer): Bitmap {
        val w = i420.width
        val h = i420.height
        val yStride = i420.strideY
        val uStride = i420.strideU
        val vStride = i420.strideV
        val chromaH = (h + 1) / 2

        // Pull the planes across in three memcpys. Addressing the direct buffers per sample cost
        // ~2.8 M bounds-checked JNI-backed reads a frame at 720p, which dwarfed the arithmetic.
        val yArr = copyPlane(i420.dataY, i420YScratch, h * yStride).also { i420YScratch = it }
        val uArr = copyPlane(i420.dataU, i420UScratch, chromaH * uStride).also { i420UScratch = it }
        val vArr = copyPlane(i420.dataV, i420VScratch, chromaH * vStride).also { i420VScratch = it }

        val needed = w * h
        val pixels = i420ArgbScratch?.takeIf { it.size == needed } ?: IntArray(needed).also {
            i420ArgbScratch = it
        }
        // Walk 2×2 blocks: the four luma samples in a block share one chroma pair, so this loads
        // and converts chroma once instead of four times.
        var y = 0
        while (y < h) {
            val hasRow1 = y + 1 < h
            val yRow0 = y * yStride
            val yRow1 = yRow0 + yStride
            val uRow = (y shr 1) * uStride
            val vRow = (y shr 1) * vStride
            val outRow0 = y * w
            val outRow1 = outRow0 + w
            var x = 0
            while (x < w) {
                val c = x shr 1
                val uv = (uArr[uRow + c].toInt() and 0xFF) - 128
                val vv = (vArr[vRow + c].toInt() and 0xFF) - 128
                val rBias = 409 * vv + 128
                val gBias = -100 * uv - 208 * vv + 128
                val bBias = 516 * uv + 128
                val hasCol1 = x + 1 < w

                pixels[outRow0 + x] = argbFromLuma(yArr[yRow0 + x], rBias, gBias, bBias)
                if (hasCol1) {
                    pixels[outRow0 + x + 1] = argbFromLuma(yArr[yRow0 + x + 1], rBias, gBias, bBias)
                }
                if (hasRow1) {
                    pixels[outRow1 + x] = argbFromLuma(yArr[yRow1 + x], rBias, gBias, bBias)
                    if (hasCol1) {
                        pixels[outRow1 + x + 1] =
                            argbFromLuma(yArr[yRow1 + x + 1], rBias, gBias, bBias)
                    }
                }
                x += 2
            }
            y += 2
        }
        val bitmap = ensureArgbBitmap(w, h)
        bitmap.setPixels(pixels, 0, w, 0, 0, w, h)
        return bitmap
    }

    /** One luma sample plus the block's pre-multiplied chroma terms → opaque packed ARGB. */
    private fun argbFromLuma(luma: Byte, rBias: Int, gBias: Int, bBias: Int): Int {
        val c298 = 298 * ((luma.toInt() and 0xFF) - 16)
        val r = (c298 + rBias) shr 8
        val g = (c298 + gBias) shr 8
        val b = (c298 + bBias) shr 8
        return 0xFF.shl(24) or
            (r.coerceIn(0, 255) shl 16) or
            (g.coerceIn(0, 255) shl 8) or
            b.coerceIn(0, 255)
    }

    /**
     * Bulk-copies a plane into a reusable array, addressing it from index 0 like the per-sample
     * reads it replaces.
     *
     * [size] is the stride-derived upper bound, so it overshoots the readable bytes by the last
     * row's padding; the `remaining` guard keeps that from throwing and nothing reads the padding.
     */
    private fun copyPlane(buffer: ByteBuffer, cached: ByteArray?, size: Int): ByteArray {
        val out = cached?.takeIf { it.size >= size } ?: ByteArray(size)
        val view = buffer.duplicate()
        view.position(0)
        val available = minOf(size, view.remaining())
        view.get(out, 0, available)
        return out
    }

    private fun ensureArgbBitmap(width: Int, height: Int): Bitmap {
        if (pooledArgbBitmap == null ||
            pooledArgbBitmapW != width ||
            pooledArgbBitmapH != height
        ) {
            pooledArgbBitmap?.recycle()
            pooledArgbBitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            pooledArgbBitmapW = width
            pooledArgbBitmapH = height
        }
        return pooledArgbBitmap!!
    }

    private fun ensureComposedBitmap(width: Int, height: Int): Bitmap {
        if (pooledComposedBitmap == null ||
            pooledComposedBitmapW != width ||
            pooledComposedBitmapH != height
        ) {
            pooledComposedBitmap?.recycle()
            pooledComposedBitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            pooledComposedCanvas = Canvas(pooledComposedBitmap!!)
            pooledComposedBitmapW = width
            pooledComposedBitmapH = height
        }
        return pooledComposedBitmap!!
    }

    /** Pooled stand-in for `Canvas.saveLayer`; see [pooledForegroundBitmap]. */
    private fun ensureForegroundBitmap(width: Int, height: Int): Bitmap? {
        pooledForegroundBitmap
            ?.takeIf { !it.isRecycled && it.width == width && it.height == height }
            ?.let { return it }
        pooledForegroundBitmap?.recycle()
        pooledForegroundCanvas = null
        return try {
            Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888).also {
                pooledForegroundBitmap = it
                pooledForegroundCanvas = Canvas(it)
            }
        } catch (e: OutOfMemoryError) {
            Log.w(TAG, "ensureForegroundBitmap: OOM allocating ${width}x$height layer", e)
            pooledForegroundBitmap = null
            null
        }
    }

    /**
     * Returns a reused `JavaI420Buffer` sized for [bitmap] (even dimensions). The buffer's Y/U/V
     * planes are overwritten each call — this is the closest Android equivalent to editing the
     * camera buffer in place (camera frames arrive as `TextureBufferImpl`, which is not CPU-writable).
     */
    private fun ensurePooledOutputI420(bitmapWidth: Int, bitmapHeight: Int): JavaI420Buffer? {
        val ew = (bitmapWidth / 2) * 2
        val eh = (bitmapHeight / 2) * 2
        if (ew <= 0 || eh <= 0) return null
        val existing = pooledOutputI420
        if (existing != null && existing.width == ew && existing.height == eh) {
            return existing
        }
        try {
            existing?.release()
        } catch (_: Throwable) {
            // ignore
        }
        pooledOutputI420 = JavaI420Buffer.allocate(ew, eh)
        return pooledOutputI420
    }

    /**
     * Writes [bitmap] ARGB pixels into [target] I420 planes and wraps it in a `VideoFrame`.
     * WebRTC releases the returned frame after encode; [pooledOutputI420] stays allocated.
     */
    private fun writeBitmapIntoPooledI420(bitmap: Bitmap, src: VideoFrame): VideoFrame {
        val buffer = ensurePooledOutputI420(bitmap.width, bitmap.height)
            ?: return src
        packArgbBitmapIntoI420(bitmap, buffer)
        return VideoFrame(buffer, src.rotation, src.timestampNs)
    }

    /** BT.601 limited-range ARGB → I420, matching [i420ToBitmap]. */
    private fun packArgbBitmapIntoI420(bitmap: Bitmap, buffer: JavaI420Buffer) {
        val ew = buffer.width
        val eh = buffer.height
        val needed = ew * eh
        val pixels = bitmapToI420Scratch?.takeIf { it.size == needed } ?: IntArray(needed).also {
            bitmapToI420Scratch = it
        }
        bitmap.getPixels(pixels, 0, ew, 0, 0, ew, eh)

        val yStride = buffer.strideY
        val uStride = buffer.strideU
        val vStride = buffer.strideV
        val chromaH = eh / 2

        // Build the planes in arrays and hand each over in one bulk write. This used to be two
        // separate passes over `pixels` writing the direct buffers a sample at a time — the frame
        // was walked twice for no reason, and every sample paid a bounds-checked buffer write.
        val yArr = ensurePlaneScratch(i420YScratch, eh * yStride).also { i420YScratch = it }
        val uArr = ensurePlaneScratch(i420UScratch, chromaH * uStride).also { i420UScratch = it }
        val vArr = ensurePlaneScratch(i420VScratch, chromaH * vStride).also { i420VScratch = it }

        var y = 0
        while (y < eh) {
            val row0 = y * ew
            val row1 = row0 + ew
            val yOut0 = y * yStride
            val yOut1 = yOut0 + yStride
            val uOut = (y shr 1) * uStride
            val vOut = (y shr 1) * vStride
            var x = 0
            while (x < ew) {
                val p00 = pixels[row0 + x]
                val p01 = pixels[row0 + x + 1]
                val p10 = pixels[row1 + x]
                val p11 = pixels[row1 + x + 1]

                yArr[yOut0 + x] = lumaOf(p00)
                yArr[yOut0 + x + 1] = lumaOf(p01)
                yArr[yOut1 + x] = lumaOf(p10)
                yArr[yOut1 + x + 1] = lumaOf(p11)

                // Chroma from the top-left sample of the block, matching the previous behaviour.
                val r = (p00 ushr 16) and 0xFF
                val g = (p00 ushr 8) and 0xFF
                val b = p00 and 0xFF
                val c = x shr 1
                uArr[uOut + c] = (((-38 * r - 74 * g + 112 * b + 128) shr 8) + 128)
                    .coerceIn(0, 255).toByte()
                vArr[vOut + c] = (((112 * r - 94 * g - 18 * b + 128) shr 8) + 128)
                    .coerceIn(0, 255).toByte()
                x += 2
            }
            y += 2
        }

        writePlane(buffer.dataY, yArr, eh * yStride)
        writePlane(buffer.dataU, uArr, chromaH * uStride)
        writePlane(buffer.dataV, vArr, chromaH * vStride)
    }

    /** BT.601 limited-range luma from a packed ARGB pixel. */
    private fun lumaOf(px: Int): Byte {
        val r = (px ushr 16) and 0xFF
        val g = (px ushr 8) and 0xFF
        val b = px and 0xFF
        return (((66 * r + 129 * g + 25 * b + 128) shr 8) + 16).coerceIn(0, 255).toByte()
    }

    private fun ensurePlaneScratch(cached: ByteArray?, size: Int): ByteArray =
        cached?.takeIf { it.size >= size } ?: ByteArray(size)

    private fun writePlane(buffer: ByteBuffer, plane: ByteArray, size: Int) {
        val view = buffer.duplicate()
        view.position(0)
        view.put(plane, 0, minOf(size, view.remaining()))
    }
}
