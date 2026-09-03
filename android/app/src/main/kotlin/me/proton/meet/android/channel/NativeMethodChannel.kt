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

package proton.android.meet.channel

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import me.proton.core.account.domain.entity.Account
import me.proton.core.account.domain.entity.AccountDetails
import me.proton.core.account.domain.entity.AccountState
import me.proton.core.account.domain.entity.SessionState
import me.proton.core.domain.entity.UserId
import me.proton.core.network.domain.session.Session
import me.proton.core.network.domain.session.SessionId
import proton.android.meet.LogTag
import proton.android.meet.MeetLogger

interface NativeCallHandler {
    fun startLogin()
    fun startSignUp()
    fun startReport(username: String, email: String)
    fun startSubscription(accountSession: AccountSession)
    fun startUpgrade(accountSession: AccountSession)
    fun startChangePassword(accountSession: AccountSession)
    fun startUpdateRecoveryEmail(accountSession: AccountSession)
    fun restartActivity()
    fun restartApplication()
    fun logout(userId: UserId?)
    fun setMeetApiClientHeader(versionHeader: VersionHeader)
}

data class AccountSession(
    val account: Account,
    val session: Session
)

data class VersionHeader(
    val version: String?,
    val agent: String?
)

class NativeMethodChannel(
    engine: FlutterEngine,
    private val callHandler: NativeCallHandler,
) : MethodChannel(
    /* messenger = */ engine.dartExecutor.binaryMessenger,
    /* name = */ "me.proton.meet/native.views"
) {
    fun init() {
        setMethodCallHandler { call: MethodCall, result ->
            runCatching {
                val arguments = getArgumentsOrNull(call.arguments).orEmpty()
                val userId = getUserIdOrNull(arguments)
                val account = getAccountOrNull(arguments)
                val session = getSessionOrNull(arguments)
                when (call.method) {
                    "native.initialize.core.environment" -> callHandler.setMeetApiClientHeader(
                        getVersionHeader(arguments)
                    )
                    "native.navigation.login" -> callHandler.startLogin()
                    "native.navigation.signup" -> callHandler.startSignUp()
                    "native.navigation.report" -> {
                        val email = arguments["email"] as? String
                        val username = arguments["username"] as? String
                        require(!email.isNullOrBlank() && !username.isNullOrBlank()) {
                            "Missing username or email for bug report"
                        }
                        callHandler.startReport(username = username, email = email)
                    }
                    "native.navigation.plan.subscription" -> callHandler.startSubscription(
                        getAccountSession(account, session)
                    )

                    "native.navigation.plan.upgrade" -> callHandler.startUpgrade(
                        getAccountSession(account, session)
                    )

                    "native.navigation.user.settings.changepassword" -> callHandler.startChangePassword(
                        getAccountSession(account, session)
                    )

                    "native.navigation.user.settings.recoveryemail" -> callHandler.startUpdateRecoveryEmail(
                        getAccountSession(account, session)
                    )

                    "native.navigation.restartActivity" -> callHandler.restartActivity()
                    "native.navigation.restartApp" -> callHandler.restartApplication()
                    "native.account.logout" -> callHandler.logout(userId)
                }
            }.fold(
                onSuccess = {
                    result.success(null)
                },
                onFailure = {
                    MeetLogger.e(LogTag.CHANNEL_NATIVE, it)
                    result.error("code", it.message, null)
                }
            )
        }
    }

    private fun getVersionHeader(arguments: Map<String, Any>): VersionHeader {
        val appVersionKey = "app-version"
        val userAgentKey = "user-agent"
        return VersionHeader(
            version = arguments[appVersionKey] as String?,
            agent = arguments[userAgentKey] as String?,
        )
    }

    private fun getAccountSession(
        account: Account?,
        session: Session?,
    ) = AccountSession(
        account = requireNotNull(account) { "Missing Account (check session map / userId)" },
        session = requireNotNull(session) { "Missing Session (check accessToken, refreshToken, scopes)" },
    )

    /**
     * Normalizes Flutter method arguments into a [Map<String, Any>] so values stay typed
     * (e.g. [scopes] as a list). Avoids [Map<String, String>] casts that drop valid maps.
     *
     * Supported shapes (match iOS): `[ sessionKey, authMap ]`, or a single auth [Map],
     * same as other `native.navigation.*` calls.
     */
    private fun getArgumentsOrNull(arguments: Any?): Map<String, Any>? =
        when (arguments) {
            is ArrayList<*> ->
                if (arguments.size < 2) {
                    null
                } else {
                    val payload = arguments[1]
                    if (payload is Map<*, *>) mapFromFlutter(payload) else null
                }
            is Map<*, *> -> mapFromFlutter(arguments)
            else -> null
        }

    private fun mapFromFlutter(raw: Map<*, *>): Map<String, Any> {
        val out = LinkedHashMap<String, Any>()
        for ((k, v) in raw) {
            if (k != null && v != null) {
                out[k.toString()] = v
            }
        }
        return out
    }

    private fun getUserIdOrNull(arguments: Map<String, Any>): UserId? = runCatching {
        arguments["userId"]?.let { UserId(it as String) }
    }.getOrNull()

    private fun getSessionIdOrNull(arguments: Map<String, Any>): SessionId? = runCatching {
        arguments["sessionId"]?.let { SessionId(it as String) }
    }.getOrNull()

    private fun getAccountOrNull(arguments: Map<String, Any>) = runCatching {
        Account(
            username = arguments["userName"] as String?,
            userId = requireNotNull(getUserIdOrNull(arguments)),
            email = arguments["userMail"] as String?,
            sessionId = requireNotNull(getSessionIdOrNull(arguments)),
            state = AccountState.Ready,
            sessionState = SessionState.Authenticated,
            details = AccountDetails(null, null)
        )
    }.onFailure {
        MeetLogger.e(LogTag.CHANNEL_NATIVE, it)
    }.getOrNull()

    private fun getSessionOrNull(arguments: Map<String, Any>) = runCatching {
        Session.Authenticated(
            userId = requireNotNull(getUserIdOrNull(arguments)),
            sessionId = requireNotNull(getSessionIdOrNull(arguments)),
            accessToken = requireNotNull(arguments["accessToken"]?.toString()),
            refreshToken = requireNotNull(arguments["refreshToken"]?.toString()),
            scopes = parseScopes(arguments),
        )
    }.onFailure {
        MeetLogger.e(LogTag.CHANNEL_NATIVE, it)
    }.getOrNull()

    /** Flutter sends [scopes] as a List; Proton Core expects an [ArrayList] of scope strings. */
    private fun parseScopes(arguments: Map<String, Any>): ArrayList<String> {
        val raw = arguments["scopes"] ?: return ArrayList()
        return when (raw) {
            is ArrayList<*> -> ArrayList(raw.map { it.toString() })
            is List<*> -> ArrayList(raw.map { it.toString() })
            is String ->
                ArrayList(
                    raw.split(',').map { it.trim() }.filter { it.isNotEmpty() },
                )
            else -> throw IllegalArgumentException("Invalid scopes payload: ${raw::class.java.name}")
        }
    }
}
