import ActivityKit
import SwiftUI
import WidgetKit
import AppIntents
// Helper function to format elapsed time as MM:SS or H:MM:SS
func formatTime(seconds: Int) -> String {
    let hours = seconds / 3600
    let minutes = (seconds % 3600) / 60
    let secs = seconds % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, secs)
    } else {
        return String(format: "%d:%02d", minutes, secs)
    }
}
//@main
struct CallActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CallActivityWidgetAttributes.self) { context in
            /// Lock Screen banner style - Zoom-inspired design
            ZStack {
                // Dark gradient background (purple/black tones)
                LinearGradient(
                    colors: [
                        Color(red: 0.15, green: 0.1, blue: 0.2),
                        Color(red: 0.05, green: 0.05, blue: 0.1),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                
                VStack(alignment: .leading, spacing: 16) {
                    // Top row: App icon + Time
                    HStack {
                        // App icon (smallLogo) with leading padding
                        Image("islandLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                        
                        Spacer()
                        
                        // Time display (formatted from elapsed seconds)
                        Text(formatTime(seconds: context.state.elapsedSeconds))
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(.gray.opacity(0.7))
                    }
                    
                    // Main title: Room name
                    Text(context.state.roomName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    
                    // Subtitle: Speaking status + participant count
                    HStack(spacing: 4) {
                        Text("Speaking")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.white.opacity(0.5))
                        Text("•")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.5))
                        Text("\(context.state.participantCount) participants")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    
                    // Status icons aligned to the right
                    HStack(spacing: 10) {
                        Spacer()
                        
                        // Microphone icon (bright if on, dim if muted)
                        Image(systemName: context.state.isVideoEnabled ? "video.fill" : "video.slash.fill")
                            .font(.system(size: 14))
                            .foregroundColor(
                                context.state.isVideoEnabled ? .white.opacity(0.8) : .white.opacity(0.3))
                        
                        // Microphone icon (bright if on, dim if muted)
                        Image(systemName: context.state.isMuted ? "mic.slash.fill" : "mic.fill")
                            .font(.system(size: 14))
                            .foregroundColor(
                                context.state.isMuted ? .white.opacity(0.3) : .white.opacity(0.8))
                    }.padding(.bottom, 16)
                }
                .padding(.horizontal, 14)
                .padding(.top, 16)
                .padding(.bottom, 10)
            }
            
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    // Icon with colored background
                    Rectangle()
                        .foregroundColor(.clear)
                        .frame(width: 53, height: 53)
                        .background(.clear)
                        .overlay(
                            Image("islandLogo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 53, height: 53)
                        ).padding(.top, 10)
                        .padding(.leading, 10)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        // Room name
                        Text(context.state.roomName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(height: 18)
                        // Participant count
                        Text("\(context.state.participantCount) participants")
                            .font(.system(size: 15))
                            .foregroundColor(Color(red: 0.60, green: 0.60, blue: 0.60))
                    }
                    .padding(.horizontal, 8)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack {
                        Spacer()
                        HStack(spacing: 12) {
                            Image(systemName: context.state.isVideoEnabled ? "video.fill" : "video.slash.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 18, height: 18)
                                .foregroundColor(
                                    context.state.isVideoEnabled ? Color(red: 0.22, green: 0.75, blue: 0.35) : .white.opacity(0.3)
                                )
                            
                            Image(systemName: context.state.isMuted ? "mic.slash.fill" : "mic.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 18, height: 18)
                                .foregroundColor(
                                    context.state.isMuted ? .white.opacity(0.3) : Color(red: 0.22, green: 0.75, blue: 0.35)
                                )
                        }
                        Spacer()
                    }
                    .padding(.top, 10)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    /// expanded bottom buttons
                    EmptyView()
                    //                    // Control buttons row - Speaker, Microphone, Video (non-clickable), End Call
                    //                    HStack(alignment: .top, spacing: 8) {
                    //                        // Speaker button
                    //                        Button(intent: ToggleSpeakerIntent()) {
                    //                            ZStack {
                    //                                Ellipse()
                    //                                    .foregroundColor(.clear)
                    //                                    .frame(width: 50.64, height: 50.64)
                    //                                    .background(Color(red: 0.16, green: 0.16, blue: 0.18))
                    //                                Image(systemName: "speaker.wave.2.fill")
                    //                                    .font(.system(size: 22.82))
                    //                                    .foregroundColor(.white)
                    //                            }
                    //                            .frame(width: 50.64, height: 50.64)
                    //                        }
                    //                        .buttonStyle(.plain)
                    //
                    //                        // Microphone button (clickable)
                    //                        Button(intent: ToggleMuteIntent()) {
                    //                            ZStack {
                    //                                Ellipse()
                    //                                    .foregroundColor(.clear)
                    //                                    .frame(width: 50.64, height: 50.64)
                    //                                    .background(Color(red: 0.16, green: 0.16, blue: 0.18))
                    //                                Image(
                    //                                    systemName: context.state.isMuted
                    //                                    ? "mic.slash.fill" : "mic.fill"
                    //                                )
                    //                                .font(.system(size: 22.82))
                    //                                .foregroundColor(.white)
                    //                            }
                    //                            .frame(width: 50.64, height: 50.64)
                    //                        }
                    //                        .buttonStyle(.plain)
                    //
                    //                        // Video toggle button (non-clickable, shows state only)
                    //                        ZStack {
                    //                            Ellipse()
                    //                                .foregroundColor(.clear)
                    //                                .frame(width: 50.64, height: 50.64)
                    //                                .background(Color(red: 0.16, green: 0.16, blue: 0.18))
                    //                            Image(
                    //                                systemName: context.state.isVideoEnabled
                    //                                ? "video.fill" : "video.slash.fill"
                    //                            )
                    //                            .font(.system(size: 22.82))
                    //                            .foregroundColor(.white)
                    //                        }
                    //                        .frame(width: 50.64, height: 50.64)
                    //
                    //                        // End call button (red, clickable)
                    //                        Button(intent: EndCallIntent()) {
                    //                            ZStack {
                    //                                Ellipse()
                    //                                    .foregroundColor(.clear)
                    //                                    .frame(width: 50.64, height: 50.64)
                    //                                    .background(Color(red: 0.98, green: 0.21, blue: 0.20))
                    //                                Image(systemName: "phone.down.fill")
                    //                                    .font(.system(size: 22.41))
                    //                                    .foregroundColor(.white)
                    //                            }
                    //                            .frame(width: 50.64, height: 50.64)
                    //                        }
                    //                        .buttonStyle(.plain)
                    //                    }
                }
            } compactLeading: {
                // Green video camera icon
                Image(systemName: "video.fill")
                    .font(.system(size: 14))
                    .foregroundColor(Color(red: 0.22, green: 0.75, blue: 0.35))
                
            } compactTrailing: {
                // Time display (formatted from elapsed seconds)
                Text(formatTime(seconds: context.state.elapsedSeconds))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.gray.opacity(0.7))
                //                // Colorful waveform icon with green, yellow, and orange bars
                //                HStack(spacing: 2) {
                //                    Rectangle()
                //                        .fill(Color.green)
                //                        .frame(width: 2, height: 8)
                //                    Rectangle()
                //                        .fill(Color.yellow)
                //                        .frame(width: 2, height: 12)
                //                    Rectangle()
                //                        .fill(Color.orange)
                //                        .frame(width: 2, height: 10)
                //                    Rectangle()
                //                        .fill(Color.green)
                //                        .frame(width: 2, height: 14)
                //                    Rectangle()
                //                        .fill(Color.yellow)
                //                        .frame(width: 2, height: 8)
                //                }
            } minimal: {
                // Minimal state - shows your logo
                Image("islandLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                
            }
        }
    }
}

#if DEBUG
@available(iOSApplicationExtension 16.2, *)
struct CallActivityWidget_Previews: PreviewProvider {
    static var previews: some View {
        let attributes = CallActivityWidgetAttributes(callId: "preview-call")
        let contentState = CallActivityWidgetAttributes.ContentState(
            isMuted: true,
            isVideoEnabled: false,
            participantCount: 5,
            roomName: "Team Sync",
            elapsedSeconds: 120
        )
        
        // Lock Screen preview
        attributes
            .previewContext(contentState, viewKind: .content)
            .previewDisplayName("Lock Screen")
        
        // Dynamic Island – minimal
        attributes
            .previewContext(contentState, viewKind: .dynamicIsland(.minimal))
            .previewDisplayName("Dynamic Island – Minimal")
        
        // Dynamic Island – compact
        attributes
            .previewContext(contentState, viewKind: .dynamicIsland(.compact))
            .previewDisplayName("Dynamic Island – Compact")
        attributes
            .previewContext(contentState, viewKind: .dynamicIsland(.expanded))
            .previewDisplayName("Dynamic Island – Expanded")
        
    }
}
#endif
