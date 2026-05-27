package com.proton.proton_denoise

import kotlin.test.Test
import kotlin.test.assertFalse

internal class ProtonDenoisePluginTest {
    @Test
    fun rnnoiseNative_notLoadedInJvmUnitTest() {
        // JVM unit tests do not package libproton_denoise.so.
        assertFalse(MeetAudioRnnoiseProcessor.isNativeReady)
    }
}
