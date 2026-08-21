package com.proton.proton_denoise

import android.content.Context
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** Per-backend readiness probes for debug settings UI. */
internal object DenoiseDiagnostics {
    private fun withPlatform(details: Map<String, Any>): Map<String, Any> =
            details + ("platform" to "android")

    private val allTypeIds =
            listOf(
                    DenoiseKind.RNNOISE.id,
                    DenoiseKind.DEEPFILTER.id,
                    DenoiseKind.DTLN_RS.id,
            )

    fun warmUpAll(context: Context): List<Map<String, Any>> =
            allTypeIds.map { typeId ->
                warmUp(context, typeId).toMutableMap().apply { put("id", typeId) }
            }

    fun warmUp(context: Context, typeId: String): Map<String, Any> =
            when (DenoiseKind.fromId(typeId)) {
                DenoiseKind.RNNOISE -> warmUpRnnoise()
                DenoiseKind.DEEPFILTER -> warmUpDeepFilter(context)
                DenoiseKind.DTLN_RS -> warmUpDtln()
                null ->
                        withPlatform(
                                mapOf(
                                        "warmUpOk" to false,
                                        "warmUpMs" to 0,
                                        "error" to "Unknown denoise type: $typeId",
                                ),
                        )
            }

    fun payload(context: Context): List<Map<String, Any>> =
            listOf(
                    rnnoiseEntry(),
                    deepfilterEntry(context),
                    dtlnEntry(),
            )

    private fun rnnoiseEntry(): Map<String, Any> {
        var createProbe = false
        var frameSize = 0
        if (ProtonRnnoiseNative.isAvailable) {
            val probe = ProtonRnnoiseNative.create()
            if (probe != 0L) {
                frameSize = ProtonRnnoiseNative.getFrameSize()
                ProtonRnnoiseNative.destroy(probe)
                createProbe = frameSize > 0
            }
        }
        return mapOf(
                "id" to DenoiseKind.RNNOISE.id,
                "displayName" to "RNNoise",
                "isReady" to MeetAudioRnnoiseProcessor.isNativeReady,
                "details" to
                        withPlatform(
                                mapOf(
                                        "libLoaded" to ProtonRnnoiseNative.isAvailable,
                                        "createProbe" to createProbe,
                                        "frameSize" to frameSize,
                                ),
                        ),
        )
    }

    private fun deepfilterEntry(context: Context): Map<String, Any> {
        val assetPath = DeepFilterModelStore.resolveAssetPath(context)
        val staged = DeepFilterModelStore.ensureModelFile(context)
        var createProbe = false
        var frameSize = 0
        if (ProtonDeepFilterNative.isAvailable && staged != null) {
            val handle = ProtonDeepFilterNative.create(staged.absolutePath)
            if (handle != 0L) {
                frameSize = ProtonDeepFilterNative.getFrameSize(handle)
                ProtonDeepFilterNative.destroy(handle)
                createProbe = frameSize > 0
            }
        }
        return mapOf(
                "id" to DenoiseKind.DEEPFILTER.id,
                "displayName" to "DeepFilter 3",
                "isReady" to MeetAudioDeepFilterProcessor.isNativeReady(context),
                "details" to
                        withPlatform(
                                mapOf(
                                        "runtimeAvailable" to ProtonDeepFilterNative.isAvailable,
                                        "modelAsset" to (assetPath ?: ""),
                                        "modelStaged" to (staged?.absolutePath ?: ""),
                                        "modelFound" to
                                                DeepFilterModelStore.isModelAvailable(context),
                                        "createProbe" to createProbe,
                                        "frameSize" to frameSize,
                                ),
                        ),
        )
    }

    private fun warmUpRnnoise(): Map<String, Any> {
        val start = System.nanoTime()
        var warmUpOk = false
        var frameSize = 0
        if (ProtonRnnoiseNative.isAvailable) {
            val handle = ProtonRnnoiseNative.create()
            if (handle != 0L) {
                frameSize = ProtonRnnoiseNative.getFrameSize()
                ProtonRnnoiseNative.destroy(handle)
                warmUpOk = frameSize > 0
            }
        }
        val ms = ((System.nanoTime() - start) / 1_000_000).toInt()
        return withPlatform(
                mapOf(
                        "warmUpOk" to warmUpOk,
                        "warmUpMs" to ms,
                        "frameSize" to frameSize,
                ),
        )
    }

