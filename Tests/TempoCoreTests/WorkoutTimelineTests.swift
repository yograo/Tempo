import Foundation
import XCTest
@testable import TempoCore

private func sample() -> Routine {
    Routine(name: "Quick workout", steps: [
        .init(kind: .exercise, name: "Squats", seconds: 5),
        .init(kind: .rest, name: "Rest", seconds: 2),
        .init(kind: .exercise, name: "Plank", seconds: 4)
    ])
}

final class WorkoutTimelineTests: XCTestCase {
    func testSixSecondPreparationPreservesTheFullFirstExercise() {
        var timer = WorkoutTimeline(routine: sample())
        XCTAssertTrue(timer.isPreparing)
        XCTAssertEqual(timer.remainingSeconds, 6)
        XCTAssertNil(timer.currentStep)
        XCTAssertEqual(timer.totalRemaining, 17)
        XCTAssertEqual(timer.start(now: 100), [.countdown(6)])
        for second in 1...5 {
            XCTAssertEqual(timer.tick(now: 100 + Double(second)), [.countdown(6 - second)])
            XCTAssertTrue(timer.isPreparing)
            XCTAssertEqual(timer.tick(now: 100 + Double(second) + 0.05), [])
        }
        XCTAssertEqual(timer.tick(now: 106), [.stepStarted])
        XCTAssertFalse(timer.isPreparing)
        XCTAssertEqual(timer.stepIndex, 0)
        XCTAssertEqual(timer.remainingSeconds, 5)
        XCTAssertEqual(timer.currentStep?.name, "Squats")
        XCTAssertEqual(timer.totalRemaining, 11)
        XCTAssertEqual(timer.tick(now: 111), [.stepStarted])
        XCTAssertEqual(timer.currentStep?.kind, .rest)
        XCTAssertEqual(timer.tick(now: 117), [.completed])
    }

    func testPreparationCanPauseAndResumeWithoutLosingTime() {
        var timer = WorkoutTimeline(routine: sample())
        _ = timer.start(now: 0)
        _ = timer.pause(now: 1.25)
        XCTAssertTrue(timer.isPreparing)
        XCTAssertEqual(timer.remaining, 4.75)
        XCTAssertEqual(timer.tick(now: 100), [])
        timer.resume(now: 100)
        XCTAssertEqual(timer.tick(now: 104.75), [.stepStarted])
        XCTAssertEqual(timer.remainingSeconds, 5)
    }

    func testSkippingPreparationStartsFirstExerciseAndKeepsPauseState() {
        var timer = WorkoutTimeline(routine: sample())
        _ = timer.start(now: 0)
        _ = timer.pause(now: 1)
        XCTAssertEqual(timer.skip(now: 1), [.stepStarted])
        XCTAssertEqual(timer.state, .paused)
        XCTAssertFalse(timer.isPreparing)
        XCTAssertEqual(timer.stepIndex, 0)
        XCTAssertEqual(timer.remainingSeconds, 5)
    }

    func testDelayedPreparationTickUsesOriginalDeadline() {
        var timer = WorkoutTimeline(routine: sample())
        _ = timer.start(now: 0)
        XCTAssertEqual(timer.tick(now: 7.5), [.stepStarted])
        XCTAssertEqual(timer.remaining, 3.5)
        XCTAssertEqual(timer.stepIndex, 0)
        XCTAssertEqual(timer.tick(now: 100), [.completed])
        XCTAssertEqual(timer.tick(now: 101), [])
    }

    func testAdvancesThroughExerciseRestAndCompletion() {
        var timer = WorkoutTimeline(routine: sample(), preparationSeconds: 0)
        XCTAssertTrue(timer.start(now: 100) == [.stepStarted])
        XCTAssertTrue(timer.tick(now: 105) == [.stepStarted])
        XCTAssertTrue(timer.currentStep?.kind == .rest)
        XCTAssertTrue(timer.remainingSeconds == 2)
        XCTAssertTrue(timer.tick(now: 107) == [.stepStarted])
        XCTAssertTrue(timer.currentStep?.name == "Plank")
        XCTAssertTrue(timer.tick(now: 111) == [.completed])
        XCTAssertTrue(timer.state == .completed)
        XCTAssertTrue(timer.totalRemaining == 0)
        XCTAssertTrue(timer.tick(now: 112).isEmpty)
    }

    func testDelayedTicksDoNotAccumulateDrift() {
        var timer = WorkoutTimeline(routine: sample(), preparationSeconds: 0)
        _ = timer.start(now: 0)
        XCTAssertTrue(timer.tick(now: 8.4) == [.stepStarted])
        XCTAssertTrue(timer.stepIndex == 2)
        XCTAssertTrue(abs(timer.remaining - 2.6) < 0.0001)
        XCTAssertTrue(timer.tick(now: 11) == [.completed])
    }

    func testLateTickCompletesOnlyOnce() {
        var timer = WorkoutTimeline(routine: sample(), preparationSeconds: 0)
        _ = timer.start(now: 0)
        XCTAssertTrue(timer.tick(now: 1000) == [.completed])
        XCTAssertTrue(timer.tick(now: 1001) == [])
    }

