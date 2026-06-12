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

import android.content.Context
import android.util.Log
import com.cloudwebrtc.webrtc.FlutterWebRTCPlugin
import com.cloudwebrtc.webrtc.video.LocalVideoTrack
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ConcurrentHashMap

/**
 * Flutter method channel ↔ flutter_webrtc local video track.
 *
 * Stack:
 *   BackgroundBlurChannel — attach / detach / config (this file)
 *   MeetBackgroundBlurFrameProcessor — WebRTC frame callback
 *   MeetBackgroundBlurMediaPipeEngine — segmentation + bitmap blur composite
 *
 * One shared [MeetBackgroundBlurFrameProcessor] is reused across attach cycles; detach disables
 * native processing without tearing down the segmenter (mirrors Darwin `BackgroundBlurBridge`).
 */
class BackgroundBlurChannel(
        binding: FlutterPlugin.FlutterPluginBinding,
) : MethodChannel(binding.binaryMessenger, CHANNEL_NAME) {

    private val engine = binding.flutterEngine
    private val context: Context = binding.applicationContext

    private val processors = ConcurrentHashMap<String, MeetBackgroundBlurFrameProcessor>()
    private var sharedProcessor: MeetBackgroundBlurFrameProcessor? = null
    private var attachedTrackId: String? = null
    // Matches Dart BackgroundBlurConfig defaults until setBackgroundBlurConfig runs.
    private var pendingBlurSigma: Float = 128f
    private var pendingObscureOpacity: Float = 0.1f
    private var pendingReplacementPath: String? = null
    private var pendingReplacementBytes: ByteArray? = null

    init {
        Log.i(
                "ProtonVideoEffects",
                "$TAG: constructed on channel=$CHANNEL_NAME engine=${System.identityHashCode(engine)} " +
                        "context=${context.javaClass.simpleName}@${System.identityHashCode(context)}",
        )
    }

    fun init() {
        Log.i("ProtonVideoEffects", "$TAG: handler installed on channel=$CHANNEL_NAME")
        setMethodCallHandler { call: MethodCall, result ->
            Log.d(
                    "ProtonVideoEffects",
                    "$TAG: ${call.method} args=${formatArgs(call.arguments)}",
            )
            try {
                when (call.method) {
                    "isImplementationReady" -> {
                        Log.i("ProtonVideoEffects", "$TAG: isImplementationReady -> true")
                        result.success(true)
                    }
                    "setBackgroundBlurConfig" -> setBackgroundBlurConfig(call, result)
                    "setReplacementBackgroundImage" -> setReplacementBackgroundImage(call, result)
                    "clearReplacementBackground" -> clearReplacementBackground(result)
                    "setSegmentationModel" -> setSegmentationModel(call, result)
                    "getSegmentationModel" -> getSegmentationModel(result)
                    "attach" -> attach(call, result)
                    "detach" -> detach(call, result)
                    else -> {
                        Log.w(
                                "ProtonVideoEffects",
                                "$TAG: unknown method=${call.method}, returning notImplemented"
                        )
                        result.notImplemented()
                    }
                }
            } catch (e: Throwable) {
                Log.e("ProtonVideoEffects", "$TAG: method handler failed", e)
                result.error("video_effects", e.message, null)
            }
        }
    }

    private fun setBackgroundBlurConfig(call: MethodCall, result: MethodChannel.Result) {
        storePendingBlurConfig(call)
        storePendingReplacement(call)
        allProcessors().forEach { proc ->
            proc.applyBlurConfig(pendingBlurSigma, pendingObscureOpacity)
            applyPendingReplacement(proc)
        }
        result.success(null)
    }

    private fun setReplacementBackgroundImage(call: MethodCall, result: MethodChannel.Result) {
        storePendingReplacement(call)
        val targets = allProcessors()
        if (targets.isEmpty()) {
            result.success(null)
            return
        }
        val ok = targets.all { applyPendingReplacement(it) }
        if (ok) {
            result.success(null)
        } else {
            result.error("IMAGE", "Failed to decode replacement image", null)
        }
    }

    private fun setSegmentationModel(call: MethodCall, result: MethodChannel.Result) {
        val model = call.argument<String>("model")
        if (model == "vision") {
            result.error("UNSUPPORTED", "Apple Vision segmentation is Apple platforms only", null)
            return
        }
        if (model != "single" && model != "landscape" && model != "multiclass") {
            result.error("ARGS", "model must be single, landscape, multiclass, or vision (iOS)", null)
            return
        }
        sharedProcessor?.setSegmentationModelPreference(model)
        processors.values.forEach { it.setSegmentationModelPreference(model) }
        result.success(null)
    }

    private fun getSegmentationModel(result: MethodChannel.Result) {
        val info = sharedProcessor?.segmentationModelDebugInfo()
            ?: processors.values.firstOrNull()?.segmentationModelDebugInfo()
            ?: mapOf(
                "model" to "none",
                "backend" to "none",
                "forced" to false,
                "supported" to true,
            )
        result.success(info)
    }

    private fun clearReplacementBackground(result: MethodChannel.Result) {
        pendingReplacementPath = null
        pendingReplacementBytes = null
        sharedProcessor?.clearReplacementBackground()
        processors.values.forEach { it.clearReplacementBackground() }
        result.success(null)
    }

    private fun storePendingBlurConfig(call: MethodCall) {
        call.argument<Number>("blurSigma")?.toFloat()?.let { pendingBlurSigma = it }
        call.argument<Number>("backgroundObscureOpacity")?.toFloat()?.let {
            pendingObscureOpacity = it
        }
    }

    private fun allProcessors(): List<MeetBackgroundBlurFrameProcessor> {
        val list = processors.values.toMutableList()
        sharedProcessor?.let { shared ->
            if (!list.contains(shared)) {
                list.add(shared)
            }
        }
        return list
    }

    private fun applyPendingBlurConfig(proc: MeetBackgroundBlurFrameProcessor) {
        proc.applyBlurConfig(pendingBlurSigma, pendingObscureOpacity)
    }

    private fun storePendingReplacement(call: MethodCall) {
        if (call.argument<String>("backgroundMode") == "blur") {
            pendingReplacementPath = null
            pendingReplacementBytes = null
            return
        }
        call.argument<String>("replacementImagePath")?.takeIf { it.isNotEmpty() }?.let {
            pendingReplacementPath = it
            pendingReplacementBytes = null
            return
        }
        call.argument<String>("filePath")?.takeIf { it.isNotEmpty() }?.let {
            pendingReplacementPath = it
            pendingReplacementBytes = null
            return
        }
        @Suppress("UNCHECKED_CAST")
        (call.argument<ByteArray>("imageBytes"))?.takeIf { it.isNotEmpty() }?.let {
            pendingReplacementBytes = it
            pendingReplacementPath = null
        }
    }

    private fun applyPendingReplacement(proc: MeetBackgroundBlurFrameProcessor): Boolean {
        pendingReplacementBytes?.let {
            return proc.setReplacementBackgroundImageBytes(it)
        }
        pendingReplacementPath?.let {
            return proc.setReplacementBackgroundImagePath(it)
        }
        proc.clearReplacementBackground()
        return true
    }

    private fun attach(call: MethodCall, result: MethodChannel.Result) {
        val trackId = call.argument<String>("trackId")
        Log.i(
                "ProtonVideoEffects",
                "$TAG.attach: trackId=$trackId currentProcessors=${snapshotProcessorKeys()}",
        )
        if (trackId.isNullOrEmpty()) {
            Log.w("ProtonVideoEffects", "$TAG.attach: missing trackId -> error ARGS")
            result.error("ARGS", "trackId required", null)
            return
        }
        when (val local = lookupLocalTrack(trackId)) {
            LookupResult.NotReady -> {
                Log.w(
                        "ProtonVideoEffects",
                        "$TAG.attach: WebRTC plugin not ready for trackId=$trackId -> error WEBRTC_NOT_READY",
                )
                result.error(
                        "WEBRTC_NOT_READY",
                        "FlutterWebRTCPlugin handler not initialized yet — retry after the engine settles",
                        null,
                )
                return
            }
            LookupResult.NotFound -> {
                Log.w(
                        "ProtonVideoEffects",
                        "$TAG.attach: track not found for id=$trackId -> error TRACK",
                )
                result.error("TRACK", "Local video track not found for id=$trackId", null)
                return
            }
            is LookupResult.Found -> {
                Log.i(
                        "ProtonVideoEffects",
                        "$TAG.attach: track found ${describeTrack(local.track)}",
                )
                if (attachedTrackId == trackId) {
                    val existing = processors[trackId] ?: sharedProcessor
                    if (existing != null) {
                        existing.setEnabled(true)
                        storePendingBlurConfig(call)
                        storePendingReplacement(call)
                        applyPendingBlurConfig(existing)
                        applyPendingReplacement(existing)
                        processors[trackId] = existing
                        Log.i(
                                "ProtonVideoEffects",
                                "$TAG.attach: idempotent re-attach trackId=$trackId " +
                                        "processor=${System.identityHashCode(existing)}",
                        )
                        result.success(null)
                        return
                    }
                }
                clearOtherProcessors(keepTrackId = trackId)
                processors[trackId]?.let { existing ->
                    storePendingBlurConfig(call)
                    storePendingReplacement(call)
                    applyPendingBlurConfig(existing)
                    applyPendingReplacement(existing)
                    Log.i(
                            "ProtonVideoEffects",
                            "$TAG.attach: processor already in map for trackId=$trackId, refreshed config",
                    )
                    result.success(null)
                    return
                }

                /// we can preinit MeetBackgroundBlurFrameProcessor somewhere else early,
                ///  but need to make sure it is safe not crash the code
                val proc =
                        sharedProcessor
                                ?: MeetBackgroundBlurFrameProcessor(context).also {
                                    sharedProcessor = it
                                    Log.i(
                                            "ProtonVideoEffects",
                                            "$TAG.attach: created shared processor=${System.identityHashCode(it)}",
                                    )
                                }
                proc.setEnabled(true)
                storePendingBlurConfig(call)
                storePendingReplacement(call)
                applyPendingBlurConfig(proc)
                applyPendingReplacement(proc)
                processors[trackId] = proc
                local.track.addProcessor(proc)
                attachedTrackId = trackId
                Log.i(
                        "ProtonVideoEffects",
                        "$TAG.attach: processor installed for trackId=$trackId " +
                                "processor=${System.identityHashCode(proc)} activeProcessors=${snapshotProcessorKeys()}",
                )
                result.success(null)
            }
        }
    }

    private fun detach(call: MethodCall, result: MethodChannel.Result) {
        val trackId = call.argument<String>("trackId")
        Log.i(
                "ProtonVideoEffects",
                "$TAG.detach: trackId=$trackId currentProcessors=${snapshotProcessorKeys()}",
        )
        if (trackId.isNullOrEmpty()) {
            Log.w("ProtonVideoEffects", "$TAG.detach: missing trackId -> error ARGS")
            result.error("ARGS", "trackId required", null)
            return
        }
        val proc = processors.remove(trackId)
        if (proc != null) {
            Log.i(
                    "ProtonVideoEffects",
                    "$TAG.detach: removed processor=${System.identityHashCode(proc)} from map for trackId=$trackId",
            )
            when (val lookup = lookupLocalTrack(trackId)) {
                is LookupResult.Found -> {
                    lookup.track.removeProcessor(proc)
                    Log.i(
                            "ProtonVideoEffects",
                            "$TAG.detach: detached processor from track ${describeTrack(lookup.track)}",
                    )
                }
                LookupResult.NotReady ->
                        Log.w(
                                "ProtonVideoEffects",
                                "$TAG.detach: WebRTC plugin not ready for trackId=$trackId, disabled processor anyway",
                        )
                LookupResult.NotFound ->
                        Log.w(
                                "ProtonVideoEffects",
                                "$TAG.detach: track gone for trackId=$trackId, disabled processor anyway",
                        )
            }
            Log.i(
                    "ProtonVideoEffects",
                    "$TAG.detach: disabled processor for trackId=$trackId remaining=${snapshotProcessorKeys()} " +
                            "shared=${sharedProcessor?.let { System.identityHashCode(it) } ?: "null"}",
            )
        } else {
            Log.i(
                    "ProtonVideoEffects",
                    "$TAG.detach: no processor for trackId=$trackId, no-op (active=${snapshotProcessorKeys()})",
            )
        }
        if (attachedTrackId == trackId) {
            attachedTrackId = null
        }
        result.success(null)
    }

    /** Tear down the shared processor when the Flutter engine is destroyed. */
    fun dispose() {
        for (id in processors.keys.toList()) {
            val proc = processors.remove(id) ?: continue
            when (val lookup = lookupLocalTrack(id)) {
                is LookupResult.Found -> lookup.track.removeProcessor(proc)
                else -> Unit
            }
            proc.setEnabled(false)
        }
        attachedTrackId = null
        sharedProcessor?.release()
        sharedProcessor = null
        Log.i("ProtonVideoEffects", "$TAG.dispose: shared processor released")
    }

    private fun clearOtherProcessors(keepTrackId: String) {
        val toRemove = processors.keys.filter { it != keepTrackId }
        if (toRemove.isEmpty()) return
        Log.i("ProtonVideoEffects", "$TAG.clearOthers: keep=$keepTrackId removing=$toRemove")
        for (id in toRemove) {
            val proc = processors.remove(id) ?: continue
            proc.setEnabled(false)
            when (val lookup = lookupLocalTrack(id)) {
                is LookupResult.Found -> {
                    lookup.track.removeProcessor(proc)
                    Log.i(
                            "ProtonVideoEffects",
                            "$TAG.clearOthers: detached processor from old track ${describeTrack(lookup.track)}",
                    )
                }
                LookupResult.NotReady ->
                        Log.w(
                                "ProtonVideoEffects",
                                "$TAG.clearOthers: WebRTC not ready while removing old trackId=$id",
                        )
                LookupResult.NotFound ->
                        Log.w(
                                "ProtonVideoEffects",
                                "$TAG.clearOthers: old track missing for trackId=$id",
                        )
            }
        }
    }

    /**
     * Safely fetches the local video track from `flutter_webrtc`, distinguishing three states:
     * 1. Plugin not yet wired into this engine (hot reload / activity recreation window) or its
     * ```
     *      private `methodCallHandler` not yet attached.
     * ```
     * 2. Plugin ready but no track with the requested id.
     * 3. Track found.
     *
     * Resolution order mirrors iOS' `[FlutterWebRTCPlugin sharedSingleton]` pattern but prefers the
     * per-engine plugin registry over the global static, which is safer across activity recreation:
     * a. `engine.plugins.get(FlutterWebRTCPlugin)` — guaranteed to point at the plugin instance
     * ```
     *      attached to *this* `FlutterEngine`, set after `GeneratedPluginRegistrant.registerWith`.
     * ```
     * b. Fallback to `FlutterWebRTCPlugin.sharedSingleton` for compatibility with older releases
     * ```
     *      and edge cases where the plugin lives outside the engine registry.
     * ```
     * `FlutterWebRTCPlugin.getLocalTrack` can still throw NPE if `methodCallHandler` is not yet
     * wired (see `FlutterWebRTCPlugin.java:65`). Catching it here keeps the stack trace out of the
     * log and lets Flutter retry on its own cadence.
     */
    private fun lookupLocalTrack(trackId: String): LookupResult {
        val plugin = findWebRtcPlugin(trackId) ?: return LookupResult.NotReady
        val raw =
                try {
                    plugin.getLocalTrack(trackId)
                } catch (npe: NullPointerException) {
                    Log.w(
                            "ProtonVideoEffects",
                            "$TAG.lookup: FlutterWebRTCPlugin.getLocalTrack($trackId) threw NPE (handler not wired): ${npe.message}",
                    )
                    return LookupResult.NotReady
                }
        if (raw == null) {
            Log.w("ProtonVideoEffects", "$TAG.lookup: getLocalTrack($trackId) returned null")
            return LookupResult.NotFound
        }
        val local = raw as? LocalVideoTrack
        if (local == null) {
            Log.w(
                    "ProtonVideoEffects",
                    "$TAG.lookup: getLocalTrack($trackId) returned ${raw.javaClass.name}, not LocalVideoTrack",
            )
            return LookupResult.NotFound
        }
        Log.i(
                "ProtonVideoEffects",
                "$TAG.lookup: resolved trackId=$trackId -> ${describeTrack(local)}",
        )
        return LookupResult.Found(local)
    }

    /**
     * Locate the `FlutterWebRTCPlugin` instance attached to this engine. Returns `null` and logs
     * the reason if neither lookup path succeeds — caller treats that as `NotReady`.
     */
    private fun findWebRtcPlugin(trackId: String): FlutterWebRTCPlugin? {
        val viaRegistry: FlutterWebRTCPlugin? =
                try {
                    engine.plugins.get(FlutterWebRTCPlugin::class.java) as? FlutterWebRTCPlugin
                } catch (t: Throwable) {
                    Log.w(
                            "ProtonVideoEffects",
                            "$TAG.lookup: engine.plugins.get(FlutterWebRTCPlugin) threw: ${t.message}",
                    )
                    null
                }
        if (viaRegistry != null) {
            Log.i(
                    "ProtonVideoEffects",
                    "$TAG.lookup: plugin via engine.plugins=${System.identityHashCode(viaRegistry)} for trackId=$trackId",
            )
            return viaRegistry
        }
        val viaStatic = FlutterWebRTCPlugin.sharedSingleton
        if (viaStatic != null) {
            Log.w(
                    "ProtonVideoEffects",
                    "$TAG.lookup: plugin not in engine.plugins registry, falling back to " +
                            "sharedSingleton=${System.identityHashCode(viaStatic)} for trackId=$trackId",
            )
            return viaStatic
        }
        Log.w(
                "ProtonVideoEffects",
                "$TAG.lookup: FlutterWebRTCPlugin unavailable (engine.plugins.get=null, sharedSingleton=null) " +
                        "for trackId=$trackId",
        )
        return null
    }

    private fun snapshotProcessorKeys(): String =
            processors.keys.joinToString(prefix = "[", postfix = "]").let {
                "$it size=${processors.size}"
            }

    private fun describeTrack(track: LocalVideoTrack): String {
        // `LocalVideoTrack` is flutter_webrtc's wrapper; it exposes id/kind/enabled directly but
        // `state()` lives on the inner `track.track` (org.webrtc.MediaStreamTrack). Pull each value
        // defensively because the native handle may have been disposed between lookup and log.
        val id = runCatching { track.id() }.getOrElse { "?" }
        val kind = runCatching { track.kind() }.getOrElse { "?" }
        val enabled = runCatching { track.enabled() }.getOrNull()
        val state = runCatching { track.track?.state()?.toString() }.getOrNull() ?: "?"
        return "LocalVideoTrack(id=$id kind=$kind enabled=$enabled state=$state hash=${System.identityHashCode(track)})"
    }

    private fun formatArgs(args: Any?): String =
            when (args) {
                null -> "null"
                is Map<*, *> ->
                        args.entries.joinToString(prefix = "{", postfix = "}") { (k, v) -> "$k=$v" }
                else -> args.toString()
            }

    private sealed interface LookupResult {
        data object NotReady : LookupResult
        data object NotFound : LookupResult
        data class Found(val track: LocalVideoTrack) : LookupResult
    }

    private companion object {
        const val TAG = "BackgroundBlurChannel"
        const val CHANNEL_NAME = "me.proton.meet/video_effects"
        // Future: custom background image — separate attachCustomBackground handler.
    }
}