    private fun warmUpDeepFilter(context: Context): Map<String, Any> {
        val start = System.nanoTime()
        if (!ProtonDeepFilterNative.isAvailable) {
            return withPlatform(
                    mapOf(
                            "warmUpOk" to false,
                            "warmUpMs" to 0,
                            "error" to "DeepFilter native library unavailable",
                    ),
            )
        }
        val staged = DeepFilterModelStore.ensureModelFile(context)
        if (staged == null) {
            return withPlatform(
                    mapOf(
                            "warmUpOk" to false,
                            "warmUpMs" to 0,
                            "error" to "DeepFilter model not staged",
                    ),
            )
        }
        val executor = Executors.newSingleThreadExecutor()
        return try {
            val probe =
                    executor
                            .submit<Map<String, Any>> {
                                val handle = ProtonDeepFilterNative.create(staged.absolutePath)
                                if (handle == 0L) {
                                    return@submit mapOf(
                                            "warmUpOk" to false,
                                            "frameSize" to 0,
                                    )
                                }
                                val frameSize = ProtonDeepFilterNative.getFrameSize(handle)
                                ProtonDeepFilterNative.setEnabled(handle, true)
                                ProtonDeepFilterNative.destroy(handle)
                                mapOf(
                                        "warmUpOk" to (frameSize > 0),
                                        "frameSize" to frameSize,
                                )
                            }
                            .get(30, TimeUnit.SECONDS)
            val ms = ((System.nanoTime() - start) / 1_000_000).toInt()
            withPlatform(probe.toMutableMap().apply { put("warmUpMs", ms) })
        } catch (e: Exception) {
            withPlatform(
                    mapOf(
                            "warmUpOk" to false,
                            "warmUpMs" to ((System.nanoTime() - start) / 1_000_000).toInt(),
                            "error" to (e.message ?: "warmUp failed"),
                    ),
            )
        } finally {
            executor.shutdown()
        }
    }

    private fun warmUpDtln(): Map<String, Any> {
        val start = System.nanoTime()
        var warmUpOk = false
        var sampleRate = 0
        var blockShift = 0
        if (ProtonDtlnRsNative.isAvailable) {
            val handle = ProtonDtlnRsNative.create()
            if (handle != 0L) {
                sampleRate = ProtonDtlnRsNative.getSampleRate()
                blockShift = ProtonDtlnRsNative.getBlockShift()
                ProtonDtlnRsNative.destroy(handle)
                warmUpOk = sampleRate > 0 && blockShift > 0
            }
        }
        val ms = ((System.nanoTime() - start) / 1_000_000).toInt()
        return withPlatform(
                mapOf(
                        "warmUpOk" to warmUpOk,
                        "warmUpMs" to ms,
                        "sampleRate" to sampleRate,
                        "blockShift" to blockShift,
                ),
        )
    }

    private fun dtlnEntry(): Map<String, Any> {
        var createProbe = false
        var sampleRate = 0
        var blockShift = 0
        if (ProtonDtlnRsNative.isAvailable) {
            val probe = ProtonDtlnRsNative.create()
            if (probe != 0L) {
                sampleRate = ProtonDtlnRsNative.getSampleRate()
                blockShift = ProtonDtlnRsNative.getBlockShift()
                ProtonDtlnRsNative.destroy(probe)
                createProbe = sampleRate > 0 && blockShift > 0
            }
        }
        return mapOf(
                "id" to DenoiseKind.DTLN_RS.id,
                "displayName" to "DTLN",
                "isReady" to MeetAudioDtlnRsProcessor.isNativeReady,
                "details" to
                        withPlatform(
                                mapOf(
                                        "libLoaded" to ProtonDtlnRsNative.isAvailable,
                                        "createProbe" to createProbe,
                                        "sampleRate" to sampleRate,
                                        "blockShift" to blockShift,
                                ),
                        ),
        )
    }
}
