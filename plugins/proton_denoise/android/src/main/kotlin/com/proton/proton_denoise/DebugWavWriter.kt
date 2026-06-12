package com.proton.proton_denoise

import java.io.File
import java.io.RandomAccessFile
import kotlin.math.roundToInt

internal object DebugWavWriter {
    fun write16BitMono(file: File, samples: FloatArray, sampleRate: Int) {
        val numChannels = 1
        val bitsPerSample = 16
        val byteRate = sampleRate * numChannels * bitsPerSample / 8
        val dataSize = samples.size * 2
        RandomAccessFile(file, "rw").use { raf ->
            raf.setLength(0)
            raf.writeBytes("RIFF")
            writeIntLE(raf, 36 + dataSize)
            raf.writeBytes("WAVE")
            raf.writeBytes("fmt ")
            writeIntLE(raf, 16)
            writeShortLE(raf, 1)
            writeShortLE(raf, numChannels.toShort())
            writeIntLE(raf, sampleRate)
            writeIntLE(raf, byteRate)
            writeShortLE(raf, (numChannels * bitsPerSample / 8).toShort())
            writeShortLE(raf, bitsPerSample.toShort())
            raf.writeBytes("data")
            writeIntLE(raf, dataSize)
            val bytes = ByteArray(2)
            for (sample in samples) {
                val clamped = sample.coerceIn(-1f, 1f)
                val s = (clamped * 32767f).roundToInt().toShort()
                bytes[0] = (s.toInt() and 0xff).toByte()
                bytes[1] = ((s.toInt() shr 8) and 0xff).toByte()
                raf.write(bytes)
            }
        }
    }

    private fun writeIntLE(raf: RandomAccessFile, value: Int) {
        raf.writeByte(value and 0xff)
        raf.writeByte((value shr 8) and 0xff)
        raf.writeByte((value shr 16) and 0xff)
        raf.writeByte((value shr 24) and 0xff)
    }

    private fun writeShortLE(raf: RandomAccessFile, value: Short) {
        val v = value.toInt()
        raf.writeByte(v and 0xff)
        raf.writeByte((v shr 8) and 0xff)
    }
}
