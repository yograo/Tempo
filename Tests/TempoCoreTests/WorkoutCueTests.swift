import XCTest
@testable import TempoCore

final class WorkoutCueTests: XCTestCase {
    private var routine: Routine {
        Routine(name: "Short workout", steps: [.init(kind: .exercise, name: "Squats", seconds: 5),
            .init(kind: .rest, name: "Breathe", seconds: 2), .init(kind: .exercise, name: "Plank", seconds: 4)])
    }

    func testAlertDeadlinesIncludePreparationAndCompletion() {
        var timeline = WorkoutTimeline(routine: routine)
        _ = timeline.start(now: 100)
        let plan = WorkoutAlertPlan(timeline: timeline)
        XCTAssertEqual(plan.cues.map(\.offset), [6, 11, 13, 17])
        XCTAssertEqual(plan.cues.last?.text, WorkoutCues.completion)
        XCTAssertFalse(plan.truncated)
    }

    func testPauseCancelsAlertsAndResumeAndSkipRecomputeOffsets() {
        var timeline = WorkoutTimeline(routine: routine, preparationSeconds: 0)
        _ = timeline.start(now: 0)
        _ = timeline.pause(now: 1.25)
        XCTAssertTrue(WorkoutAlertPlan(timeline: timeline).cues.isEmpty)
        timeline.resume(now: 100)
        XCTAssertEqual(WorkoutAlertPlan(timeline: timeline).cues.map(\.offset), [3.75, 5.75, 9.75])
        _ = timeline.skip(now: 100)
        XCTAssertEqual(WorkoutAlertPlan(timeline: timeline).cues.map(\.offset), [2, 6])
        _ = timeline.tick(now: 106)
        XCTAssertTrue(WorkoutAlertPlan(timeline: timeline).cues.isEmpty)
    }

    func testLongRoutineReservesCompletionWithinSystemLimit() {
        let routine = Routine(name: "Many steps", steps: (0..<100).map { .init(kind: .exercise, name: "Step \($0)", seconds: 10) })
        var timeline = WorkoutTimeline(routine: routine)
        _ = timeline.start(now: 0)
        let plan = WorkoutAlertPlan(timeline: timeline)
        XCTAssertEqual(plan.cues.count, 64)
        XCTAssertTrue(plan.truncated)
        XCTAssertEqual(plan.cues.last?.offset, 1006)
        XCTAssertTrue(plan.cues.last!.isCompletion)
        XCTAssertEqual(WorkoutAlertPlan(timeline: timeline, limit: 1).cues.count, 1)
        XCTAssertTrue(WorkoutAlertPlan(timeline: timeline, limit: 0).cues.isEmpty)
    }

    func testSpokenRestAndDurationAreClearAndNamesAreBounded() {
        XCTAssertEqual(WorkoutCues.step(.init(kind: .rest, name: "Breathe", seconds: 61)), "Rest. Breathe. 1 minute, 1 second.")
        XCTAssertEqual(WorkoutCues.step(.init(kind: .exercise, name: "Squats", seconds: 120)), "Squats. 2 minutes.")
        let cue = WorkoutCues.step(.init(kind: .exercise, name: String(repeating: "a", count: 1000), seconds: 1))
        XCTAssertLessThan(cue.count, 100)
    }
}
