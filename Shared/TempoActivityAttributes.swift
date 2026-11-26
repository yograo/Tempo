import ActivityKit
import Foundation

struct TempoActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var endDate: Date
        var remainingSeconds: Int
        var isPaused: Bool
        var isComplete: Bool
    }
    var workoutID: String
    var routineName: String
    var symbol: String
}
