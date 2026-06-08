/*
 * Copyright (c) 2026 Proton AG
 * This file is part of Proton AG and Proton Meet.
 */

package proton.android.meet.meeting

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Flutter method channel for Android ongoing meeting calls. */
class MeetCallChannel(
    private val context: Context,
    flutterEngine: FlutterEngine,
) : MethodChannel.MethodCallHandler {

    private val channel: MethodChannel =
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MeetCallController.METHOD_CHANNEL,
        )

    init {
        channel.setMethodCallHandler(this)
        MeetCallController.attach(context, channel)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        MeetCallController.detach()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "init" -> {
                val ok = MeetCallController.ensureInitialized(context)
                result.success(ok)
            }
            "startMeeting" -> {
                if (!MeetCallController.hasPostNotificationsPermission(context)) {
                    result.success(false)
                    return
                }
                val callId = call.argument<String>("callId") ?: ""
                val roomName = call.argument<String>("roomName") ?: ""
                val hasCamera = call.argument<Boolean>("hasCamera") ?: false
                val hasMic = call.argument<Boolean>("hasMic") ?: false
                if (callId.isBlank()) {
                    result.success(false)
                    return
                }
                val ok =
                    MeetCallController.startMeeting(
                        context,
                        callId,
                        roomName,
                        hasCamera,
                        hasMic,
                    )
                result.success(ok)
            }
            "stopMeeting" -> {
                MeetCallController.stopMeeting(context)
                result.success(null)
            }
            "startScreenShare" -> {
                if (!MeetCallController.hasPostNotificationsPermission(context)) {
                    result.success(false)
                    return
                }
                val ok = MeetCallController.startScreenShare(context)
                result.success(ok)
            }
            "stopScreenShare" -> {
                MeetCallController.stopScreenShare(context)
                result.success(null)
            }
            "hasActiveMeetingCall" -> {
                result.success(MeetCallController.hasActiveMeetingCall())
            }
            else -> result.notImplemented()
        }
    }

    companion object {
        private var instance: MeetCallChannel? = null

        fun register(context: Context, flutterEngine: FlutterEngine): MeetCallChannel {
            instance?.dispose()
            val channel = MeetCallChannel(context, flutterEngine)
            instance = channel
            return channel
        }

        fun dispose() {
            instance?.dispose()
            instance = null
        }
    }
}
