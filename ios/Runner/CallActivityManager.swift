import Foundation
import ActivityKit

@available(iOS 16.2, *)
final class CallActivityManager {
    static let shared = CallActivityManager()
    private init() {}
    
    private var activity: Activity<CallActivityWidgetAttributes>?
    private var callId: String?
    
    func start(callId: String, roomName: String, participantCount: Int,
               isMuted: Bool = false, isVideoEnabled: Bool = true) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        
        self.callId = callId
        
        let attributes = CallActivityWidgetAttributes(callId: callId)
        let state = CallActivityWidgetAttributes.ContentState(
            isMuted: isMuted,
            isVideoEnabled: isVideoEnabled,
            participantCount: participantCount,
            roomName: roomName,
            elapsedSeconds: 0
        )
        
        // End any lingering ones first (e.g., after crash / hot-reload) and then start new activity
        Task { @MainActor in
            // Wait for cleanup to complete before starting new activity
            await endAllAsync(immediately: true)
            
            do {
                // Use staleDate as a safety net
                let content = ActivityContent(state: state,
                                              staleDate: .now.addingTimeInterval(5*60))
                let newActivity = try Activity.request(attributes: attributes, content: content, pushType: nil)
                self.activity = newActivity
                print("CallActivityManager: Successfully started Live Activity with ID: \(newActivity.id)")
            } catch {
                print("CallActivityManager: ERROR - Live Activity start failed: \(error)")
                print("CallActivityManager: Error details: \(error.localizedDescription)")
                if let nsError = error as NSError? {
                    print("CallActivityManager: Error domain: \(nsError.domain), code: \(nsError.code)")
                    print("CallActivityManager: Error userInfo: \(nsError.userInfo)")
                }
                self.callId = nil
            }
        }
    }
    
    func update(
        isMuted: Bool? = nil,
        isVideoEnabled: Bool? = nil,
        participantCount: Int? = nil,
        roomName: String? = nil,
        elapsedSeconds: Int? = nil
    ) {
        guard let activity = self.activity else { return }
        
        // Safety check: verify activity is still active
        guard activity.activityState == .active else {
            print("Live Activity is no longer active, cleaning up")
            self.activity = nil
            self.callId = nil
            return
        }
        
        var state = activity.contentState
        if let isMuted { state.isMuted = isMuted }
        if let isVideoEnabled { state.isVideoEnabled = isVideoEnabled }
        if let participantCount { state.participantCount = participantCount }
        if let roomName { state.roomName = roomName }
        if let elapsedSeconds { state.elapsedSeconds = elapsedSeconds }
        
        Task { @MainActor in
            
            await activity.update(using: state)
            
        }
    }
    
    func end(immediately: Bool = false) {
        guard let activity else { return }
        let final = CallActivityWidgetAttributes.ContentState(
            isMuted: true,               // arbitrary final flags
            isVideoEnabled: false,
            participantCount: 0,
            roomName: activity.attributes.callId, // or keep roomName if you prefer
            elapsedSeconds: activity.contentState.elapsedSeconds
        )
        Task { @MainActor in
            
            // Provide final ActivityContent to make the state transition explicit
            let content = ActivityContent(state: final, staleDate: nil)
            await activity.end(content, dismissalPolicy: immediately ? .immediate : .default)
            
        }
        self.activity = nil
        self.callId = nil
    }
    
    /// End *all* activities of this type (covers multiple instances / stale ones).
    /// Synchronous version for use in contexts that can't await (e.g., applicationWillTerminate).
    func endAll(immediately: Bool = true) {
        Task { @MainActor in
            await endAllAsync(immediately: immediately)
        }
    }
    
    /// Async implementation of endAll.
    @MainActor
    private func endAllAsync(immediately: Bool = true) async {
        let acts = Activity<CallActivityWidgetAttributes>.activities
        guard !acts.isEmpty else {
            // Clear our handle even if no activities found
            self.activity = nil
            self.callId = nil
            return
        }
        for act in acts {
            
            let final = CallActivityWidgetAttributes.ContentState(
                isMuted: true,
                isVideoEnabled: false,
                participantCount: 0,
                roomName: act.contentState.roomName,
                elapsedSeconds: act.contentState.elapsedSeconds
            )
            let content = ActivityContent(state: final, staleDate: nil)
            await act.end(content, dismissalPolicy: immediately ? .immediate : .default)
            
            
            
            
        }
        // Also clear our handle after all activities are ended
        self.activity = nil
        self.callId = nil
    }
    
    /// Clean up stale activities on app launch
    func cleanupStaleActivities() {
        let acts = Activity<CallActivityWidgetAttributes>.activities
        guard !acts.isEmpty else { return }
        
        // End all activities that are not in active state or are stale
        Task { @MainActor in
            for act in acts {
                // Check if activity is stale (older than 10 minutes) or not active
                let isStale = act.activityState != .active
                if isStale {
                    let final = CallActivityWidgetAttributes.ContentState(
                        isMuted: true,
                        isVideoEnabled: false,
                        participantCount: 0,
                        roomName: act.contentState.roomName,
                        elapsedSeconds: act.contentState.elapsedSeconds
                    )
                    let content = ActivityContent(state: final, staleDate: nil)
                    await act.end(content, dismissalPolicy: .immediate)
                    print("Cleaned up stale Live Activity: \(act.id)")
                    
                }
            }
        }
        
        // Clear our handle if we don't have a matching activity
        if let currentCallId = self.callId {
            let hasMatchingActivity = acts.contains { $0.attributes.callId == currentCallId }
            if !hasMatchingActivity {
                self.activity = nil
                self.callId = nil
            }
        } else {
            self.activity = nil
        }
    }
}
