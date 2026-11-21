import SwiftUI

@MainActor @Observable
final class WorkoutController {
    private(set) var timeline: WorkoutTimeline
    var soundEnabled = true
    private(set) var pausedAutomatically = false
    private(set) var audioUnavailable = false
    private let tones = TonePlayer()

    init(routine: Routine) { timeline = WorkoutTimeline(routine: routine) }
    private var now: Double { ProcessInfo.processInfo.systemUptime }

    func start() {
        guard timeline.state == .ready else { return }
        tones.prepare()
        audioUnavailable = tones.unavailable
        handle(timeline.start(now: now))
        updateIdleTimer()
    }

    func tick() {
        handle(timeline.tick(now: now))
        updateIdleTimer()
    }

    func togglePause() {
        if timeline.state == .running {
            handle(timeline.pause(now: now))
        } else if timeline.state == .paused {
            tones.prepare()
            timeline.resume(now: now)
            pausedAutomatically = false
        }
        updateIdleTimer()
    }

    func pauseForInterruption() {
        guard timeline.state == .running else { return }
        handle(timeline.pause(now: now))
        pausedAutomatically = timeline.state == .paused
        tones.stop()
        updateIdleTimer()
    }

    func skip() {
        handle(timeline.skip(now: now))
        updateIdleTimer()
    }

    func toggleSound() {
        soundEnabled.toggle()
        if !soundEnabled { tones.stop() }
    }

    func restart() {
        timeline = WorkoutTimeline(routine: timeline.routine)
        pausedAutomatically = false
        start()
    }

    func stop() {
        _ = timeline.pause(now: now)
        tones.releaseSession()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func handle(_ events: [WorkoutTimeline.Event]) {
        for event in events {
            if soundEnabled {
                tones.play(event)
                audioUnavailable = tones.unavailable
            }
            switch event {
            case .stepStarted: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            case .completed: UINotificationFeedbackGenerator().notificationOccurred(.success)
            case .countdown: break
            }
        }
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = timeline.state == .running
    }
}