    func testPauseAndResumePreserveFractionalSeconds() {
        var timer = WorkoutTimeline(routine: sample(), preparationSeconds: 0)
        _ = timer.start(now: 0)
        _ = timer.pause(now: 1.25)
        XCTAssertTrue(timer.remaining == 3.75)
        XCTAssertTrue(timer.state == .paused)
        XCTAssertTrue(timer.tick(now: 100).isEmpty)
        XCTAssertTrue(timer.remaining == 3.75)
        timer.resume(now: 100)
        XCTAssertTrue(timer.tick(now: 103.75) == [.stepStarted])
        XCTAssertTrue(timer.currentStep?.kind == .rest)
    }

    func testCountdownBeepOccursOncePerSecond() {
        var timer = WorkoutTimeline(routine: sample(), preparationSeconds: 0)
        _ = timer.start(now: 0)
        XCTAssertTrue(timer.tick(now: 1).isEmpty)
        XCTAssertTrue(timer.tick(now: 2) == [.countdown(3)])
        XCTAssertTrue(timer.tick(now: 2.1).isEmpty)
        XCTAssertTrue(timer.tick(now: 3) == [.countdown(2)])
        XCTAssertTrue(timer.tick(now: 4) == [.countdown(1)])
        XCTAssertTrue(timer.tick(now: 5) == [.stepStarted])
    }

    func testShortStepDoesNotImmediatelyInterruptItsStartingTone() {
        var timer = WorkoutTimeline(routine: Routine(name: "Short", steps: [.init(kind: .exercise, name: "Move", seconds: 3)]), preparationSeconds: 0)
        XCTAssertTrue(timer.start(now: 0) == [.stepStarted])
        XCTAssertTrue(timer.tick(now: 0.05).isEmpty)
        XCTAssertTrue(timer.tick(now: 1) == [.countdown(2)])
        XCTAssertTrue(timer.tick(now: 2) == [.countdown(1)])
        XCTAssertTrue(timer.tick(now: 3) == [.completed])
    }

    func testSkipWhilePausedKeepsNextStepPaused() {
        var timer = WorkoutTimeline(routine: sample(), preparationSeconds: 0)
        _ = timer.start(now: 0)
        _ = timer.pause(now: 1)
        XCTAssertTrue(timer.skip(now: 10) == [.stepStarted])
        XCTAssertTrue(timer.state == .paused)
        XCTAssertTrue(timer.remainingSeconds == 2)
        XCTAssertTrue(timer.stepIndex == 1)
        timer.resume(now: 50)
        XCTAssertTrue(timer.tick(now: 52) == [.stepStarted])
    }

    func testSkippingFinalStepCompletesOnce() {
        var timer = WorkoutTimeline(routine: sample(), preparationSeconds: 0)
        _ = timer.start(now: 0)
        _ = timer.skip(now: 1)
        _ = timer.skip(now: 1)
        XCTAssertTrue(timer.skip(now: 1) == [.completed])
        XCTAssertTrue(timer.skip(now: 1) == [])
    }

    func testPauseAtBoundaryAdvancesBeforePausing() {
        var timer = WorkoutTimeline(routine: sample(), preparationSeconds: 0)
        _ = timer.start(now: 0)
        XCTAssertTrue(timer.pause(now: 5) == [.stepStarted])
        XCTAssertTrue(timer.state == .paused)
        XCTAssertTrue(timer.currentStep?.kind == .rest)
    }

    func testPauseAtFinishStaysComplete() {
        var timer = WorkoutTimeline(routine: sample(), preparationSeconds: 0)
        _ = timer.start(now: 0)
        XCTAssertTrue(timer.pause(now: 11) == [.completed])
        XCTAssertTrue(timer.state == .completed)
        timer.resume(now: 20)
        XCTAssertTrue(timer.state == .completed)
    }

    func testInvalidRoutinesCannotStart() {
        for routine in [Routine(name: "Empty", steps: []), Routine(name: "Zero", steps: [.init(kind: .exercise, name: "Plank", seconds: 0)])] {
            var timer = WorkoutTimeline(routine: routine, preparationSeconds: 0)
            XCTAssertTrue(timer.start(now: 0).isEmpty)
            XCTAssertTrue(timer.state == .ready)
        }
    }

    func testTotalTimeAndProgressStayWithinBounds() {
        var timer = WorkoutTimeline(routine: sample(), preparationSeconds: 0)
        XCTAssertTrue(timer.totalRemaining == 11)
        XCTAssertTrue(timer.stepProgress == 0)
        _ = timer.start(now: 0)
        _ = timer.tick(now: 2.5)
        XCTAssertTrue(timer.totalRemaining == 9)
        XCTAssertTrue(timer.stepProgress == 0.5)
        _ = timer.tick(now: 100)
        XCTAssertTrue(timer.stepProgress == 1)
    }
}
