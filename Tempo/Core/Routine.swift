import Foundation

enum ExerciseIcon: String, Codable, CaseIterable, Identifiable, Sendable {
    case intervals, strength, running, cycling, yoga, stretching, walking, core, swimming, boxing, dance, jumpRope

    var id: String { rawValue }
    var title: String {
        switch self {
        case .intervals: return "Intervals"
        case .strength: return "Strength"
        case .running: return "Running"
        case .cycling: return "Cycling"
        case .yoga: return "Yoga"
        case .stretching: return "Stretching"
        case .walking: return "Walking"
        case .core: return "Core"
        case .swimming: return "Swimming"
        case .boxing: return "Boxing"
        case .dance: return "Dance"
        case .jumpRope: return "Jump rope"
        }
    }

    var symbol: String {
        switch self {
        case .intervals: return "figure.highintensity.intervaltraining"
        case .strength: return "figure.strengthtraining.traditional"
        case .running: return "figure.run"
        case .cycling: return "figure.outdoor.cycle"
        case .yoga: return "figure.yoga"
        case .stretching: return "figure.flexibility"
        case .walking: return "figure.walk"
        case .core: return "figure.core.training"
        case .swimming: return "figure.pool.swim"
        case .boxing: return "figure.boxing"
        case .dance: return "figure.dance"
        case .jumpRope: return "figure.jumprope"
        }
    }
}

enum StepKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case exercise, rest
    var id: String { rawValue }
    var title: String { self == .exercise ? "Exercise" : "Rest" }
    var symbol: String { self == .exercise ? "figure.strengthtraining.functional" : "wind" }
}

struct RoutineStep: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var kind: StepKind
    var name: String
    var seconds: Int
    // Optional so routines saved before icon selection remain readable.
    var icon: ExerciseIcon?

    var selectedIcon: ExerciseIcon {
        get { icon ?? .strength }
        set { icon = newValue }
    }
    var symbol: String { kind == .rest ? "wind" : selectedIcon.symbol }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? kind.title : trimmed
    }

    var isValid: Bool { (1...3599).contains(seconds) && (kind == .rest || !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
}

struct Routine: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var steps: [RoutineStep]
    var icon: ExerciseIcon?

    var selectedIcon: ExerciseIcon {
        get { icon ?? .intervals }
        set { icon = newValue }
    }

    var totalSeconds: Int { steps.reduce(0) { $0 + $1.seconds } }
    var exerciseCount: Int { steps.filter { $0.kind == .exercise }.count }
    var restSeconds: Int { steps.filter { $0.kind == .rest }.reduce(0) { $0 + $1.seconds } }
    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && exerciseCount > 0 && steps.allSatisfy(\.isValid)
    }

    static var starter: Routine {
        Routine(name: "Everyday energy", steps: [
            .init(kind: .exercise, name: "Jumping jacks", seconds: 45),
            .init(kind: .rest, name: "Catch your breath", seconds: 15),
            .init(kind: .exercise, name: "Squats", seconds: 45),
            .init(kind: .rest, name: "Catch your breath", seconds: 15),
            .init(kind: .exercise, name: "Mountain climbers", seconds: 30),
            .init(kind: .rest, name: "Catch your breath", seconds: 15),
            .init(kind: .exercise, name: "Plank", seconds: 45)
        ])
    }
}

enum DurationText {
    static func clock(_ seconds: Int) -> String {
        let value = max(0, seconds)
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    static func short(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let remainder = seconds % 60
        return remainder == 0 ? "\(seconds / 60) min" : "\(seconds / 60)m \(remainder)s"
    }
}
