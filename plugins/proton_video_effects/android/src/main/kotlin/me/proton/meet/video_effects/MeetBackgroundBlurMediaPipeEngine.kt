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
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.util.Log
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
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.Callable
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.Locale

/**
 * MediaPipe selfie segmenter (single-class or multiclass) + bitmap-based background blur.
 *
 * Direct port of `MeetBackgroundBlurMediaPipeEngine.swift`. The high-level pipeline matches the
 * iOS engine exactly — see the Swift file for the design rationale on **confidence masks**, the
 * **single-slot in-flight gate**, the **mask snapshot** copy strategy, and the input/background
 * swap trick for the multiclass model.
 *
 * Pipeline:
 *   1. **Asynchronous** segmentation — inference runs off the WebRTC video processing thread.
 *      The active backend is selected at construction time:
 *      * **Raw TFLite GPU** first. This loads the bundled `.tflite` model directly through
 *        `Interpreter + GpuDelegate` and reads the output tensor bytes, bypassing MediaPipe
 *        Tasks's GPU result-conversion layer.
 *      * **MediaPipe Tasks CPU** fallback. This remains the known-good path when TFLite GPU
 *        delegate compilation, probe inference, or runtime execution fails.
 *   2. The raw TFLite GPU path exists because MediaPipe Tasks Vision 0.10.35 crashes on Android
 *      GPU output conversion: `ImageSegmenter.convertToTaskResult` calls `PacketGetter
 *      .getImageWidth(...)` / `...FromImageList(...)` on a GPU-produced `Image`; on Adreno 7xx/8xx
 *      devices that `Image` can have `ImageFrame::format() == UNKNOWN`, which trips an
 *      uncatchable native `CHECK` in `image_frame.cc:109/298` and aborts the process. Raw TFLite
 *      avoids that `Image → ImageFrame` JNI boundary entirely.
 *   3. Each frame composites a downscaled box-blurred background + sharp foreground using a
 *      `Canvas` + `PorterDuff.Mode.SRC_IN` mask blend.
 *
 * Mask interpretation (CPU path only) depends on the model:
 *   * Single-class `selfie_segmenter`: `confidenceMasks[0]` is the **foreground** probability.
 *   * Multiclass `selfie_multiclass_256x256`: `confidenceMasks[0]` is the **background**
 *     probability — we invert it once when copying out of MediaPipe's transient buffer so the
 *     cached snapshot is always "high alpha where person", regardless of model. Since the per-
 *     class confidences sum to 1, `1 − mask[0]` is exactly `Σ mask[1..5]` (soft foreground).
 *
 * The category-mask code path ([makeForegroundSnapshotFromCategory], [usesCategoryMaskOutput],
 * the `setOutputCategoryMask` branch in [createSegmenter]) is kept only for a future MediaPipe
 * Tasks version where GPU output conversion is fixed. The active GPU path today is raw TFLite
 * tensor output, not MediaPipe category masks.
 *
 * **Platform differences vs. iOS:**
 *   * No `CVPixelBuffer` equivalent for in-place mutation: we round-trip through `Bitmap` and
 *     return a fresh `VideoFrame` rather than modifying the camera buffer.
 *   * No Core Image. Background blur is a downscale → box-blur (3 passes ≈ Gaussian) → upscale
 *     pass; mask compositing is a `Canvas` layer with `PorterDuff.Mode.SRC_IN`. This is the
 *     closest equivalent to `CIBlendWithMask` that works on a pure CPU Bitmap (Android's only
 *     hardware-accelerated blur, `RenderEffect`, can't render *into* a `Bitmap`).
 *   * Frame size is controlled by [PROCESSING_LONG_SIDE]: set `<= 0` to keep original camera
 *     resolution, or set a positive cap to downscale first via `Buffer.cropAndScale` (GPU-
 *     accelerated for texture-backed camera buffers).
 *
 * Threading model:
 *   * `process(...)` runs on the WebRTC video-source thread.
 *   * MediaPipe's result listener runs on a MediaPipe-owned worker thread.
 *   * `maskLock` serialises every read/write of [currentMask] and [inferenceInFlight].
 */
