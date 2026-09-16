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

import io.flutter.plugin.common.MethodCall

/**
 * Shape of the segmentation mask before it is used to blend subject over background.
 *
 * Kotlin counterpart of Dart `MaskEdgeTuning` and of `MaskEdgeTuning` in
 * `MeetBackgroundBlurMediaPipeEngine.swift`. The three must stay in sync: Dart owns the defaults
 * and the clamp ranges, and sends every field on `setBlurConfig`.
 *
 * The stages run in the same fixed order as Apple's pipeline — erode, solidify, feather, gamma —
 * which is what keeps the knobs independent. Erosion moves the outline without reshaping the ramp;
 * solidify fixes interior translucency while leaving a narrow boundary ramp; the feather then
 * widens that ramp into the visible soft edge; gamma reweights the finished result.
 *
 * Apple runs these *after* upscaling the mask to frame resolution, using Core Image on the GPU.
 * Doing that here would mean per-pixel Kotlin loops over a 720p mask every frame, so we run in
 * mask space (256²) instead and convert the frame-height fractions to mask pixels. Because the
 * mask is a scaled copy of the frame, `fraction × frameHeight` frame pixels is exactly
 * `fraction × maskHeight` mask pixels, so the dials mean the same thing on both platforms.
 */
internal data class MaskEdgeTuning(
    val featherHeightFraction: Float = DEFAULT_FEATHER_HEIGHT_FRACTION,
    val erodeHeightFraction: Float = DEFAULT_ERODE_HEIGHT_FRACTION,
    val solidifySlope: Float = DEFAULT_SOLIDIFY_SLOPE,
    val solidifyMidpoint: Float = DEFAULT_SOLIDIFY_MIDPOINT,
    val foregroundGamma: Float = DEFAULT_FOREGROUND_GAMMA,
) {
    companion object {
        const val DEFAULT_FEATHER_HEIGHT_FRACTION = 0.005f
        const val DEFAULT_ERODE_HEIGHT_FRACTION = 0.002f
        const val DEFAULT_SOLIDIFY_SLOPE = 6f
        const val DEFAULT_SOLIDIFY_MIDPOINT = 0.55f
        const val DEFAULT_FOREGROUND_GAMMA = 1f

        const val MAX_EDGE_FRACTION = 0.05f
        const val MIN_SOLIDIFY_SLOPE = 1f
        const val MAX_SOLIDIFY_SLOPE = 16f
        const val MIN_SOLIDIFY_MIDPOINT = 0.2f
        const val MAX_SOLIDIFY_MIDPOINT = 0.8f
        const val MIN_FOREGROUND_GAMMA = 0.5f
        const val MAX_FOREGROUND_GAMMA = 3f

        /**
         * Reads the five `mask*` keys Dart sends alongside `blurSigma`.
         *
         * A missing key falls back to the default rather than to the current value: Dart always
         * sends the complete set, so a gap means an older client, and the defaults are what that
         * client is expecting to get.
         */
        fun fromMethodCall(call: MethodCall): MaskEdgeTuning {
            fun read(key: String, fallback: Float): Float =
                call.argument<Number>(key)?.toFloat() ?: fallback

            return MaskEdgeTuning(
                featherHeightFraction = read(
                    "maskFeatherHeightFraction",
                    DEFAULT_FEATHER_HEIGHT_FRACTION,
                ),
                erodeHeightFraction = read(
                    "maskErodeHeightFraction",
                    DEFAULT_ERODE_HEIGHT_FRACTION,
                ),
                solidifySlope = read("maskSolidifySlope", DEFAULT_SOLIDIFY_SLOPE),
                solidifyMidpoint = read("maskSolidifyMidpoint", DEFAULT_SOLIDIFY_MIDPOINT),
                foregroundGamma = read("maskForegroundGamma", DEFAULT_FOREGROUND_GAMMA),
            ).clamped()
        }
    }

    /** Dart clamps too, but this engine is also driven by tests and by the debug channel. */
    fun clamped(): MaskEdgeTuning = MaskEdgeTuning(
        featherHeightFraction = featherHeightFraction.coerceIn(0f, MAX_EDGE_FRACTION),
        erodeHeightFraction = erodeHeightFraction.coerceIn(0f, MAX_EDGE_FRACTION),
        solidifySlope = solidifySlope.coerceIn(MIN_SOLIDIFY_SLOPE, MAX_SOLIDIFY_SLOPE),
        solidifyMidpoint = solidifyMidpoint.coerceIn(MIN_SOLIDIFY_MIDPOINT, MAX_SOLIDIFY_MIDPOINT),
        foregroundGamma = foregroundGamma.coerceIn(MIN_FOREGROUND_GAMMA, MAX_FOREGROUND_GAMMA),
    )
}
