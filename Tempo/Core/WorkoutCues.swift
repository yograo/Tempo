import Foundation

enum WorkoutCues {
    static let completion = "Workout complete. Well done!"

    static func step(_ step: RoutineStep) -> String {
        let name = String(step.displayName.prefix(80))
        let duration = step.seconds
        let minutes = duration / 60
        let seconds = duration % 60
        let parts = [minutes > 0 ? "\(minutes) \(minutes == 1 ? "minute" : "minutes")" : nil,
                     seconds > 0 ? "\(seconds) \(seconds == 1 ? "second" : "seconds")" : nil].compactMap { $0 }
        let prefix = step.kind == .rest && name != "Rest" ? "Rest. " : ""
        return "\(prefix)\(name). \(parts.joined(separator: ", "))."
    }
}

/// Offsets from a timeline snapshot, suitable for system-delivered notifications.
struct WorkoutAlertPlan {
    struct Cue: Equatable {
        let key: String
        let offset: Double
        let text: String
        let isCompletion: Bool
    }
    let cues: [Cue]
    let truncated: Bool

    init(timeline: WorkoutTimeline, limit: Int = 64) {
        guard timeline.state == .running, limit > 0 else {
            cues = []; truncated = false; return
        }
        var offset = timeline.remaining
        let nextIndex = timeline.isPreparing ? 0 : timeline.stepIndex + 1
        var result: [Cue] = []
        for index in nextIndex..<timeline.routine.steps.count {
            let step = timeline.routine.steps[index]
            result.append(Cue(key: "step-\(index)", offset: offset, text: WorkoutCues.step(step), isCompletion: false))
            offset += Double(step.seconds)
        }
        let completion = Cue(key: "complete", offset: offset, text: WorkoutCues.completion, isCompletion: true)
        // Always reserve a slot for completion, even for unusually long routines.
        truncated = result.count + 1 > limit
        cues = Array(result.prefix(max(0, limit - 1))) + [completion]
    }
}
