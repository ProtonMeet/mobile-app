package com.proton.proton_screen_recorder

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.util.Log
import java.io.File
import java.io.FileInputStream

/** Publishes completed recordings to the public Downloads folder. */
object RecordingMediaStore {
    private const val TAG = "RecordingMediaStore"
    private const val SUBFOLDER = "Proton Meet"

    fun publishToDownloads(
        context: Context,
        sourceFile: File,
        displayName: String,
    ): String? {
        if (!sourceFile.exists() || sourceFile.length() <= 0L) {
            Log.w(TAG, "publishToDownloads: source missing or empty: ${sourceFile.path}")
            return null
        }

        val resolver = context.contentResolver
        val values =
            ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, displayName)
                put(MediaStore.MediaColumns.MIME_TYPE, "video/mp4")
                put(MediaStore.MediaColumns.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/$SUBFOLDER")
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
            }

        val collection =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                MediaStore.Downloads.EXTERNAL_CONTENT_URI
            } else {
                @Suppress("DEPRECATION")
                MediaStore.Files.getContentUri("external")
            }

        val uri = resolver.insert(collection, values)
        if (uri == null) {
            Log.e(TAG, "publishToDownloads: MediaStore insert failed")
            return null
        }

        return runCatching {
            resolver.openOutputStream(uri)?.use { output ->
                FileInputStream(sourceFile).use { input ->
                    input.copyTo(output)
                }
            } ?: throw IllegalStateException("Could not open MediaStore output stream")

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val published = ContentValues().apply {
                    put(MediaStore.MediaColumns.IS_PENDING, 0)
                }
                resolver.update(uri, published, null, null)
            }

            publicDisplayPath(displayName)
        }.onFailure { error ->
            Log.e(TAG, "publishToDownloads failed", error)
            resolver.delete(uri, null, null)
        }.getOrNull()
    }

    fun publicDisplayPath(fileName: String): String {
        return "/storage/emulated/0/${Environment.DIRECTORY_DOWNLOADS}/$SUBFOLDER/$fileName"
    }
}
