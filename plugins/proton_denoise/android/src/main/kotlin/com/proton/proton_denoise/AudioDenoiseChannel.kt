package com.proton.proton_denoise

import android.content.pm.ApplicationInfo
import android.util.Log
import com.cloudwebrtc.webrtc.FlutterWebRTCPlugin
import com.cloudwebrtc.webrtc.audio.AudioProcessingAdapter
import com.cloudwebrtc.webrtc.audio.AudioProcessingController
import com.cloudwebrtc.webrtc.audio.LocalAudioTrack
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

/**
 * Flutter channel ↔ flutter_webrtc local audio track capture post-processing.
 *
 * Stack:
 *   AudioDenoiseChannel — attach / detach / config (this file)
 *   MeetAudio*Processor — per-backend frame callback (RNNoise, DeepFilter, DTLN)
 *
 * Processing runs on WebRTC's capture chain via [AudioProcessingController.capturePostProcessing].
 */
class AudioDenoiseChannel(
    binding: FlutterPlugin.FlutterPluginBinding,
) : MethodChannel(binding.binaryMessenger, CHANNEL_NAME) {

    private val appContext = binding.applicationContext
    private val engine = binding.flutterEngine

    private val processors = ConcurrentHashMap<String, AudioProcessingAdapterHolder>()
    private val debugIoExecutor = Executors.newSingleThreadExecutor()
    private var attachedTrackId: String? = null
    private var attachedKind: DenoiseKind? = null

    fun init() {
        setMethodCallHandler { call: MethodCall, result ->
            try {
                when (call.method) {
                    "listDenoiseTypes" -> result.success(listDenoiseTypesPayload())
                    "isTypeReady" -> {
                        val type = call.argument<String>("type")
                        result.success(isTypeReady(type))
                    }
                    "attach" -> attach(call, result)
                    "detach" -> detach(call, result)
                    "setDeepFilterAttenLim" -> setDeepFilterAttenLim(call, result)
                    "denoiseDebugAudioFile" -> {
                        if (!isDebuggableBuild()) {
                            result.error("UNAVAILABLE", "denoiseDebugAudioFile is debug-only", null)
                            return@setMethodCallHandler
                        }
                        denoiseDebugAudioFile(call, result)
                    }
                    "isDtlnRsNativeReady" -> {
                        if (!isDebuggableBuild()) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        result.success(MeetAudioDtlnRsProcessor.isNativeReady)
                    }
                    "isRnnoiseNativeReady" -> {
                        if (!isDebuggableBuild()) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        result.success(MeetAudioRnnoiseProcessor.isNativeReady)
                    }
                    "diagnoseDenoise" ->
                        debugIoExecutor.execute {
                            try {
                                result.success(DenoiseDiagnostics.payload(appContext))
                            } catch (e: Throwable) {
                                Log.e(TAG, "diagnoseDenoise failed", e)
                                result.error("denoise", e.message, null)
                            }
                        }
                    "warmUpDenoise" -> {
                        val type = call.argument<String>("type")
                        debugIoExecutor.execute {
                            try {
                                if (type.isNullOrEmpty()) {
                                    result.success(DenoiseDiagnostics.warmUpAll(appContext))
                                } else {
                                    val payload =
                                        DenoiseDiagnostics.warmUp(appContext, type).toMutableMap()
                                    payload["id"] = type
                                    result.success(payload)
                                }
                            } catch (e: Throwable) {
                                Log.e(TAG, "warmUpDenoise failed", e)
                                result.error("denoise", e.message, null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Throwable) {
                Log.e(TAG, "method ${call.method} failed", e)
                result.error("denoise", e.message, null)
            }
        }
    }

    fun dispose() {
        val plugin = findWebRtcPlugin("dispose")
        for (id in processors.keys.toList()) {
            detachProcessorFromTrack(id, plugin, removeFromMap = true)
        }
        attachedTrackId = null
        attachedKind = null
        debugIoExecutor.shutdownNow()
        Log.i(TAG, "dispose: released processors")
    }

    private fun listDenoiseTypesPayload(): List<Map<String, Any>> =
        listOf(
            mapOf(
                "id" to DenoiseKind.RNNOISE.id,
                "displayName" to "RNNoise",
                "isReady" to MeetAudioRnnoiseProcessor.isNativeReady,
            ),
            mapOf(
                "id" to DenoiseKind.DEEPFILTER.id,
                "displayName" to "DeepFilter 3",
                "isReady" to MeetAudioDeepFilterProcessor.isNativeReady(appContext),
            ),
            mapOf(
                "id" to DenoiseKind.DEEPFILTER2.id,
                "displayName" to "DeepFilter 2",
                "isReady" to false,
            ),
            mapOf(
                "id" to DenoiseKind.DTLN_RS.id,
                "displayName" to "DTLN",
                "isReady" to MeetAudioDtlnRsProcessor.isNativeReady,
            ),
        )

    private fun isTypeReady(typeId: String?): Boolean =
        when (DenoiseKind.fromId(typeId)) {
            DenoiseKind.RNNOISE -> MeetAudioRnnoiseProcessor.isNativeReady
            DenoiseKind.DEEPFILTER -> MeetAudioDeepFilterProcessor.isNativeReady(appContext)
            DenoiseKind.DEEPFILTER2 -> false
            DenoiseKind.DTLN_RS -> MeetAudioDtlnRsProcessor.isNativeReady
            null -> false
        }

    private fun parseDeepFilterAttenLimDb(call: MethodCall): Float {
        val raw = call.argument<Number>("deepFilterAttenLimDb")
        return raw?.toFloat()?.coerceIn(1f, 100f)
            ?: MeetAudioDeepFilterProcessor.DEFAULT_ATTEN_LIM_DB
    }

    private fun attach(call: MethodCall, result: MethodChannel.Result) {
        val trackId = call.argument<String>("trackId")
        val typeId = call.argument<String>("type")
        val deepFilterAttenLimDb = parseDeepFilterAttenLimDb(call)
        if (trackId.isNullOrEmpty() || typeId.isNullOrEmpty()) {
            result.error("ARGS", "trackId and type required", null)
            return
        }
        val kind = DenoiseKind.fromId(typeId)
        if (kind == null) {
            result.error("ARGS", "Unknown denoise type: $typeId", null)
            return
        }
        when (val lookup = lookupLocalTrack(trackId)) {
            LookupResult.NotReady -> {
                result.error(
                    "WEBRTC_NOT_READY",
                    "FlutterWebRTCPlugin handler not initialized yet — retry after the engine settles",
                    null,
                )
                return
            }
            LookupResult.NotFound -> {
                result.error("TRACK", "Local audio track not found for id=$trackId", null)
                return
            }
            is LookupResult.Found -> {
                Log.i(TAG, "attach: track ${describeTrack(lookup.track)} type=$typeId")
                val plugin = findWebRtcPlugin(trackId)
                if (plugin == null) {
                    result.error("WEBRTC_NOT_READY", "FlutterWebRTCPlugin unavailable", null)
                    return
                }
                val controller = audioProcessingController(plugin)
                if (controller == null) {
                    result.error(
                        "WEBRTC_NOT_READY",
                        "Audio processing controller unavailable",
                        null,
                    )
                    return
                }
                if (attachedTrackId == trackId && attachedKind == kind) {
                    // Idempotent re-attach — same track + backend already wired.
                    processors[trackId]?.let { holder ->
                        holder.setEnabled(true)
                        holder.applyDeepFilterAttenLim(deepFilterAttenLimDb)
                    }
                    result.success(null)
                    return
                }
                clearOtherProcessors(keepTrackId = trackId, plugin = plugin)
                detachProcessorFromTrack(trackId, plugin, removeFromMap = true)
                val holder =
                    AudioProcessingAdapterHolder(
                        kind,
                        appContext,
                        deepFilterAttenLimDb = deepFilterAttenLimDb,
                    )
                // WebRTC calls initialize only once at factory setup; processors added later
                // must be initialized explicitly (iOS creates RNNoise handle in init()).
                holder.processor.initialize(
                    MeetAudioPcm.WEBRTC_CAPTURE_SAMPLE_RATE_HZ,
                    1,
                )
                holder.setEnabled(true)
                controller.capturePostProcessing.addProcessor(holder.processor)
                processors[trackId] = holder
                attachedTrackId = trackId
                attachedKind = kind
                Log.i(TAG, "attach: installed capture processor for trackId=$trackId")
                result.success(null)
            }
        }
    }

    private fun setDeepFilterAttenLim(call: MethodCall, result: MethodChannel.Result) {
        val trackId = call.argument<String>("trackId")
        val attenLimDb = call.argument<Number>("attenLimDb")?.toFloat()
        if (trackId.isNullOrEmpty() || attenLimDb == null) {
            result.error("ARGS", "trackId and attenLimDb required", null)
            return
        }
        val holder = processors[trackId]
        if (holder == null) {
            result.error("TRACK", "No denoise processor for trackId=$trackId", null)
            return
        }
        holder.applyDeepFilterAttenLim(attenLimDb.coerceIn(1f, 100f))
        result.success(null)
    }

    private fun denoiseDebugAudioFile(call: MethodCall, result: MethodChannel.Result) {
        val inputPath = call.argument<String>("inputPath")
        val typeId = call.argument<String>("type") ?: DenoiseKind.DTLN_RS.id
        if (inputPath.isNullOrBlank()) {
            result.error("ARGS", "inputPath required", null)
            return
        }
        val kind = DenoiseKind.fromId(typeId)
        if (kind == null) {
            result.error("ARGS", "Unknown denoise type: $typeId", null)
            return
        }
        if (!isTypeReady(typeId)) {
            result.error("UNAVAILABLE", "$typeId native library not ready", null)
            return
        }
        debugIoExecutor.execute {
            try {
                val output = OfflineFileDenoiser.denoiseFileToWav(appContext, inputPath, kind)
                result.success(
                    mapOf(
                        "outputPath" to output.outputPath,
                        "sampleRateHz" to output.sampleRateHz,
                        "type" to typeId,
                    ),
                )
            } catch (e: Throwable) {
                Log.e(TAG, "denoiseDebugAudioFile failed", e)
                result.error("DENOISE_FAILED", e.message, null)
            }
        }
    }

    private fun detach(call: MethodCall, result: MethodChannel.Result) {
        val trackId = call.argument<String>("trackId")
        if (trackId.isNullOrEmpty()) {
            result.error("ARGS", "trackId required", null)
            return
        }
        val plugin = findWebRtcPlugin(trackId)
        detachProcessorFromTrack(trackId, plugin, removeFromMap = true)
        if (attachedTrackId == trackId) {
            attachedTrackId = null
            attachedKind = null
        }
        result.success(null)
    }

    private fun clearOtherProcessors(keepTrackId: String, plugin: FlutterWebRTCPlugin) {
        // One mic track at a time — detach denoise from any other local track.
        for (id in processors.keys.filter { it != keepTrackId }) {
            detachProcessorFromTrack(id, plugin, removeFromMap = true)
        }
    }

    private fun detachProcessorFromTrack(
        trackId: String,
        plugin: FlutterWebRTCPlugin?,
        removeFromMap: Boolean,
    ) {
        val holder = processors[trackId] ?: return
        holder.setEnabled(false)
        val resolvedPlugin = plugin ?: FlutterWebRTCPlugin.sharedSingleton
        val removed =
            audioProcessingController(resolvedPlugin)
                ?.capturePostProcessing
                ?.let { chain ->
                    chain.removeProcessor(holder.processor)
                    true
                } == true
        if (!removed) {
            Log.w(
                TAG,
                "detach: capture processor not removed for trackId=$trackId " +
                    "(plugin=${resolvedPlugin != null})",
            )
        }
        holder.release()
        if (removeFromMap) {
            processors.remove(trackId)
        }
    }

    private fun lookupLocalTrack(trackId: String): LookupResult {
        val plugin = findWebRtcPlugin(trackId) ?: return LookupResult.NotReady
        val raw = try {
            plugin.getLocalTrack(trackId)
        } catch (npe: NullPointerException) {
            Log.w(
                TAG,
                "lookup: getLocalTrack($trackId) NPE (handler not wired): ${npe.message}",
            )
            return LookupResult.NotReady
        }
        if (raw == null) {
            Log.w(TAG, "lookup: getLocalTrack($trackId) returned null")
            return LookupResult.NotFound
        }
        val local = raw as? LocalAudioTrack
        if (local == null) {
            Log.w(TAG, "lookup: getLocalTrack($trackId) returned ${raw.javaClass.name}")
            return LookupResult.NotFound
        }
        return LookupResult.Found(local)
    }

    private fun findWebRtcPlugin(trackId: String): FlutterWebRTCPlugin? {
        val viaRegistry: FlutterWebRTCPlugin? = try {
            engine.plugins.get(FlutterWebRTCPlugin::class.java) as? FlutterWebRTCPlugin
        } catch (t: Throwable) {
            Log.w(TAG, "lookup: engine.plugins.get threw: ${t.message}")
            null
        }
        if (viaRegistry != null) {
            return viaRegistry
        }
        val viaStatic = FlutterWebRTCPlugin.sharedSingleton
        if (viaStatic != null) {
            Log.w(TAG, "lookup: using sharedSingleton for trackId=$trackId")
            return viaStatic
        }
        Log.w(TAG, "lookup: FlutterWebRTCPlugin unavailable for trackId=$trackId")
        return null
    }

    private fun audioProcessingController(
        plugin: FlutterWebRTCPlugin?,
    ): AudioProcessingController? {
        if (plugin == null) {
            return null
        }
        return try {
            plugin.getAudioProcessingController()
        } catch (npe: NullPointerException) {
            Log.w(TAG, "getAudioProcessingController NPE: ${npe.message}")
            null
        }
    }

    private fun describeTrack(track: LocalAudioTrack): String {
        val id = runCatching { track.id() }.getOrElse { "?" }
        val kind = runCatching { track.kind() }.getOrElse { "?" }
        val enabled = runCatching { track.enabled() }.getOrNull()
        return "LocalAudioTrack(id=$id kind=$kind enabled=$enabled)"
    }

    private class AudioProcessingAdapterHolder(
        kind: DenoiseKind,
        appContext: android.content.Context,
        deepFilterAttenLimDb: Float = MeetAudioDeepFilterProcessor.DEFAULT_ATTEN_LIM_DB,
    ) {
        val processor: MeetAudioCaptureProcessor =
            when (kind) {
                DenoiseKind.RNNOISE -> MeetAudioRnnoiseProcessor()
                DenoiseKind.DEEPFILTER,
                DenoiseKind.DEEPFILTER2,
                -> MeetAudioDeepFilterProcessor(appContext, deepFilterAttenLimDb)
                DenoiseKind.DTLN_RS -> MeetAudioDtlnRsProcessor()
            }

        fun setEnabled(enabled: Boolean) {
            processor.setEnabled(enabled)
        }

        fun applyDeepFilterAttenLim(attenLimDb: Float) {
            (processor as? MeetAudioDeepFilterProcessor)?.setAttenLimDb(attenLimDb)
        }

        fun release() {
            processor.release()
        }
    }

    private sealed interface LookupResult {
        data object NotReady : LookupResult
        data object NotFound : LookupResult
        data class Found(val track: LocalAudioTrack) : LookupResult
    }

    /** Matches Flutter [kDebugMode] / `android:debuggable` (false for release & store builds). */
    private fun isDebuggableBuild(): Boolean =
        (appContext.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0

    companion object {
        const val CHANNEL_NAME = "me.proton.meet/denoise"
        private const val TAG = "AudioDenoiseChannel"
    }
}
