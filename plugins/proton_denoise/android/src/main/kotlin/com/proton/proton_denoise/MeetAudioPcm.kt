package com.proton.proton_denoise

import kotlin.math.min

/** Shared PCM helpers for capture processors and offline debug denoise. */
internal object MeetAudioPcm {
    /** Typical WebRTC capture rate (RNNoise expects 48 kHz frames). */
    const val WEBRTC_CAPTURE_SAMPLE_RATE_HZ = 48000

    /** dtln-rs model input rate. */
    const val DTLN_SAMPLE_RATE_HZ = 16000

    fun downmix(samples: FloatArray, channels: Int): FloatArray {
        if (channels <= 1) {
            return samples
        }
        val frames = samples.size / channels
        return FloatArray(frames) { frame ->
            var sum = 0f
            for (ch in 0 until channels) {
                sum += samples[frame * channels + ch]
            }
            sum / channels
        }
    }

    fun upmixToChannels(mono: FloatArray, channels: Int, frames: Int): FloatArray {
        val out = FloatArray(frames * channels)
        for (frame in 0 until frames) {
            val value = mono.getOrElse(frame) { 0f }
            for (ch in 0 until channels) {
                out[frame * channels + ch] = value
            }
        }
        return out
    }

    fun resample(input: FloatArray, fromRate: Int, toRate: Int): FloatArray {
        if (fromRate == toRate || input.isEmpty()) {
            return input
        }
        val outLen = ((input.size.toLong() * toRate) / fromRate).toInt().coerceAtLeast(1)
        return FloatArray(outLen) { i ->
            val srcPos = i.toDouble() * fromRate / toRate
            val idx = srcPos.toInt().coerceIn(0, input.size - 1)
            val frac = (srcPos - idx).toFloat()
            val next = min(idx + 1, input.size - 1)
            input[idx] * (1f - frac) + input[next] * frac
        }
    }

    fun padToMultiple(samples: FloatArray, blockSize: Int): FloatArray {
        if (blockSize <= 0) {
            return samples
        }
        val len = ((samples.size + blockSize - 1) / blockSize) * blockSize
        if (len == samples.size) {
            return samples
        }
        return samples.copyOf(len)
    }
}
