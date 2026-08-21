package com.proton.proton_denoise

import android.content.Context
import android.util.Log
import java.io.File

/** Offline file denoise for debug — uses the same pipelines as live capture processors. */
internal object OfflineFileDenoiser {
    private const val TAG = "OfflineFileDenoiser"

    data class Result(val outputPath: String, val sampleRateHz: Int)

    fun denoiseFileToWav(
        context: Context,
        inputPath: String,
        kind: DenoiseKind,
    ): Result {
        val input = File(inputPath)
        if (!input.isFile) {
            throw IllegalArgumentException("Input file not found: $inputPath")
        }

        val captureRate = MeetAudioPcm.WEBRTC_CAPTURE_SAMPLE_RATE_HZ
        val pcm = DebugAudioDecoder.decodeToMonoFloat(input.absolutePath, captureRate)

        val denoised = when (kind) {
            DenoiseKind.RNNOISE -> denoiseRnnoise(pcm, captureRate)
            DenoiseKind.DTLN_RS -> denoiseDtln(pcm, captureRate)
            DenoiseKind.DEEPFILTER ->
                throw UnsupportedOperationException(
                    "DeepFilter offline debug not implemented",
                )
        }

        val cacheSubdir = when (kind) {
            DenoiseKind.RNNOISE -> "rnnoise_denoise"
            DenoiseKind.DTLN_RS -> "dtln_denoise"
            DenoiseKind.DEEPFILTER -> "deepfilter_denoise"
        }
        val suffix = when (kind) {
            DenoiseKind.RNNOISE -> "rnnoise"
            DenoiseKind.DTLN_RS -> "denoised"
            DenoiseKind.DEEPFILTER -> "deepfilter"
        }

        val outDir = File(context.cacheDir, cacheSubdir).apply { mkdirs() }
        val baseName = input.nameWithoutExtension.ifBlank { "audio" }
        val outFile = File(outDir, "${baseName}_${suffix}.wav")
        DebugWavWriter.write16BitMono(outFile, denoised, captureRate)
        Log.i(TAG, "Wrote ${outFile.absolutePath} (${outFile.length()} bytes) kind=$kind")
        return Result(outFile.absolutePath, captureRate)
    }

    private fun denoiseRnnoise(pcm: FloatArray, sampleRateHz: Int): FloatArray {
        if (!ProtonRnnoiseNative.isAvailable) {
            throw IllegalStateException("RNNoise native library not available")
        }
        val handle = ProtonRnnoiseNative.create()
        if (handle == 0L) {
            throw IllegalStateException("rnnoise_create failed")
        }
        return try {
            val frameSize = ProtonRnnoiseNative.getFrameSize()
            if (frameSize <= 0) {
                throw IllegalStateException("rnnoise_get_frame_size returned $frameSize")
            }
            val out = MeetAudioRnnoisePipeline.denoiseMono(pcm, sampleRateHz, handle)
            val framesProcessed = out.size / frameSize
            var changedSamples = 0
            for (i in out.indices) {
                if (kotlin.math.abs(pcm[i] - out[i]) > 1e-5f) {
                    changedSamples++
                }
            }
            Log.i(
                TAG,
                "RNNoise offline: ${pcm.size} samples @ ${sampleRateHz}Hz, " +
                    "frameSize=$frameSize, framesProcessed=$framesProcessed, " +
                    "changedSamples=$changedSamples",
            )
            if (changedSamples == 0) {
                Log.w(TAG, "RNNoise offline produced identical samples — check native processing")
            }
            out
        } finally {
            ProtonRnnoiseNative.destroy(handle)
        }
    }

    private fun denoiseDtln(pcm: FloatArray, sampleRateHz: Int): FloatArray {
        if (!ProtonDtlnRsNative.isAvailable) {
            throw IllegalStateException("dtln-rs native library not available")
        }
        val handle = ProtonDtlnRsNative.create()
        if (handle == 0L) {
            throw IllegalStateException("dtln_create failed")
        }
        return try {
            MeetAudioDtlnPipeline.denoiseMono(pcm, sampleRateHz, handle)
        } finally {
            ProtonDtlnRsNative.destroy(handle)
        }
    }

}
