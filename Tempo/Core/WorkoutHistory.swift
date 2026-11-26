import Foundation

struct WorkoutRecord: Codable, Identifiable, Equatable {
    enum Outcome: String, Codable { case finished, endedEarly }
    let id: UUID
    let routineID: UUID
    let routineName: String
    let icon: ExerciseIcon
    let startedAt: Date
    let endedAt: Date
    let activeSeconds: Double
    let skippedSteps: Int
    let outcome: Outcome
    var durationSeconds: Int { Int(activeSeconds.rounded()) }

    var isValid: Bool {
        !routineName.isEmpty && activeSeconds.isFinite && activeSeconds >= 0 && activeSeconds < Double(Int.max) &&
        skippedSteps >= 0 && endedAt >= startedAt
    }
}

struct SavedWorkout: Codable {
    let id: UUID
    let startedAt: Date
    var timeline: WorkoutTimeline
    let savedAt: Date
    let savedClock: Double
    let soundEnabled: Bool
    let speechEnabled: Bool
    var speechFiles: [String: String]? = nil
}

struct WorkoutArchive: Codable {
    var records: [WorkoutRecord] = []
    var active: SavedWorkout?

    mutating func finish(_ record: WorkoutRecord) {
        if !records.contains(where: { $0.id == record.id }) { records.append(record) }
        if active?.id == record.id { active = nil }
    }

    func thisWeek(now: Date = Date(), calendar: Calendar = .current) -> [WorkoutRecord] {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return [] }
        return records.filter { week.contains($0.endedAt) && $0.endedAt <= now }
    }
}

struct WorkoutHistoryFileStore {
    let url: URL

    func load() throws -> WorkoutArchive {
        guard FileManager.default.fileExists(atPath: url.path) else { return WorkoutArchive() }
        let archive = try JSONDecoder().decode(WorkoutArchive.self, from: Data(contentsOf: url))
        guard archive.records.allSatisfy(\.isValid),
              Set(archive.records.map(\.id)).count == archive.records.count else {
            throw CocoaError(.fileReadCorruptFile)
        }
        if let active = archive.active {
            guard active.timeline.isValidSnapshot, active.savedClock.isFinite else {
                throw CocoaError(.fileReadCorruptFile)
            }
        }
        return archive
    }

    func save(_ archive: WorkoutArchive) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(archive).write(to: url, options: .atomic)
    }
}
