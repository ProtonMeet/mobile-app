package com.proton.proton_denoise

import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteOrder

/** Reads 16-bit PCM WAV without MediaCodec (reliable for offline debug). */
internal object DebugWavReader {
    fun readMono16ToFloat(path: String, targetSampleRateHz: Int): FloatArray {
        val file = File(path)
        RandomAccessFile(file, "r").use { raf ->
            val riff = ByteArray(4)
            if (raf.read(riff) != 4 || String(riff) != "RIFF") {
                throw IllegalArgumentException("Not a RIFF file: $path")
            }
            readLeInt(raf) // chunk size
            val wave = ByteArray(4)
            if (raf.read(wave) != 4 || String(wave) != "WAVE") {
                throw IllegalArgumentException("Not a WAVE file: $path")
            }

            var audioFormat = 1
            var channels = 1
            var sampleRate = 0
            var bitsPerSample = 16
            var dataSize = 0
            var dataOffset = 0L

            while (raf.filePointer + 8 <= raf.length()) {
                val chunkId = readChunkId(raf)
                val chunkSize = readLeInt(raf).toLong()
                when (chunkId) {
                    "fmt " -> {
                        audioFormat = readLeShort(raf).toInt()
                        channels = readLeShort(raf).toInt()
                        sampleRate = readLeInt(raf)
                        readLeInt(raf) // byte rate
                        readLeShort(raf) // block align
                        bitsPerSample = readLeShort(raf).toInt()
                        val consumed = 16L
                        if (chunkSize > consumed) {
                            raf.seek(raf.filePointer + (chunkSize - consumed))
                        }
                    }
                    "data" -> {
                        dataSize = chunkSize.toInt()
                        dataOffset = raf.filePointer
                        raf.seek(raf.filePointer + chunkSize)
                    }
                    else -> raf.seek(raf.filePointer + chunkSize)
                }
            }

            if (dataSize <= 0 || sampleRate <= 0) {
                throw IllegalArgumentException("Invalid WAV PCM in $path")
            }
            if (audioFormat != 1 || bitsPerSample != 16) {
                throw IllegalArgumentException(
                    "Only 16-bit PCM WAV supported (format=$audioFormat bits=$bitsPerSample)",
                )
            }

            raf.seek(dataOffset)
            val bytes = ByteArray(dataSize)
            raf.readFully(bytes)
            val shorts = ShortArray(dataSize / 2)
            val buffer = java.nio.ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
            buffer.asShortBuffer().get(shorts)

            val mono = downmixToMono(shorts, channels)
            val floats = FloatArray(mono.size) { i -> mono[i] / 32768f }
            return MeetAudioPcm.resample(floats, sampleRate, targetSampleRateHz)
        }
    }

    private fun downmixToMono(interleaved: ShortArray, channels: Int): ShortArray {
        if (channels <= 1) {
            return interleaved
        }
        val frames = interleaved.size / channels
        return ShortArray(frames) { frame ->
            var sum = 0
            for (ch in 0 until channels) {
                sum += interleaved[frame * channels + ch]
            }
            (sum / channels).toShort()
        }
    }

    private fun readChunkId(raf: RandomAccessFile): String {
        val id = ByteArray(4)
        raf.readFully(id)
        return String(id)
    }

    private fun readLeInt(raf: RandomAccessFile): Int {
        val b0 = raf.read()
        val b1 = raf.read()
        val b2 = raf.read()
        val b3 = raf.read()
        return (b0 and 0xff) or ((b1 and 0xff) shl 8) or
            ((b2 and 0xff) shl 16) or ((b3 and 0xff) shl 24)
    }

    private fun readLeShort(raf: RandomAccessFile): Short {
        val b0 = raf.read()
        val b1 = raf.read()
        return ((b0 and 0xff) or ((b1 and 0xff) shl 8)).toShort()
    }
}
