package com.proton.proton_denoise

import io.flutter.embedding.engine.plugins.FlutterPlugin

/** Registers WebRTC track denoise on `me.proton.meet/denoise` (see [AudioDenoiseChannel]). */
class ProtonDenoisePlugin : FlutterPlugin {
    private var audioDenoiseChannel: AudioDenoiseChannel? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        audioDenoiseChannel = AudioDenoiseChannel(flutterPluginBinding).also { it.init() }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        audioDenoiseChannel?.dispose()
        audioDenoiseChannel = null
    }
}
