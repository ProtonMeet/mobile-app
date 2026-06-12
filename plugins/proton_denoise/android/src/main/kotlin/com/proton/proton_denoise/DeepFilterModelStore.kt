package com.proton.proton_denoise

import android.content.Context
import android.util.Log
import java.io.BufferedInputStream
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.util.zip.GZIPOutputStream

/**
 * Copies the bundled ONNX model from assets into app filesDir for libdf.
 *
 * AGP may store `.tar.gz` assets without the `.gz` suffix and/or as an uncompressed `.tar`
 * (e.g. `DeepFilterNet3_onnx.tar`), so [resolveAssetPath] tries several names and
 * [stageModelFromAsset] re-gzips raw tar bytes before calling df_create.
 */
internal object DeepFilterModelStore {
    private const val TAG = "DeepFilterModelStore"
    private const val ASSET_DIR = "deepfilter"
    const val FILE_NAME = "DeepFilterNet3_onnx.tar.gz"

    private val assetCandidates = listOf(
        "$ASSET_DIR/$FILE_NAME",
        "$ASSET_DIR/DeepFilterNet3_onnx.tar",
    )

    fun resolveAssetPath(context: Context): String? {
        for (path in assetCandidates) {
            if (assetExists(context, path)) {
                return path
            }
        }
        return try {
            context.assets.list(ASSET_DIR)
                ?.firstOrNull { it.contains("DeepFilterNet3") }
                ?.let { "$ASSET_DIR/$it" }
        } catch (_: IOException) {
            null
        }
    }

    fun ensureModelFile(context: Context): File? {
        val dir = File(context.filesDir, ASSET_DIR)
        val out = File(dir, FILE_NAME)
        if (out.isFile && isValidGzipFile(out)) {
            return out
        }
        if (out.isFile) {
            Log.w(TAG, "deleting invalid staged model (${out.length()} bytes, not gzip)")
            out.delete()
        }
        val assetPath = resolveAssetPath(context) ?: run {
            Log.w(TAG, "DeepFilter model asset not found under assets/$ASSET_DIR")
            return null
        }
        return stageModelFromAsset(context, assetPath, out)
    }

    /** Light readiness probe — does not run df_create (matches iOS isBundled). */
    fun isModelAvailable(context: Context): Boolean {
        val dir = File(context.filesDir, ASSET_DIR)
        val staged = File(dir, FILE_NAME)
        if (staged.isFile && isValidGzipFile(staged)) {
            return true
        }
        return resolveAssetPath(context) != null
    }

    private fun stageModelFromAsset(context: Context, assetPath: String, out: File): File? =
        try {
            out.parentFile?.mkdirs()
            openAsset(context, assetPath).use { raw ->
                BufferedInputStream(raw).use { input ->
                    input.mark(2)
                    val header = ByteArray(2)
                    val read = input.read(header)
                    input.reset()
                    if (read < 2) {
                        Log.w(TAG, "DeepFilter asset assets/$assetPath is empty")
                        return null
                    }
                    val gzipPayload =
                        (header[0].toInt() and 0xff) == GZIP_MAGIC0 &&
                            (header[1].toInt() and 0xff) == GZIP_MAGIC1
                    out.outputStream().use { output ->
                        if (gzipPayload) {
                            input.copyTo(output)
                        } else {
                            Log.i(
                                TAG,
                                "assets/$assetPath is not gzip; re-compressing for df_create",
                            )
                            GZIPOutputStream(output).use { gzip ->
                                input.copyTo(gzip)
                            }
                        }
                    }
                }
            }
            if (out.isFile && isValidGzipFile(out)) {
                Log.i(
                    TAG,
                    "staged DeepFilter model from assets/$assetPath (${out.length()} bytes)",
                )
                out
            } else {
                Log.w(TAG, "staged model failed gzip validation")
                out.delete()
                null
            }
        } catch (e: IOException) {
            Log.w(TAG, "failed to stage DeepFilter model from assets/$assetPath", e)
            out.delete()
            null
        }

    private fun isValidGzipFile(file: File): Boolean {
        if (!file.isFile || file.length() < 2L) {
            return false
        }
        return try {
            file.inputStream().buffered().use { input ->
                val b0 = input.read()
                val b1 = input.read()
                b0 == GZIP_MAGIC0 && b1 == GZIP_MAGIC1
            }
        } catch (_: IOException) {
            false
        }
    }

    private fun assetExists(context: Context, path: String): Boolean =
        try {
            openAsset(context, path).use { true }
        } catch (_: IOException) {
            false
        }

    private fun openAsset(context: Context, path: String): InputStream =
        context.assets.open(path)

    private const val GZIP_MAGIC0 = 0x1f
    private const val GZIP_MAGIC1 = 0x8b
}
