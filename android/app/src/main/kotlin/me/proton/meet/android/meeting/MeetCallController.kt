/*
 * Copyright (c) 2026 Proton AG
 * This file is part of Proton AG and Proton Meet.
 */

package proton.android.meet.meeting

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.util.Log
import android.widget.RemoteViews
import androidx.core.app.NotificationCompat
import androidx.core.app.Person
import androidx.core.content.ContextCompat
import androidx.core.graphics.drawable.IconCompat
import io.flutter.plugin.common.MethodChannel
import proton.android.meet.R
import proton.android.meet.activity.MainActivity

/** Coordinates meeting foreground service, CallStyle / custom notification, and Flutter. */
object MeetCallController {

    private const val TAG = "MeetCallController"
    const val CHANNEL_ID = "meet_ongoing_call_v1"
    const val NOTIFICATION_ID = 1001
    const val METHOD_CHANNEL = "proton.android.meet/meeting_call"

    const val ACTION_RETURN_TO_CALL = "proton.android.meet.RETURN_TO_CALL"
    const val ACTION_END_CALL = "proton.android.meet.END_CALL"

    private var methodChannel: MethodChannel? = null
    private var appContext: Context? = null

    @Volatile private var isMeetingActive: Boolean = false

    @Volatile private var roomName: String = ""

    @Volatile private var callId: String = ""

    @Volatile private var hasCameraPermission: Boolean = false

    @Volatile private var hasMicPermission: Boolean = false

    @Volatile private var isScreenSharing: Boolean = false

    fun attach(context: Context, channel: MethodChannel) {
        appContext = context.applicationContext
        methodChannel = channel
    }

    fun detach() {
        methodChannel = null
    }

    fun ensureInitialized(context: Context): Boolean {
        val ctx = context.applicationContext
        appContext = ctx
        ensureNotificationChannel(ctx)
        return true
    }

    fun startMeeting(
            context: Context,
            callId: String,
            roomName: String,
            hasCamera: Boolean,
            hasMic: Boolean,
    ): Boolean {
        val ctx = context.applicationContext
        appContext = ctx
        this.callId = callId
        this.roomName = roomName.ifBlank { ctx.getString(R.string.meet_call_default_room) }
        hasCameraPermission = hasCamera
        hasMicPermission = hasMic
        isScreenSharing = false

        ensureInitialized(ctx)

        if (!hasPostNotificationsPermission(ctx)) {
            Log.w(TAG, "startMeeting: POST_NOTIFICATIONS not granted")
            return false
        }

        if (!canPromoteToForeground(MeetCallForegroundService.FgsMode.MEETING)) {
            Log.w(
                    TAG,
                    "startMeeting: no applicable foreground service type " +
                            "(camera/microphone permission required)",
            )
            return false
        }

        isMeetingActive = true
        if (isScreenSharing) {
            // Already in screen-share mode; refresh notification only.
            MeetCallForegroundService.start(ctx, MeetCallForegroundService.FgsMode.SCREEN_SHARE)
        } else {
            MeetCallForegroundService.start(ctx, MeetCallForegroundService.FgsMode.MEETING)
        }
        Log.i(TAG, "Meeting foreground service started for $callId")
        return true
    }

    fun stopMeeting(context: Context) {
        val ctx = context.applicationContext
        isMeetingActive = false
        isScreenSharing = false
        MeetCallForegroundService.stop(ctx)
        val nm = ctx.getSystemService(NotificationManager::class.java)
        nm?.cancel(NOTIFICATION_ID)
        Log.d(TAG, "Meeting call stopped")
    }

    fun startScreenShare(context: Context): Boolean {
        val ctx = context.applicationContext
        if (!hasPostNotificationsPermission(ctx)) {
            Log.w(TAG, "startScreenShare: POST_NOTIFICATIONS not granted")
            return false
        }
        if (!canPromoteToForeground(MeetCallForegroundService.FgsMode.SCREEN_SHARE)) {
            Log.w(TAG, "startScreenShare: no applicable foreground service type")
            return false
        }
        if (!isMeetingActive) {
            Log.w(TAG, "startScreenShare: no active meeting")
            return false
        }
        isScreenSharing = true
        MeetCallForegroundService.start(ctx, MeetCallForegroundService.FgsMode.SCREEN_SHARE)
        return true
    }

    fun stopScreenShare(context: Context) {
        val ctx = context.applicationContext
        if (!isMeetingActive) {
            isScreenSharing = false
            return
        }
        isScreenSharing = false
        MeetCallForegroundService.start(ctx, MeetCallForegroundService.FgsMode.MEETING)
    }

    fun notifyReturnToCall() {
        runCatching { methodChannel?.invokeMethod("onReturnToCall", null) }
    }

