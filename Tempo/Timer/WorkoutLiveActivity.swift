import ActivityKit
import Foundation

@MainActor
final class WorkoutLiveActivity {
    private var activity: Activity<TempoActivityAttributes>?
    private var updates: Task<Void, Never>?
    private(set) var unavailable = false

    func update(id: UUID, timeline: WorkoutTimeline) {
        let state = TempoActivityAttributes.ContentState(
            endDate: Date().addingTimeInterval(timeline.totalRemainingExact),
            remainingSeconds: timeline.totalRemaining,
            isPaused: timeline.state == .paused, isComplete: timeline.state == .completed)
        let content = ActivityContent(state: state, staleDate: state.isPaused ? nil : state.endDate)
        if activity == nil {
            activity = Activity<TempoActivityAttributes>.activities.first { $0.attributes.workoutID == id.uuidString }
        }
        if activity == nil && timeline.state != .completed {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { unavailable = true; return }
            do {
                activity = try Activity.request(attributes: TempoActivityAttributes(
                    workoutID: id.uuidString, routineName: String(timeline.routine.name.prefix(100)),
                    symbol: timeline.routine.selectedIcon.symbol), content: content, pushType: nil)
                unavailable = false
            } catch { unavailable = true }
        }
        guard let activity else { return }
        let previous = updates
        updates = Task {
            await previous?.value
            if state.isComplete {
                await activity.end(content, dismissalPolicy: .after(Date().addingTimeInterval(60)))
            } else {
                await activity.update(content)
            }
        }
    }

    func end() {
        guard let activity else { return }
        self.activity = nil
        let previous = updates
        updates = Task {
            await previous?.value
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    static func removeOrphans(keeping id: UUID?) {
        for activity in Activity<TempoActivityAttributes>.activities where activity.attributes.workoutID != id?.uuidString {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
