package com.proton.proton_screen_recorder

import android.app.Activity
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.result.ActivityResult
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.LifecycleOwner
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Android screen recording via MediaProjection + MediaCodec/MediaMuxer. */
class ProtonScreenRecorderPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler,
    ActivityAware {

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private lateinit var appContext: android.content.Context

    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var projectionLauncher: ActivityResultLauncher<Intent>? = null
    private var eventSink: EventChannel.EventSink? = null
    private var pendingStartResult: MethodChannel.Result? = null
    private var pendingStartArgs: StartArgs? = null
    private var resumeObserver: LifecycleEventObserver? = null

    private val mainHandler = Handler(Looper.getMainLooper())
    private val recorder by lazy { AndroidScreenRecorder(appContext) }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        methodChannel = MethodChannel(binding.binaryMessenger, "screen_recording")
        methodChannel.setMethodCallHandler(this)
        eventChannel = EventChannel(binding.binaryMessenger, "screen_recording/events")
        eventChannel.setStreamHandler(this)

        recorder.callback =
            object : AndroidScreenRecorder.Callback {
                override fun onInterrupted() {
                    emitEvent("recordingInterrupted")
                }
            }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        recorder.callback = null
        clearResumeObserver()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        val componentActivity = binding.activity as? ComponentActivity
        if (componentActivity == null) {
            Log.e(TAG, "Activity is not a ComponentActivity; screen recording unavailable")
            return
        }
        projectionLauncher =
            componentActivity.registerForActivityResult(
                ActivityResultContracts.StartActivityForResult(),
            ) { activityResult: ActivityResult ->
                handleProjectionConsent(activityResult.resultCode, activityResult.data)
            }
    }

    override fun onDetachedFromActivityForConfigChanges() {
        detachActivity()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        detachActivity()
    }

    private fun detachActivity() {
        clearResumeObserver()
        projectionLauncher = null
        activityBinding = null
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> result.success(true)
            "isRecording" -> result.success(recorder.isRecording())
            "startRecording" -> handleStartRecording(call, result)
            "stopRecording" -> handleStopRecording(result)
            "publishToDownloads" -> handlePublishToDownloads(call, result)
            else -> result.notImplemented()
        }
    }

    private fun handleStartRecording(call: MethodCall, result: MethodChannel.Result) {
        val activity = activity
        val launcher = projectionLauncher
        if (activity == null || launcher == null) {
            result.error("NO_ACTIVITY", "Activity is not available", null)
            return
        }

        val arguments = call.arguments as? Map<*, *>
        val outputPath = arguments?.get("outputPath") as? String
        if (outputPath.isNullOrBlank()) {
            result.error(
                "INVALID_ARGUMENT",
                "outputPath is required on Android",
                null,
            )
            return
        }

        val enableMicrophone = arguments["enableMicrophone"] as? Boolean ?: true
        val args = StartArgs(outputPath = outputPath, enableMicrophone = enableMicrophone)

        if (recorder.isRecording()) {
            result.error("RECORDING_ERROR", "Recording is already in progress", null)
            return
        }

        pendingStartResult = result
        pendingStartArgs = args
        runCatching {
            launcher.launch(recorder.requestProjection(activity))
        }.onFailure { error ->
            clearPendingStart()
            result.error(
                "RECORDING_ERROR",
                error.message ?: "Failed to request screen capture",
                null,
            )
        }
    }

    private fun handleProjectionConsent(resultCode: Int, data: Intent?) {
        val startResult = pendingStartResult
        val startArgs = pendingStartArgs
        if (startResult == null || startArgs == null) {
            return
        }

        if (resultCode != Activity.RESULT_OK || data == null) {
            clearPendingStart()
            startResult.error(
                "PERMISSION_DENIED",
                "Screen capture permission denied",
                null,
            )
            return
        }

        runCatching {
            recorder.onProjectionResult(resultCode, data)
        }.onFailure { error ->
            Log.e(TAG, "MediaProjection consent handling failed", error)
            recorder.releaseProjection()
            clearPendingStart()
            startResult.error(
                "RECORDING_ERROR",
                recordingStartErrorMessage(error),
                null,
            )
            return
        }

        val currentActivity = activity
        if (currentActivity == null) {
            recorder.releaseProjection()
            clearPendingStart()
            startResult.error("NO_ACTIVITY", "Activity is not available", null)
            return
        }

        // MediaProjection capture must start once the activity is foreground again.
        beginRecordingWhenResumed(currentActivity)
    }

    private fun beginRecordingWhenResumed(activity: Activity) {
        clearResumeObserver()

        if (activity is LifecycleOwner &&
            activity.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)
        ) {
            launchRecording(activity)
            return
        }

        if (activity !is LifecycleOwner) {
            mainHandler.post { launchRecording(activity) }
            return
        }

        val observer =
            LifecycleEventObserver { _, event ->
                when (event) {
                    Lifecycle.Event.ON_RESUME -> {
                        clearResumeObserver()
                        launchRecording(activity)
                    }
                    Lifecycle.Event.ON_DESTROY -> {
                        clearResumeObserver()
                        val result = pendingStartResult
                        recorder.releaseProjection()
                        clearPendingStart()
                        result?.error(
                            "NO_ACTIVITY",
                            "Activity destroyed before recording could start",
                            null,
                        )
                    }
                    else -> Unit
                }
            }
        resumeObserver = observer
        activity.lifecycle.addObserver(observer)
    }

    private fun launchRecording(activity: Activity) {
        val startResult = pendingStartResult
        val startArgs = pendingStartArgs
        clearPendingStart()
        if (startResult == null || startArgs == null) {
            return
        }

        runCatching {
            recorder.startRecording(
                activity = activity,
                outputPath = startArgs.outputPath,
                enableMicrophone = startArgs.enableMicrophone,
            )
            startResult.success(true)
        }.onFailure { error ->
            Log.e(TAG, "startRecording failed", error)
            recorder.releaseProjection()
            startResult.error(
                "RECORDING_ERROR",
                recordingStartErrorMessage(error),
                null,
            )
        }
    }

    private fun handleStopRecording(result: MethodChannel.Result) {
        if (!recorder.isRecording()) {
            recorder.releaseProjection()
            result.success(null)
            return
        }
        runCatching {
            val path = recorder.stopRecording()
            val file = java.io.File(path)
            if (file.exists() && file.length() > 0) {
                result.success(path)
            } else {
                result.error("RECORDING_ERROR", "No recording data was captured", null)
            }
        }.onFailure { error ->
            Log.e(TAG, "stopRecording failed", error)
            result.error(
                "RECORDING_ERROR",
                error.message ?: "Failed to stop recording",
                null,
            )
        }
    }

    private fun handlePublishToDownloads(call: MethodCall, result: MethodChannel.Result) {
        val arguments = call.arguments as? Map<*, *>
        val sourcePath = arguments?.get("sourcePath") as? String
        val displayName = arguments?.get("displayName") as? String
        if (sourcePath.isNullOrBlank() || displayName.isNullOrBlank()) {
            result.error("INVALID_ARGUMENT", "sourcePath and displayName are required", null)
            return
        }

        val publishedPath =
            RecordingMediaStore.publishToDownloads(
                appContext,
                java.io.File(sourcePath),
                displayName,
            )
        if (publishedPath == null) {
            result.error(
                "PUBLISH_FAILED",
                "Could not copy recording to Downloads/Proton Meet",
                null,
            )
            return
        }
        result.success(publishedPath)
    }

    private fun clearPendingStart() {
        pendingStartResult = null
        pendingStartArgs = null
    }

    private fun clearResumeObserver() {
        val observer = resumeObserver ?: return
        (activity as? LifecycleOwner)?.lifecycle?.removeObserver(observer)
        resumeObserver = null
    }

    private fun recordingStartErrorMessage(error: Throwable): String {
        if (error is SecurityException) {
            return "Screen capture requires an active meeting notification. Stay in the call and try again."
        }
        return error.message ?: "Failed to start recording"
    }

    private fun emitEvent(name: String) {
        val sink = eventSink ?: return
        mainHandler.post { sink.success(name) }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private data class StartArgs(
        val outputPath: String,
        val enableMicrophone: Boolean,
    )

    companion object {
        private const val TAG = "ProtonScreenRecorder"
    }
}
