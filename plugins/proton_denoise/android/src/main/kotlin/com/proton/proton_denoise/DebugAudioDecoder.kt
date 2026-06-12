package com.proton.proton_denoise

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import java.nio.ByteBuffer
import java.nio.ByteOrder

/** Decodes local audio files to mono float PCM at a target sample rate. */
internal object DebugAudioDecoder {
    fun decodeToMonoFloat(path: String, targetSampleRateHz: Int): FloatArray {
        if (path.endsWith(".wav", ignoreCase = true)) {
            return DebugWavReader.readMono16ToFloat(path, targetSampleRateHz)
        }
        val extractor = MediaExtractor()
        extractor.setDataSource(path)
        var trackIndex = -1
        for (i in 0 until extractor.trackCount) {
            val format = extractor.getTrackFormat(i)
            val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
            if (mime.startsWith("audio/")) {
                trackIndex = i
                break
            }
        }
        if (trackIndex < 0) {
            extractor.release()
            throw IllegalArgumentException("No audio track in $path")
        }
        extractor.selectTrack(trackIndex)
        val format = extractor.getTrackFormat(trackIndex)
        val mime = format.getString(MediaFormat.KEY_MIME)
            ?: throw IllegalArgumentException("Missing MIME for audio track")
        val sourceRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        val channelCount = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)

        val codec = MediaCodec.createDecoderByType(mime)
        codec.configure(format, null, null, 0)
        codec.start()

        val pcmChunks = mutableListOf<ShortArray>()
        var decodedSampleRate = sourceRate
        var inputDone = false
        val bufferInfo = MediaCodec.BufferInfo()

        while (true) {
            if (!inputDone) {
                val inIndex = codec.dequeueInputBuffer(10_000)
                if (inIndex >= 0) {
                    val inputBuffer = codec.getInputBuffer(inIndex) ?: continue
                    val sampleSize = extractor.readSampleData(inputBuffer, 0)
                    if (sampleSize < 0) {
                        codec.queueInputBuffer(
                            inIndex,
                            0,
                            0,
                            0,
                            MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                        )
                        inputDone = true
                    } else {
                        codec.queueInputBuffer(
                            inIndex,
                            0,
                            sampleSize,
                            extractor.sampleTime,
                            0,
                        )
                        extractor.advance()
                    }
                }
            }

            val outIndex = codec.dequeueOutputBuffer(bufferInfo, 10_000)
            when {
                outIndex == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                    if (inputDone) {
                        break
                    }
                }
                outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    val outputFormat = codec.outputFormat
                    if (outputFormat.containsKey(MediaFormat.KEY_SAMPLE_RATE)) {
                        decodedSampleRate =
                            outputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    }
                }
                outIndex >= 0 -> {
                    val outputBuffer = codec.getOutputBuffer(outIndex)
                    if (outputBuffer != null && bufferInfo.size > 0) {
                        outputBuffer.order(ByteOrder.LITTLE_ENDIAN)
                        val shorts = ShortArray(bufferInfo.size / 2)
                        outputBuffer.asShortBuffer().get(shorts)
                        pcmChunks.add(shorts)
                    }
                    codec.releaseOutputBuffer(outIndex, false)
                    if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                        break
                    }
                }
            }
        }

        codec.stop()
        codec.release()
        extractor.release()

        val totalShorts = pcmChunks.sumOf { it.size }
        val interleaved = ShortArray(totalShorts)
        var offset = 0
        for (chunk in pcmChunks) {
            chunk.copyInto(interleaved, offset)
            offset += chunk.size
        }

        val monoShorts = downmixToMono(interleaved, channelCount)
        val floats = FloatArray(monoShorts.size) { i -> monoShorts[i] / 32768f }
        return MeetAudioPcm.resample(floats, decodedSampleRate, targetSampleRateHz)
    }

    private fun downmixToMono(interleaved: ShortArray, channels: Int): ShortArray {
        if (channels <= 1) {
            return interleaved
        }
        val frames = interleaved.size / channels
        val mono = ShortArray(frames)
        for (frame in 0 until frames) {
            var sum = 0
            for (ch in 0 until channels) {
                sum += interleaved[frame * channels + ch]
            }
            mono[frame] = (sum / channels).toShort()
        }
        return mono
    }
}
