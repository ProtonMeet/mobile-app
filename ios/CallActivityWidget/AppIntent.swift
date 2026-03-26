//
//  AppIntent.swift
//  CallActivityWidget
//
//  Created by Yanfeng Zhang on 11/10/25.
//

import AppIntents
import WidgetKit

struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Configuration" }
    static var description: IntentDescription { "This is an example widget." }

    // An example configurable parameter.
    @Parameter(title: "Favorite Emoji", default: "😃")
    var favoriteEmoji: String
}

// App Intents for Dynamic Island button actions
// When these intents are triggered, iOS will automatically open the app
// We'll handle the actions via the method channel in AppDelegate
struct ToggleMuteIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Mute"
    static var description: IntentDescription = "Toggle microphone mute"

    @Parameter(title: "Action", default: "toggleMute")
    var action: String

    func perform() async throws -> some IntentResult {
        // iOS will automatically open the app when this intent is triggered
        // The action will be handled via method channel in AppDelegate
        return .result()
    }
}

struct ToggleSpeakerIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Speaker"
    static var description: IntentDescription = "Toggle speaker mode"

    @Parameter(title: "Action", default: "toggleSpeaker")
    var action: String

    func perform() async throws -> some IntentResult {
        return .result()
    }
}

struct EndCallIntent: AppIntent {
    static var title: LocalizedStringResource = "End Call"
    static var description: IntentDescription = "End the current call"

    @Parameter(title: "Action", default: "endCall")
    var action: String

    func perform() async throws -> some IntentResult {
        return .result()
    }
}