internal class MeetBackgroundBlurMediaPipeEngine(
    private val context: Context,
) {
    companion object {
        private const val TAG = "MeetBgBlur"

        private const val MULTICLASS_MODEL_ASSET = "selfie_multiclass_256x256.tflite"
        private const val SINGLECLASS_MODEL_ASSET = "selfie_segmenter.tflite"

        /** Both supported MediaPipe selfie models take a 256×256 input. */
        private const val SEGMENTER_INPUT_SIZE = 256

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
        private const val BACKGROUND_BLUR_DOWNSAMPLE = 0.25f

        /**
         * Radius for the (downscaled) box-blur. Three passes of box-blur with this radius
         * approximate a Gaussian with σ ≈ radius × √(N/3) ≈ radius (for N=3 passes).
         */
        private const val BACKGROUND_BLUR_RADIUS = 8

        /**
         * σ for the mask feather, run on the 256² mask before upscale. After upscale to the
         * processing resolution this turns into a `σ × upscaleFactor` pixel-wide soft edge.
         *
         * Two values:
         *   * [MASK_FEATHER_SIGMA_CONFIDENCE] — small (1.5). The mask is already a continuous
         *     probability so most of the smoothness comes from the source. Larger values would
         *     bleed the subject silhouette outward.
         *   * [MASK_FEATHER_SIGMA_CATEGORY] — larger (3.0). The mask is hard binary 0/255 from
         *     the argmax category output, so we need a wider Gaussian to recover an edge that
         *     looks comparable to the confidence-mask path after upscale.
         */
        private const val MASK_FEATHER_SIGMA_CONFIDENCE = 1.5f
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
    )

    private enum class SegmenterBackendKind {
        TFLITE_GPU,
        MEDIAPIPE_CPU,
    }

    private data class SegmenterAttempt(
        val modelAsset: String,
        val isMulticlass: Boolean,
        val backend: SegmenterBackendKind,
    )

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

    /** `true` when the active segmenter was configured with `setOutputCategoryMask(true)` rather
     *  than `setOutputConfidenceMasks(true)`. Drives both the result-listener decoding path
     *  ([onSegmenterResult]) and the feather σ ([composeWithMask]). Set together with [segmenter]
     *  in [setupSegmenter] under the same try block so it can never refer to a different
     *  segmenter than the one we're actually using. */
    @Volatile
    private var usesCategoryMaskOutput: Boolean = false

    private val maskLock = Any()
    private var currentMask: MaskSnapshot? = null

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
    /** Reused ARGB scratch for Bitmap → I420 conversion to avoid per-frame large IntArray churn. */
    private var bitmapToI420Scratch: IntArray? = null
    /** Reused downscaled blur scratch (pixels + tmp) to reduce repeated allocations. */
    private var blurPixelsScratch: IntArray? = null
    private var blurTmpScratch: IntArray? = null
    /** Reused ARGB scratch for packing the 256² alpha mask before upscale. */
    private var maskSrcArgbScratch: IntArray? = null
    /** Reused separable feather passes on the 256² mask (two × 64 KiB, not worth reallocating). */
    private var featherPass1Scratch: ByteArray? = null
    private var featherOutScratch: ByteArray? = null
    /** Mutable ARGB bitmap reused for I420→ARGB import (camera frames are TextureBuffer, not in-place). */
    private var pooledArgbBitmap: Bitmap? = null
    private var pooledArgbBitmapW: Int = 0
    private var pooledArgbBitmapH: Int = 0
    /** Mutable ARGB bitmap reused for compositing output before packing into I420. */
    private var pooledComposedBitmap: Bitmap? = null
    private var pooledComposedBitmapW: Int = 0
    private var pooledComposedBitmapH: Int = 0
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
                        modelBuffer = loadModelBuffer(attempt.modelAsset),
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
    private fun buildSegmenterAttemptChain(): List<SegmenterAttempt> {
        val assets = try {
            context.assets.list("")?.toSet().orEmpty()
        } catch (_: Throwable) {
            emptySet()
        }
        val hasMulticlass = MULTICLASS_MODEL_ASSET in assets
        val hasSingleclass = SINGLECLASS_MODEL_ASSET in assets
        val chain = mutableListOf<SegmenterAttempt>()
        if (hasSingleclass) {
            chain += SegmenterAttempt(SINGLECLASS_MODEL_ASSET, isMulticlass = false, SegmenterBackendKind.TFLITE_GPU)
        }
        if (hasMulticlass) {
            chain += SegmenterAttempt(MULTICLASS_MODEL_ASSET, isMulticlass = true, SegmenterBackendKind.TFLITE_GPU)
        }
        if (hasSingleclass) {
            chain += SegmenterAttempt(SINGLECLASS_MODEL_ASSET, isMulticlass = false, SegmenterBackendKind.MEDIAPIPE_CPU)
        }
        if (hasMulticlass) {
            chain += SegmenterAttempt(MULTICLASS_MODEL_ASSET, isMulticlass = true, SegmenterBackendKind.MEDIAPIPE_CPU)
        }
        return chain
    }

    private fun createSegmenter(
        modelAsset: String,
        delegate: Delegate,
        useCategoryMask: Boolean,
    ): ImageSegmenter {
        // Hand MediaPipe the model as a direct `ByteBuffer` rather than going through
        // `setModelAssetPath`. The path-based API uses `AssetManager.openFd()` + `mmap`, which
        // requires the asset to be both stored uncompressed AND 16-byte aligned inside the APK
        // for TFLite FlatBuffer parsing. AGP only guarantees 4-byte alignment for uncompressed
        // assets, so on some devices MediaPipe reads tensor metadata at slightly wrong offsets
        // and `Calculator::Open()` fails with the misleading
        //   "Batch size mismatch, expected 1 but got N values with divergent batch sizes"
        // pointing at internal U-Net feature tensors (e.g. [8, 4, 8, 512], [4, 4, 4, 768]).
        //
        // Direct `ByteBuffer`s are guaranteed aligned to 8 bytes by the JVM and to 16 bytes by
        // Android's `DirectByteBuffer` implementation (for SIMD), so this avoids the issue
        // entirely. The buffer is ~16 MB for the multiclass model — held by the segmenter for
        // its lifetime, freed in `release()`.
        val modelBuffer = loadModelBuffer(modelAsset)
        val base = BaseOptions.builder()
            .setModelAssetBuffer(modelBuffer)
            .setDelegate(delegate)
            .build()
        // Mask output type: today this is always confidence masks (`useCategoryMask=false`)
        // because [buildSegmenterAttemptChain] only emits CPU entries — see file header for the
        // GPU disablement context. The `useCategoryMask=true` branch is kept as documented dead
        // code so that re-adding `Delegate.GPU` to the chain (after a MediaPipe Tasks Vision
        // upgrade past 0.10.35) restores the workaround for the
        // `image_frame.cc Invalid format: UNKNOWN` CHECK-fail without further plumbing.
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

    /**
     * Read the bundled TFLite model fully into a direct, aligned `ByteBuffer`. Sized exactly to
     * the asset length so MediaPipe can consume it without re-allocating.
     */
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
     * Raw TFLite GPU backend for selfie segmentation.
     *
     * Why this exists: MediaPipe Tasks's `ImageSegmenter` GPU path successfully runs inference on
     * some Adreno devices, then crashes while converting the GPU-produced output `Image` back into
     * an `ImageFrame` (`image_frame.cc:109/298`, uncatchable native CHECK). Raw TFLite avoids that
     * layer entirely: it feeds the `.tflite` model directly and reads the output tensor bytes.
     *
     * GPU delegate thread-affinity is strict: create, run, and close all happen on [executor].
     */
    private class TfliteGpuSegmenterBackend(
        private val modelAsset: String,
        private val isMulticlassModel: Boolean,
        private val modelBuffer: ByteBuffer,
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
        private var outputWidth: Int = SEGMENTER_INPUT_SIZE
        private var outputHeight: Int = SEGMENTER_INPUT_SIZE
        private var outputChannels: Int = 1
        private var inputDataType: DataType = DataType.FLOAT32
        private var outputDataType: DataType = DataType.FLOAT32
        private var inputScale: Float = 1f
        private var inputZeroPoint: Int = 0
        private var outputScale: Float = 1f
        private var outputZeroPoint: Int = 0
        private var pixelScratch: IntArray? = null
        @Volatile
        private var isClosed: Boolean = false

        init {
            val future = executor.submit(Callable {
                initialiseOnGpuThread()
                // Probe one empty frame so delegate compilation and output tensor reads fail here,
                // where setupSegmenter can fall through to MediaPipe CPU, rather than on the first
                // camera frame.
                runOnGpuThread(IntArray(SEGMENTER_INPUT_SIZE * SEGMENTER_INPUT_SIZE))
            })
            try {
                future.get(TFLITE_GPU_INIT_TIMEOUT_MS, TimeUnit.MILLISECONDS)
            } catch (error: Throwable) {
                future.cancel(true)
                close()
                throw IllegalStateException("TFLite GPU backend init failed for $modelAsset", error)
            }
        }

        fun segmentAsync(
            srcBitmap: Bitmap,
            onResult: (MaskSnapshot?) -> Unit,
            onError: (Throwable) -> Unit,
        ) {
            if (isClosed) {
                srcBitmap.recycle()
                onError(IllegalStateException("TFLite backend is closed"))
                return
            }

            val pixels = try {
                val needed = srcBitmap.width * srcBitmap.height
                val scratch = pixelScratch?.takeIf { it.size == needed } ?: IntArray(needed).also {
                    pixelScratch = it
                }
                srcBitmap.getPixels(scratch, 0, srcBitmap.width, 0, 0, srcBitmap.width, srcBitmap.height)
                scratch
            } catch (error: Throwable) {
                srcBitmap.recycle()
                onError(error)
                return
            } finally {
                if (!srcBitmap.isRecycled) srcBitmap.recycle()
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
            val delegateOptions = GpuDelegate.Options().apply {
                // Prefer throughput/latency over exact FP32 parity for a segmentation mask. The
                // mask is already feathered and upscaled in compositing, so FP16 precision loss is
                // visually negligible but can materially reduce GPU inference time on Adreno.
                setPrecisionLossAllowed(true)
                // Explicit low-latency mode since this is real-time per-frame inference.
                setInferencePreference(GpuDelegate.Options.INFERENCE_PREFERENCE_FAST_SINGLE_ANSWER)
                // No-op for FLOAT models, but enables delegate support for quantized paths where
                // available. Keeps one backend binary for both model families.
                setQuantizedModelsAllowed(true)
            }
            val delegate = GpuDelegate(delegateOptions)
            val options = Interpreter.Options()
                .addDelegate(delegate)
                .setNumThreads(1)
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
            require(inputShape[1] == SEGMENTER_INPUT_SIZE && inputShape[2] == SEGMENTER_INPUT_SIZE) {
                "Unsupported input size=${inputShape.joinToString(prefix = "[", postfix = "]")}"
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
                    SEGMENTER_INPUT_SIZE * SEGMENTER_INPUT_SIZE * 3 *
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
                    if (shape[1] == SEGMENTER_INPUT_SIZE && shape[2] == SEGMENTER_INPUT_SIZE) {
                        outputLayout = OutputLayout.NHWC
                        outputHeight = shape[1]
                        outputWidth = shape[2]
                        outputChannels = shape[3]
                    } else if (shape[2] == SEGMENTER_INPUT_SIZE && shape[3] == SEGMENTER_INPUT_SIZE) {
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

            require(pixels.size == SEGMENTER_INPUT_SIZE * SEGMENTER_INPUT_SIZE) {
                "Unexpected input pixels=${pixels.size}"
            }
            input.rewind()
            var i = 0
            while (i < pixels.size) {
                val px = pixels[i]
                val r = ((px ushr 16) and 0xFF) / 255f
                val g = ((px ushr 8) and 0xFF) / 255f
                val b = (px and 0xFF) / 255f
                if (inputDataType == DataType.FLOAT32) {
                    input.putFloat(r)
                    input.putFloat(g)
                    input.putFloat(b)
                } else {
                    input.put(quantizeToUint8(r, inputScale, inputZeroPoint).toByte())
                    input.put(quantizeToUint8(g, inputScale, inputZeroPoint).toByte())
                    input.put(quantizeToUint8(b, inputScale, inputZeroPoint).toByte())
                }
                i++
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
        Log.i(TAG, "release: draining inference before closing segmenter")
        // Pull the backend out *before* dropping our reference so process() starts returning raw
        // frames the moment release() begins.
        val toClose = segmenter
        val tfliteToClose = tfliteBackend
        segmenter = null
        tfliteBackend = null

        // Wait briefly for any in-flight inference to drain. Both backends run native work off the
        // WebRTC thread; closing either one while a forward pass is running can crash or deadlock.
        // We poll the in-flight flag (set by `process` / `dispatchAsyncSegmentation`, cleared by
        // result callbacks) with a hard cap so detach never blocks indefinitely on a hung backend.
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
        bitmapToI420Scratch = null
        blurPixelsScratch = null
        blurTmpScratch = null
        maskSrcArgbScratch = null
        featherPass1Scratch = null
        featherOutScratch = null
        pooledArgbBitmap?.recycle()
        pooledArgbBitmap = null
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
        // Snapshot the backend ref ONCE per call. `release()` swaps refs to null then waits to
        // drain in-flight inference; reading once here means a concurrent release won't have us
        // dispatching to a half-closed backend mid-method.
        val tflite = tfliteBackend
        val seg = segmenter
        if (tflite == null && seg == null) return frame
        val frameId = ++processFrameCount
        val shouldStageLog = frameId == 1L || frameId % STAGE_LOG_EVERY_NTH_FRAME == 0L

        // Stage 0: gate. Decide whether to start a new inference. We dispatch only if the previous
        // one has already completed — this gives the highest segmentation rate the device can
        // sustain (typically 15-30 Hz on modern GPUs) without stacking up frames in MediaPipe's
        // queue, which is what causes mask lag when the user moves quickly.
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

        // Stage 1: WebRTC VideoFrame → ARGB Bitmap at processing resolution. If
        // PROCESSING_LONG_SIDE <= 0 we preserve original frame resolution; otherwise we downscale
        // via texture-accelerated `cropAndScale` before the CPU I420 → ARGB conversion.
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
                    "snapshot=${snapshot?.let { "${it.width}x${it.height}" } ?: "null"} " +
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
                dispatchAsyncSegmentation(tflite, seg, inputBitmap)
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
            composeWithMask(inputBitmap, snapshot)
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
     * Hands the current frame to the active async segmentation backend. Returns immediately; the
     * result is delivered later via the backend listener/callback. Caller must have already set
     * `inferenceInFlight = true`. Failure paths clear the flag again so the pipeline never gets
     * stuck with no in-flight inference.
     */
    private fun dispatchAsyncSegmentation(
        tflite: TfliteGpuSegmenterBackend?,
        seg: ImageSegmenter?,
        srcBitmap: Bitmap,
    ) {
        try {
            // Pre-scale to 256×256 ourselves. Squashing aspect ratio is fine — the models are
            // trained on inputs already normalised to 256×256 and the mask is upscaled back to the
            // camera aspect ratio at compositing time, so the squash/unsquash cancels out.
            val scaled = Bitmap.createScaledBitmap(
                srcBitmap, SEGMENTER_INPUT_SIZE, SEGMENTER_INPUT_SIZE, /* filter = */ true,
            )
            // `createScaledBitmap` may return the source if dimensions already match. The active
            // backend owns and recycles `small`, while `process()` still owns `srcBitmap`, so make
            // the ownership boundary explicit.
            val small = if (scaled === srcBitmap) {
                scaled.copy(Bitmap.Config.ARGB_8888, /* isMutable = */ false)
            } else {
                scaled
            }
            if (small == null) {
                Log.w(TAG, "dispatchAsyncSegmentation: scaled.copy returned null")
                clearInferenceInFlight()
                return
            }
            segmentClockMs += 33L
            if (tflite != null) {
                tflite.segmentAsync(
                    small,
                    onResult = { snapshot -> completeInference(success = true, newSnapshot = snapshot) },
                    onError = { error ->
                        Log.w(TAG, "TFLite segmentAsync failed", error)
                        clearInferenceInFlight()
                    },
                )
            } else if (seg != null) {
                val mpImage = BitmapImageBuilder(small).build()
                synchronized(maskLock) {
                    // Defensive: there should be only one in-flight image due to inferenceInFlight
                    // gating, but if callbacks are delayed we still close any stale input here.
                    closePendingMpInputImageLocked()
                    pendingMpInputImage = mpImage
                }
                seg.segmentAsync(mpImage, segmentClockMs)
            } else {
                small.recycle()
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
            if (newSnapshot != null) currentMask = newSnapshot

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
     *   2. Upscale the feathered mask to compositing resolution as an alpha-only bitmap.
     *   3. Background blur — downscale, 3× box-blur, upscale.
     *   4. Composite via `Canvas` + `PorterDuff.SRC_IN`: keep the sharp `input` where the mask
     *      is foreground, fall back to `blurred` elsewhere.
     */
    private fun composeWithMask(input: Bitmap, snapshot: MaskSnapshot): Bitmap? {
        val w = input.width
        val h = input.height

        // Wider feather for the binary category-mask path so the upscale produces a soft edge
        // visually comparable to the confidence-mask path. See [MASK_FEATHER_SIGMA_*] docs.
        val featherSigma = if (usesCategoryMaskOutput) {
            MASK_FEATHER_SIGMA_CATEGORY
        } else {
            MASK_FEATHER_SIGMA_CONFIDENCE
        }
        val featheredAlpha = featherMask(snapshot, featherSigma)
        val maskBitmap = upscaleAlphaToBitmap(featheredAlpha, snapshot.width, snapshot.height, w, h)
            ?: return null

        val blurred = blurBackgroundBitmap(input)
            ?: return null

        val out = ensureComposedBitmap(w, h)
        val canvas = Canvas(out)

        // 1) Fill output with the blurred background.
        canvas.drawBitmap(blurred, 0f, 0f, null)

        // 2) Off-screen layer: draw the foreground-alpha mask, then composite the sharp `input`
        //    on top with SRC_IN so it survives only where the mask is opaque. Restoring the
        //    layer composites this masked foreground back over the blurred bg, completing the
        //    equivalent of iOS's `CIBlendWithMask(input=sharp, bg=blurred, mask=foreground)`.
        val sc = canvas.saveLayer(0f, 0f, w.toFloat(), h.toFloat(), null)
        canvas.drawBitmap(maskBitmap, 0f, 0f, null)
        val srcInPaint = Paint().apply {
            xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
            isAntiAlias = false
            isFilterBitmap = true
        }
        canvas.drawBitmap(input, 0f, 0f, srcInPaint)
        canvas.restoreToCount(sc)

        maskBitmap.recycle()
        blurred.recycle()
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
     * Wraps a UInt8 foreground-alpha array as an ARGB Bitmap (the RGB channels are irrelevant —
     * `PorterDuff.Mode.SRC_IN` only looks at alpha), then bilinearly upscales to
     * (dstW × dstH).
     */
    private fun upscaleAlphaToBitmap(
        alpha: ByteArray,
        srcW: Int,
        srcH: Int,
        dstW: Int,
        dstH: Int,
    ): Bitmap? {
        if (srcW <= 0 || srcH <= 0 || dstW <= 0 || dstH <= 0) return null
        val srcNeeded = srcW * srcH
        val srcPixels = maskSrcArgbScratch?.takeIf { it.size == srcNeeded }
            ?: IntArray(srcNeeded).also { maskSrcArgbScratch = it }
        var i = 0
        while (i < srcPixels.size) {
            val a = alpha[i].toInt() and 0xFF
            srcPixels[i] = a shl 24 // RGB=0, alpha-only
            i++
        }
        val src = Bitmap.createBitmap(srcPixels, srcW, srcH, Bitmap.Config.ARGB_8888)
        if (srcW == dstW && srcH == dstH) return src
        val scaled = Bitmap.createScaledBitmap(src, dstW, dstH, /* filter = */ true)
        if (scaled !== src) src.recycle()
        return scaled
    }

    /**
     * Background blur: downscale by [BACKGROUND_BLUR_DOWNSAMPLE], three iterations of box-blur
     * at radius [BACKGROUND_BLUR_RADIUS] (≈ Gaussian), then upscale back. This matches the iOS
     * pipeline's quarter-resolution Gaussian pass.
     */
    private fun blurBackgroundBitmap(input: Bitmap): Bitmap? {
        val w = input.width
        val h = input.height
        val dsW = (w * BACKGROUND_BLUR_DOWNSAMPLE).toInt().coerceAtLeast(8)
        val dsH = (h * BACKGROUND_BLUR_DOWNSAMPLE).toInt().coerceAtLeast(8)
        val downscaled = Bitmap.createScaledBitmap(input, dsW, dsH, /* filter = */ true)
        val needed = dsW * dsH
        val pixels = blurPixelsScratch?.takeIf { it.size == needed } ?: IntArray(needed).also {
            blurPixelsScratch = it
        }
        val tmp = blurTmpScratch?.takeIf { it.size == needed } ?: IntArray(needed).also {
            blurTmpScratch = it
        }
        downscaled.getPixels(pixels, 0, dsW, 0, 0, dsW, dsH)
        repeat(3) { boxBlurPixelsInPlace(pixels, tmp, dsW, dsH, BACKGROUND_BLUR_RADIUS) }
        downscaled.setPixels(pixels, 0, dsW, 0, 0, dsW, dsH)
        val upscaled = Bitmap.createScaledBitmap(downscaled, w, h, /* filter = */ true)
        if (upscaled !== downscaled) downscaled.recycle()
        return upscaled
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
        val yBuf = i420.dataY
        val uBuf = i420.dataU
        val vBuf = i420.dataV
        val yStride = i420.strideY
        val uStride = i420.strideU
        val vStride = i420.strideV

        val needed = w * h
        val pixels = i420ArgbScratch?.takeIf { it.size == needed } ?: IntArray(needed).also {
            i420ArgbScratch = it
        }
        var y = 0
        while (y < h) {
            val yRow = y * yStride
            val uvRow = (y / 2) * uStride
            val vRow = (y / 2) * vStride
            val outRow = y * w
            var x = 0
            while (x < w) {
                val yv = (yBuf.get(yRow + x).toInt() and 0xFF) - 16
                val uv = (uBuf.get(uvRow + (x / 2)).toInt() and 0xFF) - 128
                val vv = (vBuf.get(vRow + (x / 2)).toInt() and 0xFF) - 128
                val c298 = 298 * yv
                val r = (c298 + 409 * vv + 128) shr 8
                val g = (c298 - 100 * uv - 208 * vv + 128) shr 8
                val b = (c298 + 516 * uv + 128) shr 8
                pixels[outRow + x] = 0xFF.shl(24) or
                    (r.coerceIn(0, 255) shl 16) or
                    (g.coerceIn(0, 255) shl 8) or
                    b.coerceIn(0, 255)
                x++
            }
            y++
        }
        val bitmap = ensureArgbBitmap(w, h)
        bitmap.setPixels(pixels, 0, w, 0, 0, w, h)
        return bitmap
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
            pooledComposedBitmapW = width
            pooledComposedBitmapH = height
        }
        return pooledComposedBitmap!!
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

        val yBuf = buffer.dataY
        val uBuf = buffer.dataU
        val vBuf = buffer.dataV
        val yStride = buffer.strideY
        val uStride = buffer.strideU
        val vStride = buffer.strideV

        var y = 0
        while (y < eh) {
            val row = y * ew
            val outRow = y * yStride
            var x = 0
            while (x < ew) {
                val px = pixels[row + x]
                val r = (px ushr 16) and 0xFF
                val g = (px ushr 8) and 0xFF
                val b = px and 0xFF
                val yv = ((66 * r + 129 * g + 25 * b + 128) shr 8) + 16
                yBuf.put(outRow + x, yv.coerceIn(0, 255).toByte())
                x++
            }
            y++
        }
        var yy = 0
        while (yy < eh) {
            val uvRow = (yy / 2) * uStride
            val vRow = (yy / 2) * vStride
            var x = 0
            while (x < ew) {
                val px = pixels[yy * ew + x]
                val r = (px ushr 16) and 0xFF
                val g = (px ushr 8) and 0xFF
                val b = px and 0xFF
                val uv = ((-38 * r - 74 * g + 112 * b + 128) shr 8) + 128
                val vv = ((112 * r - 94 * g - 18 * b + 128) shr 8) + 128
                uBuf.put(uvRow + (x / 2), uv.coerceIn(0, 255).toByte())
                vBuf.put(vRow + (x / 2), vv.coerceIn(0, 255).toByte())
                x += 2
            }
            yy += 2
        }
    }
}
