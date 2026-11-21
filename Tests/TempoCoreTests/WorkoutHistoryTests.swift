import Foundation
import XCTest
@testable import TempoCore

final class WorkoutHistoryTests: XCTestCase {
    private var routine: Routine {
        Routine(name: "Intervals", steps: [
            .init(kind: .exercise, name: "Squats", seconds: 10),
            .init(kind: .rest, name: "Breathe", seconds: 5),
            .init(kind: .exercise, name: "Plank", seconds: 10)
        ])
    }

    func testHistoryTimeExcludesPreparationPauseAndSkippedSeconds() {
        var timeline = WorkoutTimeline(routine: routine)
        _ = timeline.start(now: 0)
        _ = timeline.tick(now: 4)
        XCTAssertEqual(timeline.elapsedSeconds, 0)
        _ = timeline.tick(now: 8)
        XCTAssertEqual(timeline.elapsedSeconds, 2)
        _ = timeline.pause(now: 10)
        XCTAssertEqual(timeline.elapsedSeconds, 4)
        timeline.resume(now: 100)
        _ = timeline.skip(now: 103)
        XCTAssertEqual(timeline.elapsedSeconds, 7)
        XCTAssertEqual(timeline.skippedSteps, 1)
        _ = timeline.tick(now: 200)
        XCTAssertEqual(timeline.elapsedSeconds, 22)
        XCTAssertEqual(timeline.completedAt, 118)
    }

    func testSuspendedWorkoutRestoresThroughSeveralIntervals() {
        var timeline = WorkoutTimeline(routine: routine)
        _ = timeline.start(now: 100)
        _ = timeline.tick(now: 102)
        XCTAssertEqual(timeline.restore(savedClock: 102, now: 1000, elapsed: 21), [.stepStarted])
        XCTAssertEqual(timeline.currentStep?.name, "Plank")
        XCTAssertEqual(timeline.remaining, 8)
        XCTAssertEqual(timeline.elapsedSeconds, 17)
        XCTAssertEqual(timeline.tick(now: 1008), [.completed])
        XCTAssertEqual(timeline.elapsedSeconds, 25)
    }

    func testRelaunchAfterCompletionUsesActualFinishDeadline() {
        var timeline = WorkoutTimeline(routine: routine)
        _ = timeline.start(now: 0)
        XCTAssertEqual(timeline.restore(savedClock: 0, now: 500, elapsed: 100), [.completed])
        XCTAssertEqual(timeline.completedAt, 431)
        XCTAssertEqual(timeline.elapsedSeconds, 25)
        XCTAssertEqual(timeline.tick(now: 600), [])
        XCTAssertEqual(timeline.elapsedSeconds, 25)
    }

    func testPausedWorkoutDoesNotAdvanceOnRelaunch() {
        var timeline = WorkoutTimeline(routine: routine)
        _ = timeline.start(now: 0)
        _ = timeline.pause(now: 9)
        XCTAssertEqual(timeline.restore(savedClock: 9, now: 1000, elapsed: 900), [])
        XCTAssertEqual(timeline.state, .paused)
        XCTAssertEqual(timeline.remaining, 7)
        XCTAssertEqual(timeline.elapsedSeconds, 3)
        timeline.resume(now: 1000)
        _ = timeline.tick(now: 1007)
        XCTAssertEqual(timeline.currentStep?.kind, .rest)
    }

    func testCompletionIsIdempotentAndClearsOnlyMatchingActiveWorkout() throws {
        let id = UUID()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let record = WorkoutRecord(id: id, routineID: routine.id, routineName: routine.name, icon: .intervals,
            startedAt: start, endedAt: start.addingTimeInterval(31), activeSeconds: 25, skippedSteps: 0, outcome: .finished)
        var archive = WorkoutArchive(active: SavedWorkout(id: id, startedAt: start, timeline: WorkoutTimeline(routine: routine),
            savedAt: start, savedClock: 0, soundEnabled: true, speechEnabled: true))
        archive.finish(record)
        archive.finish(record)
        XCTAssertEqual(archive.records.count, 1)
        XCTAssertNil(archive.active)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("history.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let file = WorkoutHistoryFileStore(url: url)
        try file.save(archive)
        let saved = try file.load()
        XCTAssertEqual(saved.records, [record])
        XCTAssertNil(saved.active)
    }

    func testSessionRoundTripPreservesDeadlinesAndPreferences() throws {
        var timeline = WorkoutTimeline(routine: routine)
        _ = timeline.start(now: 100)
        _ = timeline.skip(now: 110)
        let session = SavedWorkout(id: UUID(), startedAt: Date(), timeline: timeline, savedAt: Date(), savedClock: 110,
            soundEnabled: false, speechEnabled: true)
        var restored = try JSONDecoder().decode(SavedWorkout.self, from: JSONEncoder().encode(session))
        XCTAssertFalse(restored.soundEnabled)
        XCTAssertTrue(restored.speechEnabled)
        _ = restored.timeline.restore(savedClock: restored.savedClock, now: 1000, elapsed: 6)
        XCTAssertEqual(restored.timeline.currentStep?.name, "Plank")
        XCTAssertEqual(restored.timeline.remaining, 9)
        XCTAssertEqual(restored.timeline.elapsedSeconds, 10)
        XCTAssertEqual(restored.timeline.skippedSteps, 1)
    }

    func testCorruptHistoryIsPreservedAndRejected() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let corrupt = Data("{broken history".utf8)
        try corrupt.write(to: url)
        XCTAssertThrowsError(try WorkoutHistoryFileStore(url: url).load())
        XCTAssertEqual(try Data(contentsOf: url), corrupt)
    }

    func testHistoryRoundsFloatingPointDurationsToWholeSeconds() {
        let record = WorkoutRecord(id: UUID(), routineID: routine.id, routineName: routine.name, icon: .intervals,
            startedAt: Date(), endedAt: Date(), activeSeconds: 5.999999999, skippedSteps: 0, outcome: .finished)
        XCTAssertEqual(record.durationSeconds, 6)
    }

    func testWeeklySummaryUsesCalendarAndIncludesPartialWorkouts() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let week = calendar.dateInterval(of: .weekOfYear, for: now)!
        func record(_ date: Date) -> WorkoutRecord {
            WorkoutRecord(id: UUID(), routineID: routine.id, routineName: "Snapshot name", icon: .yoga,
                startedAt: date.addingTimeInterval(-10), endedAt: date, activeSeconds: 10, skippedSteps: 0, outcome: .endedEarly)
        }
        let archive = WorkoutArchive(records: [record(week.start.addingTimeInterval(-1)), record(now), record(now.addingTimeInterval(60))])
        XCTAssertEqual(archive.thisWeek(now: now, calendar: calendar).count, 1)
    }
}
