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

import me.proton.core.util.android.sentry.TimberLogger
import me.proton.core.util.kotlin.Logger

object MeetLogger : Logger by TimberLogger

object LogTag {
    const val DEFAULT = "proton.android.meet.default"
    const val CHANNEL_FLUTTER = "proton.android.meet.channel.flutter"
    const val CHANNEL_NATIVE = "proton.android.meet.channel.native"
}
