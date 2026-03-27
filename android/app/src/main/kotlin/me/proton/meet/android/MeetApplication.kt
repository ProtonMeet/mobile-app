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

package proton.android.meet

import android.app.Application
import android.app.NotificationManager
import android.content.Context
import dagger.hilt.android.HiltAndroidApp
import proton.android.meet.initializer.MainInitializer

@HiltAndroidApp
class MeetApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        MainInitializer.init(this)
    }

    override fun onTerminate() {
        // Cancel all notifications when app is terminated
        // Note: onTerminate() is not guaranteed to be called on modern Android,
        // but it's a fallback in case onDestroy() is not called
        try {
            val notificationManager =
                    getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            // Cancel background notification (ID: 9999)
            notificationManager.cancel(9999)
            android.util.Log.d("MeetApplication", "Notifications cancelled in onTerminate")
        } catch (e: Exception) {
            android.util.Log.e(
                    "MeetApplication",
                    "Error cancelling notifications in onTerminate",
                    e
            )
        }
        super.onTerminate()
    }
}
