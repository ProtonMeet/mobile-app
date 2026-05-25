package me.proton.meet.video_effects

import io.flutter.embedding.engine.plugins.FlutterPlugin

/** Registers background-blur (and future video effects) on the flutter_webrtc camera pipeline. */
class ProtonVideoEffectsPlugin : FlutterPlugin {
    private var blurChannel: BackgroundBlurChannel? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        blurChannel = BackgroundBlurChannel(binding).also { it.init() }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        blurChannel?.dispose()
        blurChannel = null
    }
}
