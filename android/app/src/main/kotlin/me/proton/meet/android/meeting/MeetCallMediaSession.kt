/*
 * Copyright (c) 2026 Proton AG
 * This file is part of Proton AG and Proton Meet.
 */

package proton.android.meet.meeting

import android.content.ComponentName
import android.content.Context
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import androidx.media.session.MediaButtonReceiver

/** Media controls for an ongoing meeting (lock screen, BT, wearables). */
class MeetCallMediaSession(context: Context) {

    private val appContext = context.applicationContext
    private val session =
        MediaSessionCompat(appContext, SESSION_TAG).apply {
            setFlags(
                MediaSessionCompat.FLAG_HANDLES_MEDIA_BUTTONS or
                    MediaSessionCompat.FLAG_HANDLES_TRANSPORT_CONTROLS,
            )
        }

    fun activate(roomName: String) {
        session.setCallback(
            object : MediaSessionCompat.Callback() {
                override fun onStop() {
                    MeetCallController.notifyEndCallRequested()
                }
            },
        )
        session.setMediaButtonReceiver(
            MediaButtonReceiver.buildMediaButtonPendingIntent(
                appContext,
                ComponentName(appContext, MediaButtonReceiver::class.java),
                PlaybackStateCompat.ACTION_STOP,
            ),
        )
        session.setMetadata(
            MediaMetadataCompat.Builder()
                .putString(MediaMetadataCompat.METADATA_KEY_TITLE, roomName)
                .putString(MediaMetadataCompat.METADATA_KEY_DISPLAY_TITLE, roomName)
                .build(),
        )
        session.setPlaybackState(
            PlaybackStateCompat.Builder()
                .setActions(PlaybackStateCompat.ACTION_STOP)
                .setState(PlaybackStateCompat.STATE_PLAYING, 0, 1f)
                .build(),
        )
        session.isActive = true
    }

    fun deactivate() {
        session.isActive = false
        session.setCallback(null)
        session.setMediaButtonReceiver(null)
    }

    fun release() {
        deactivate()
        session.release()
    }

    companion object {
        private const val SESSION_TAG = "ProtonMeetOngoingCall"
    }
}
