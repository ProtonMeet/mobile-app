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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with Proton Mail. If not, see <https://www.gnu.org/licenses/>.
 */

package proton.android.meet.initializer

import android.content.Context
import androidx.startup.Initializer
import proton.android.meet.BuildConfig
import dagger.hilt.EntryPoint
import dagger.hilt.InstallIn
import dagger.hilt.android.EntryPointAccessors
import dagger.hilt.components.SingletonComponent
import io.sentry.Sentry
import io.sentry.SentryLevel
import io.sentry.SentryOptions
import io.sentry.android.core.SentryAndroid
import io.sentry.protocol.User
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.map
import me.proton.core.accountmanager.domain.AccountManager
import me.proton.core.configuration.EnvironmentConfigurationDefaults
import me.proton.core.util.android.sentry.TimberLoggerIntegration
import me.proton.core.util.android.sentry.project.AccountSentryHubBuilder
import me.proton.core.util.kotlin.CoroutineScopeProvider
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

class SentryInitializer : Initializer<Unit> {

    override fun create(context: Context) {
        SentryAndroid.init(context.applicationContext) { options: SentryOptions ->
            options.dsn = BuildConfig.SENTRY_MEET_DSN
            options.release = BuildConfig.VERSION_NAME
            options.environment = EnvironmentConfigurationDefaults.host
            options.addIntegration(
                TimberLoggerIntegration(
                    minEventLevel = SentryLevel.WARNING,
                    minBreadcrumbLevel = SentryLevel.INFO
                )
            )
        }

        val entryPoint = EntryPointAccessors.fromApplication(
            context.applicationContext,
            SentryInitializerEntryPoint::class.java
        )
        entryPoint.observer().start()

        entryPoint.accountSentryHubBuilder().invoke(
            sentryDsn = BuildConfig.SENTRY_ACCOUNT_DSN
        )
    }

    override fun dependencies(): List<Class<out Initializer<*>>> = emptyList()

    @EntryPoint
    @InstallIn(SingletonComponent::class)
    interface SentryInitializerEntryPoint {
        fun accountSentryHubBuilder(): AccountSentryHubBuilder
        fun observer(): SentryUserObserver
    }
}

@Singleton
class SentryUserObserver @Inject constructor(
    private val scopeProvider: CoroutineScopeProvider,
    private val accountManager: AccountManager
) {

    fun start() = accountManager.getPrimaryUserId().map { userId ->
        val user = User().apply { id = userId?.id ?: UUID.randomUUID().toString() }
        Sentry.setUser(user)
    }.launchIn(scopeProvider.GlobalDefaultSupervisedScope)
}