    fun notifyEndCallRequested() {
        val channel = methodChannel
        if (channel == null) {
            Log.w(TAG, "notifyEndCallRequested: MethodChannel not attached")
            return
        }
        val deliver = {
            runCatching { channel.invokeMethod("onEndCallRequested", null) }
                .onFailure { Log.e(TAG, "notifyEndCallRequested failed", it) }
        }
        if (android.os.Looper.myLooper() == android.os.Looper.getMainLooper()) {
            deliver()
        } else {
            android.os.Handler(android.os.Looper.getMainLooper()).post { deliver() }
        }
    }

    fun launchMeetingActivity(context: Context) {
        val intent =
                Intent(context, MainActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                }
        context.startActivity(intent)
    }

    fun canPromoteToForeground(mode: MeetCallForegroundService.FgsMode): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return true
        }
        return foregroundServiceTypes(mode) != 0
    }

    fun foregroundServiceTypes(mode: MeetCallForegroundService.FgsMode): Int {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return 0
        }
        var types = 0
        if (hasCameraPermission) {
            types = types or ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
        }
        if (hasMicPermission) {
            types = types or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
        }
        if (mode == MeetCallForegroundService.FgsMode.SCREEN_SHARE) {
            types = types or ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
        }
        return types
    }

    fun buildNotification(
            context: Context,
            mode: MeetCallForegroundService.FgsMode = MeetCallForegroundService.FgsMode.MEETING,
    ): Notification {
        ensureNotificationChannel(context)
        val sharing = mode == MeetCallForegroundService.FgsMode.SCREEN_SHARE || isScreenSharing
        val subtitle =
                if (sharing) {
                    context.getString(R.string.meet_call_notification_sharing)
                } else {
                    context.getString(R.string.meet_call_notification_in_meeting)
                }
        val contentTitle = roomName + " | " + subtitle

        val tapSubtitle = context.getString(R.string.meet_call_notification_tap_subtitle)

        val returnIntent = buildReturnPendingIntent(context)
        val leaveIntent =
                PendingIntent.getBroadcast(
                        context,
                        1,
                        Intent(context, MeetCallActionReceiver::class.java).apply {
                            action = ACTION_END_CALL
                        },
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )

        val leaveLabel = context.getString(R.string.meet_call_action_leave_meeting)

        val builder =
                NotificationCompat.Builder(context, CHANNEL_ID)
                        .setSmallIcon(R.drawable.ic_stat_meet)
                        .setOngoing(true)
                        .setAutoCancel(false)
                        .setOnlyAlertOnce(true)
                        .setSilent(true)
                        .setCategory(NotificationCompat.CATEGORY_CALL)
                        .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                        .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                        .setContentTitle(contentTitle)
                        .setContentText(tapSubtitle)
                        .setContentIntent(returnIntent)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // API 31+: CallStyle, it is non-dismissible
            val person =
                    Person.Builder()
                            .setName(roomName)
                            .setIcon(
                                    IconCompat.createWithResource(context, R.drawable.ic_stat_meet)
                            )
                            .build()
            builder.setStyle(NotificationCompat.CallStyle.forOngoingCall(person, leaveIntent))
        } else {
            // API 30 and below: custom RemoteViews with localized red leave button
            // However, it can be dismissed by the user (though the foreground service is still
            // running)
            val remoteViews =
                    RemoteViews(context.packageName, R.layout.notification_meeting_ongoing).apply {
                        setTextViewText(R.id.notification_title, contentTitle)
                        setTextViewText(R.id.notification_subtitle, tapSubtitle)
                        setTextViewText(R.id.notification_leave, leaveLabel)
                        setOnClickPendingIntent(R.id.notification_leave, leaveIntent)
                    }
            builder.setStyle(NotificationCompat.DecoratedCustomViewStyle())
                    .setCustomContentView(remoteViews)
                    .setCustomBigContentView(remoteViews)
        }

        return builder.build()
    }

    private fun ensureNotificationChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = context.getSystemService(NotificationManager::class.java) ?: return
        val channel =
                NotificationChannel(
                                CHANNEL_ID,
                                context.getString(R.string.meet_call_channel_name),
                                NotificationManager.IMPORTANCE_DEFAULT,
                        )
                        .apply {
                            description = context.getString(R.string.meet_call_channel_description)
                            setShowBadge(false)
                            enableVibration(false)
                            setSound(null, null)
                            enableLights(false)
                            setBypassDnd(false)
                        }
        nm.createNotificationChannel(channel)
    }

    private fun buildReturnPendingIntent(context: Context): PendingIntent {
        return PendingIntent.getActivity(
                context,
                0,
                Intent(context, MainActivity::class.java).apply {
                    action = ACTION_RETURN_TO_CALL
                    addFlags(
                            Intent.FLAG_ACTIVITY_NEW_TASK or
                                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                                    Intent.FLAG_ACTIVITY_CLEAR_TOP,
                    )
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    fun hasActiveMeetingCall(): Boolean = isMeetingActive

    fun displayRoomName(): String = roomName

    fun hasPostNotificationsPermission(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return true
        }
        return ContextCompat.checkSelfPermission(
                context,
                android.Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
    }
}
