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
import kotlin.test.assertEquals
import org.junit.jupiter.api.Test

/**
 * Guards the wire contract with Dart `MaskEdgeTuning.toMethodChannelArgs`. The keys are the only
 * thing tying the two sides together, so a rename on either side has to fail here rather than
 * silently degrade Android back to unshaped masks.
 */
class MaskEdgeTuningTest {

    private fun call(args: Map<String, Any?>) = MethodCall("setBackgroundBlurConfig", args)

    @Test
    fun `reads every key Dart sends`() {
        val tuning = MaskEdgeTuning.fromMethodCall(
            call(
                mapOf(
                    "maskFeatherHeightFraction" to 0.01,
                    "maskErodeHeightFraction" to 0.004,
                    "maskSolidifySlope" to 8.0,
                    "maskSolidifyMidpoint" to 0.4,
                    "maskForegroundGamma" to 1.5,
                ),
            ),
        )

        assertEquals(0.01f, tuning.featherHeightFraction)
        assertEquals(0.004f, tuning.erodeHeightFraction)
        assertEquals(8f, tuning.solidifySlope)
        assertEquals(0.4f, tuning.solidifyMidpoint)
        assertEquals(1.5f, tuning.foregroundGamma)
    }

    @Test
    fun `missing keys fall back to the defaults an older client expects`() {
        val tuning = MaskEdgeTuning.fromMethodCall(call(mapOf("blurSigma" to 128.0)))

        assertEquals(MaskEdgeTuning(), tuning)
    }

    @Test
    fun `clamps out-of-range values to the same bounds as Dart`() {
        val tuning = MaskEdgeTuning.fromMethodCall(
            call(
                mapOf(
                    "maskFeatherHeightFraction" to 9.0,
                    "maskErodeHeightFraction" to -1.0,
                    "maskSolidifySlope" to 99.0,
                    "maskSolidifyMidpoint" to 0.0,
                    "maskForegroundGamma" to 42.0,
                ),
            ),
        )

        assertEquals(MaskEdgeTuning.MAX_EDGE_FRACTION, tuning.featherHeightFraction)
        assertEquals(0f, tuning.erodeHeightFraction)
        assertEquals(MaskEdgeTuning.MAX_SOLIDIFY_SLOPE, tuning.solidifySlope)
        assertEquals(MaskEdgeTuning.MIN_SOLIDIFY_MIDPOINT, tuning.solidifyMidpoint)
        assertEquals(MaskEdgeTuning.MAX_FOREGROUND_GAMMA, tuning.foregroundGamma)
    }

    @Test
    fun `defaults match the Apple pipeline neutral gamma`() {
        // 1.35 here was what pushed uncertain interior samples toward background and ate the
        // subject; the solidify stage is what fixes translucency now, so gamma must stay neutral.
        assertEquals(1f, MaskEdgeTuning().foregroundGamma)
        assertEquals(6f, MaskEdgeTuning().solidifySlope)
    }
}
