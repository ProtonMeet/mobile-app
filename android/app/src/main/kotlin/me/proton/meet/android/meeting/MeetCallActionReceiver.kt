/*
 * Copyright (c) 2026 Proton AG
 * This file is part of Proton AG and Proton Meet.
 */

package proton.android.meet.meeting

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Handles notification actions (return to meeting / end call). */
class MeetCallActionReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent?) {
        when (intent?.action) {
            MeetCallController.ACTION_RETURN_TO_CALL -> {
                MeetCallController.launchMeetingActivity(context)
                MeetCallController.notifyReturnToCall()
            }
            MeetCallController.ACTION_END_CALL -> {
                MeetCallController.endCallFromNotification(context)
            }
        }
    }
}
