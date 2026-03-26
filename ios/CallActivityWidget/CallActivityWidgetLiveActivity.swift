//
//  CallActivityWidgetLiveActivity.swift
//  CallActivityWidget
//
//  Created by Yanfeng Zhang on 11/10/25.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct CallActivityWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var isMuted: Bool
        public var isVideoEnabled: Bool
        public var participantCount: Int
        public var roomName: String
        public var elapsedSeconds: Int
    }

    public var callId: String

    public init(callId: String) {
        self.callId = callId
    }
}

extension CallActivityWidgetAttributes {
    fileprivate static var preview: CallActivityWidgetAttributes {
        CallActivityWidgetAttributes(callId: "World")
    }
}

extension CallActivityWidgetAttributes.ContentState {
    fileprivate static var smiley: CallActivityWidgetAttributes.ContentState {
        CallActivityWidgetAttributes.ContentState( isMuted: false,
                                                   isVideoEnabled: true,
                                                   participantCount: 5,
                                                   roomName: "Team Sync",
                                                   elapsedSeconds: 120)
    }
    
    fileprivate static var starEyes: CallActivityWidgetAttributes.ContentState {
        CallActivityWidgetAttributes.ContentState( isMuted: true,
                                                   isVideoEnabled: true,
                                                   participantCount: 5,
                                                   roomName: "Team Sync",
                                                   elapsedSeconds: 120)
    }
}

