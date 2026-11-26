import ActivityKit
import SwiftUI
import WidgetKit

@main
struct TempoActivityBundle: WidgetBundle {
    var body: some Widget { TempoLiveActivity() }
}

struct TempoLiveActivity: Widget {
    private let lime = Color(red: 0.82, green: 0.94, blue: 0.42)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TempoActivityAttributes.self) { context in
            HStack(spacing: 16) {
                Image(systemName: context.attributes.symbol)
                    .font(.system(size: 30)).foregroundStyle(lime)
                VStack(alignment: .leading, spacing: 6) {
                    Text("TEMPO").font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(lime)
                    Text(context.attributes.routineName).font(.system(.headline, design: .rounded)).lineLimit(2)
                    Text(context.state.isComplete ? "Workout complete" : context.state.isPaused ? "Paused · tap to resume" : context.isStale ? "Time elapsed · tap to open" : "Workout time left")
                        .font(.caption).foregroundStyle(.white.opacity(0.65))
                }
                Spacer(minLength: 0)
                countdown(context.state)
                    .font(.system(size: 32, weight: .medium, design: .rounded))
                    .frame(width: 100, alignment: .trailing)
            }
            .padding(20).foregroundStyle(.white)
            .activityBackgroundTint(Color(red: 0.08, green: 0.12, blue: 0.11))
            .activitySystemActionForegroundColor(lime)
            .widgetURL(URL(string: "tempo://workout"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Tempo", systemImage: context.attributes.symbol).foregroundStyle(lime)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdown(context.state).monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 5) {
                        Text(context.attributes.routineName).font(.headline).lineLimit(1)
                        Text(context.state.isComplete ? "Workout complete" : context.state.isPaused ? "Paused" : "Workout time left")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "timer").foregroundStyle(lime)
            } compactTrailing: {
                countdown(context.state).monospacedDigit().frame(width: 55)
            } minimal: {
                Image(systemName: context.state.isComplete ? "checkmark" : context.state.isPaused ? "pause.fill" : "timer").foregroundStyle(lime)
            }
            .widgetURL(URL(string: "tempo://workout"))
            .keylineTint(lime)
        }
    }

    @ViewBuilder
    private func countdown(_ state: TempoActivityAttributes.ContentState) -> some View {
        if state.isComplete {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(lime)
        } else if state.isPaused {
            Text(String(format: "%02d:%02d", state.remainingSeconds / 60, state.remainingSeconds % 60))
        } else {
            // System-rendered dates keep counting down even when Tempo is suspended.
            Text(timerInterval: Date.distantPast...state.endDate, countsDown: true)
                .monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
        }
    }
}
