/*
 * Copyright (c) 2026 Proton AG
 * This file is part of Proton AG and Proton Meet.
 */

package proton.android.meet.meeting

import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log

/** Foreground service for ongoing meetings with CallStyle notification and MediaSession. */
class MeetCallForegroundService : Service() {

    private val tag = "MeetCallForegroundService"

    private var mediaSession: MeetCallMediaSession? = null
    private var currentMode: FgsMode = FgsMode.MEETING

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        mediaSession = MeetCallMediaSession(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        currentMode = parseMode(intent?.getStringExtra(EXTRA_MODE))
        mediaSession?.activate(MeetCallController.displayRoomName())
        promoteToForeground(currentMode)
        // Do not restart after the process is killed; avoids a stale CallStyle notification.
        return START_NOT_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        Log.i(tag, "onTaskRemoved: stopping meeting foreground service")
        MeetCallController.stopMeeting(applicationContext)
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        if (MeetCallController.hasActiveMeetingCall()) {
            Log.i(tag, "onDestroy: clearing active meeting notification")
            MeetCallController.stopMeeting(applicationContext)
        }
        mediaSession?.release()
        mediaSession = null
        super.onDestroy()
    }

    private fun promoteToForeground(mode: FgsMode) {
        if (!MeetCallController.hasPostNotificationsPermission(this)) {
            Log.e(tag, "promoteToForeground: POST_NOTIFICATIONS not granted")
            stopSelf()
            return
        }
        try {
            val notification = MeetCallController.buildNotification(this, mode)
            val serviceTypes = MeetCallController.foregroundServiceTypes(mode)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    MeetCallController.NOTIFICATION_ID,
                    notification,
                    serviceTypes,
                )
            } else {
                startForeground(MeetCallController.NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            Log.e(tag, "promoteToForeground failed", e)
            stopSelf()
        }
    }

    private fun parseMode(raw: String?): FgsMode {
        return runCatching { FgsMode.valueOf(raw ?: FgsMode.MEETING.name) }
            .getOrDefault(FgsMode.MEETING)
    }

    enum class FgsMode {
        MEETING,
        SCREEN_SHARE,
    }

    companion object {
        const val EXTRA_MODE = "mode"

        fun start(context: Context, mode: FgsMode) {
            val intent =
                Intent(context, MeetCallForegroundService::class.java).apply {
                    putExtra(EXTRA_MODE, mode.name)
                }
            context.startForegroundService(intent)
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, MeetCallForegroundService::class.java))
        }
    }
}
