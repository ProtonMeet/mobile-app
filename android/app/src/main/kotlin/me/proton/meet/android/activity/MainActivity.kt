/*
 * Copyright (c) 2024 Proton AG
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

package proton.android.meet.activity

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import androidx.activity.viewModels
import androidx.annotation.NonNull
import androidx.lifecycle.ProcessLifecycleOwner
import cl.puntito.simple_pip_mode.PipCallbackHelper
import dagger.hilt.android.AndroidEntryPoint
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant
import javax.inject.Inject
import me.proton.core.domain.entity.UserId
import proton.android.meet.MeetApiClient
import proton.android.meet.channel.AccountSession
import proton.android.meet.channel.FlutterMethodChannel
import proton.android.meet.channel.NativeCallHandler
import proton.android.meet.channel.NativeMethodChannel
import proton.android.meet.channel.VersionHeader

@AndroidEntryPoint
class MainActivity : FlutterFragmentActivity(), NativeCallHandler {

    private val viewModel: MainActivityViewModel by viewModels()
    private var callbackHelper = PipCallbackHelper()
    private var physicalKeyChannel: MethodChannel? = null

    @Inject lateinit var meetApiClient: MeetApiClient

    private val lifecycleObserver =
            object : androidx.lifecycle.DefaultLifecycleObserver {
                override fun onStop(owner: androidx.lifecycle.LifecycleOwner) {
                    // Cancel notifications when app process is stopped (killed)
                    // This is called when the app is killed by the system
                    cancelAllNotifications()
                }
            }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        GeneratedPluginRegistrant.registerWith(flutterEngine)

        callbackHelper.configureFlutterEngine(flutterEngine)

        val nativeChannel = NativeMethodChannel(flutterEngine, this)
        val flutterChannel = FlutterMethodChannel(flutterEngine)
        nativeChannel.init()
        viewModel.register(this, flutterChannel)

        // Create channel for physical key detection (currently supports home key)
        physicalKeyChannel =
                MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "me.proton.meet/physical_key")

        // Register lifecycle observer to cancel notifications when app is killed
        ProcessLifecycleOwner.get().lifecycle.addObserver(lifecycleObserver)
    }

    override fun onPictureInPictureModeChanged(
            isInPictureInPictureMode: Boolean,
            newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        callbackHelper.onPictureInPictureModeChanged(isInPictureInPictureMode)

        android.util.Log.d("MainActivity", "PIP mode changed: $isInPictureInPictureMode")

        // When PIP is closed, restore Activity to fullscreen foreground
        if (!isInPictureInPictureMode) {
            android.util.Log.d("MainActivity", "PIP closed, restoring Activity to foreground")
        }
    }

    override fun startLogin() {
        viewModel.startLogin()
    }

    override fun startSignUp() {
        viewModel.startSignUp()
    }

    override fun startReport() {
        viewModel.startReport()
    }

    override fun startSubscription(accountSession: AccountSession) {
        viewModel.startSubscription(accountSession)
    }

    override fun startUpgrade(accountSession: AccountSession) {
        viewModel.startUpgrade(accountSession)
    }

    override fun startChangePassword(accountSession: AccountSession) {
        viewModel.startPasswordManagement(accountSession)
    }

    override fun startUpdateRecoveryEmail(accountSession: AccountSession) {
        viewModel.startUpdateRecoveryEmail(accountSession)
    }

    override fun restartActivity() {
        val intent = Intent(this, MainActivity::class.java)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
        startActivity(intent)
    }

    override fun restartApplication() {
        restartActivity()
        Runtime.getRuntime().exit(0)
    }

    override fun logout(userId: UserId?) {
        viewModel.logout(userId)
    }

    override fun setMeetApiClientHeader(versionHeader: VersionHeader) {
        meetApiClient.updateVersion(versionHeader.version, versionHeader.agent)
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        // User pressed home key - notify Flutter
        physicalKeyChannel?.invokeMethod("onHomeKeyPressed", null)
        android.util.Log.d("MainActivity", "Home key pressed")
    }

    override fun onStop() {
        super.onStop()
        // Don't cancel notifications here - user might just be switching apps
        // Notifications will be cancelled by ProcessLifecycleOwner when app is killed
    }

    override fun onDestroy() {
        // Remove lifecycle observer
        ProcessLifecycleOwner.get().lifecycle.removeObserver(lifecycleObserver)
        super.onDestroy()
        // Cancel all notifications when Activity is destroyed
        cancelAllNotifications()
    }

    private fun cancelAllNotifications() {
        try {
            val notificationManager =
                    getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            // Cancel PIP notification (ID: 9999)
            notificationManager.cancel(9999)
            android.util.Log.d("MainActivity", "Notifications cancelled")
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "Error cancelling notifications", e)
        }
    }
}
