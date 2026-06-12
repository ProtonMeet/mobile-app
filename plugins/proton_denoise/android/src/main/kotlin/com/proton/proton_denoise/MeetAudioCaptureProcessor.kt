package com.proton.proton_denoise

import com.cloudwebrtc.webrtc.audio.AudioProcessingAdapter

/** Common lifecycle for flutter-webrtc capture post-processing backends. */
internal interface MeetAudioCaptureProcessor :
    AudioProcessingAdapter.ExternalAudioFrameProcessing {
    fun setEnabled(enabled: Boolean)
    fun release()
}
