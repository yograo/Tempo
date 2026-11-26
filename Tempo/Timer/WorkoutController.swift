import AVFoundation
import Darwin
import SwiftUI
import UserNotifications

@MainActor @Observable
final class WorkoutController: Identifiable {
    let id = UUID()
    private(set) var timeline: WorkoutTimeline
    private(set) var soundEnabled = true
    private(set) var speechEnabled: Bool
    private(set) var pausedAutomatically = false
    private(set) var audioUnavailable = false
    private(set) var preparingCues = false
    private(set) var lockScreenMessage = "The timer keeps running when your screen locks."
    private let tones = TonePlayer()
    private let speech = SpokenCuePlayer()
    private let cueFiles = SpokenCueFiles()
    private let liveActivity = WorkoutLiveActivity()
    private let alerts: WorkoutAlerts
    private weak var store: WorkoutStore?
    private var sessionID = UUID()
    private var startedAt = Date()
    private var files: [String: String] = [:]
    private var foreground = true
    private var stopped = false
    private var recorded = false
    private var didPrepare = false
    private var attemptedPhrases: Set<String> = []
    private var audioPreparation: Task<Void, Never>?

    init(routine: Routine, store: WorkoutStore) {
        timeline = WorkoutTimeline(routine: routine)
        self.store = store
        alerts = store.alerts
        speechEnabled = UserDefaults.standard.object(forKey: "spokenCuesEnabled") as? Bool ?? true
    }

    init(saved: SavedWorkout, store: WorkoutStore) {
        timeline = saved.timeline
        self.store = store
        alerts = store.alerts
        sessionID = saved.id
        startedAt = saved.startedAt
        soundEnabled = saved.soundEnabled
        speechEnabled = saved.speechEnabled
        files = saved.speechFiles ?? [:]
        // Rebase across process launches (including a device restart). While running,
        // mach_continuous_time includes device sleep and ignores wall-clock changes.
        let elapsed = max(0, Date().timeIntervalSince(saved.savedAt))
        _ = timeline.restore(savedClock: saved.savedClock, now: Self.clock, elapsed: elapsed)
    }

    private static var clock: Double {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(mach_continuous_time()) * Double(info.numer) / Double(info.denom) / 1_000_000_000
    }
    private var now: Double { Self.clock }
    var historyError: String? { store?.errorMessage }

    func start() async {
        guard !didPrepare, !stopped else { return }
        didPrepare = true
        preparingCues = true
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        // Never hold a running, restored workout while rebuilding notification audio.
        if timeline.state == .ready && speechEnabled && (settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional) {
            let phrases = Array(timeline.routine.steps.prefix(63)).map(WorkoutCues.step) + [WorkoutCues.completion]
            attemptedPhrases.formUnion(phrases)
            files = await cueFiles.prepare(phrases)
        }
        preparingCues = false
        guard !Task.isCancelled, !stopped else { return }
        tones.prepare()
        audioUnavailable = tones.unavailable
        if timeline.state == .ready {
            startedAt = Date()
            let events = timeline.start(now: now)
            if soundEnabled && speechEnabled {
                speech.speak("Get ready.")
            } else { handle(events) }
        } else {
            tick()
        }
        synchronize()
    }

    func tick() {
        guard !stopped, !preparingCues else { return }
        let events = timeline.tick(now: now)
        handle(events)
        if timeline.state == .completed && !recorded { finish() }
        if events.contains(.stepStarted) { checkpoint() }
        updateIdleTimer()
    }

    func togglePause() {
        guard !preparingCues else { return }
        if timeline.state == .running {
            handle(timeline.pause(now: now))
            silence()
        } else if timeline.state == .paused {
            tones.prepare()
            timeline.resume(now: now)
            pausedAutomatically = false
            announceCurrentStep()
        }
        synchronize()
    }

    func pauseForInterruption() {
        guard foreground, UIApplication.shared.applicationState == .active, timeline.state == .running else { return }
        _ = timeline.pause(now: now)
        pausedAutomatically = timeline.state == .paused
        silence()
        synchronize()
    }

    func leaveForeground() {
        foreground = false
        tick()
        tones.releaseSession()
        speech.stop()
        checkpoint()
        // Give pending notification changes a short opportunity to finish; this is
        // not used to keep the timer executing while iOS suspends the app.
        let task = WorkoutBackgroundSave()
        Task {
            await alerts.flush()
            task.end()
        }
    }

    func returnToForeground() {
        tick() // Catch up silently; never replay missed interval announcements.
        foreground = true
        if soundEnabled { tones.prepare() }
        if didPrepare { synchronize() }
    }

    func skip() {
        guard !preparingCues else { return }
        silence()
        handle(timeline.skip(now: now))
        synchronize()
    }

    func toggleSound() {
        soundEnabled.toggle()
        if !soundEnabled { silence() }
        else { tones.prepare() }
        synchronize()
    }

    func toggleSpeech() {
        speechEnabled.toggle()
        UserDefaults.standard.set(speechEnabled, forKey: "spokenCuesEnabled")
        speech.stop()
        synchronize()
    }

    func restart() {
        liveActivity.end()
        alerts.clear()
        sessionID = UUID()
        startedAt = Date()
        recorded = false
        timeline = WorkoutTimeline(routine: timeline.routine)
        pausedAutomatically = false
        handle(timeline.start(now: now))
        synchronize()
    }

    func stop() {
        guard !stopped else { return }
        _ = timeline.pause(now: now)
        if timeline.state != .ready { finish(endedEarly: timeline.state != .completed) }
        stopped = true
        audioPreparation?.cancel()
        silence()
        tones.releaseSession()
        alerts.clear()
        liveActivity.end()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func retrySave() { store?.retrySave() }

    private func handle(_ events: [WorkoutTimeline.Event]) {
        guard foreground else { return }
        for event in events {
            if soundEnabled && timeline.state != .paused {
                if speechEnabled {
                    switch event {
                    case .countdown(let value): speech.speak(String(value))
                    case .stepStarted: announceCurrentStep()
                    case .completed: speech.speak(WorkoutCues.completion)
                    }
                } else {
                    tones.play(event)
                    audioUnavailable = tones.unavailable
                }
            }
            switch event {
            case .stepStarted: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            case .completed: UINotificationFeedbackGenerator().notificationOccurred(.success)
            case .countdown: break
            }
        }
    }

    private func announceCurrentStep() {
        guard foreground, soundEnabled, speechEnabled else { return }
        if let step = timeline.currentStep { speech.speak(WorkoutCues.step(step)) }
        else if timeline.isPreparing { speech.speak("Get ready.") }
    }

    private func synchronize() {
        guard !stopped, !preparingCues, timeline.state != .ready else { return }
        if timeline.state == .completed { finish() }
        else { checkpoint() }
        let plan = WorkoutAlertPlan(timeline: timeline)
        alerts.replace(id: sessionID, plan: plan, date: Date(), sound: soundEnabled, speech: speechEnabled, files: files)
        prepareUpcomingSpeech(plan)
        liveActivity.update(id: sessionID, timeline: timeline)
        Task {
            await alerts.flush()
            var messages: [String] = []
            if alerts.unavailable { messages.append("Enable notifications in Settings for locked-screen interval alerts.") }
            else if plan.truncated { messages.append("Lock Screen alerts cover the next 63 intervals and the finish. Reopen Tempo to refresh them.") }
            else { messages.append("The timer keeps running when your screen locks. Alerts follow Focus and notification settings.") }
            if liveActivity.unavailable { messages.append("The Lock Screen countdown is unavailable. Check Live Activities in Settings.") }
            lockScreenMessage = messages.joined(separator: " ")
        }
        updateIdleTimer()
    }

    private func checkpoint() {
        guard timeline.state != .ready, !recorded else { return }
        store?.checkpoint(SavedWorkout(id: sessionID, startedAt: startedAt, timeline: timeline,
            savedAt: Date(), savedClock: now, soundEnabled: soundEnabled, speechEnabled: speechEnabled, speechFiles: files))
    }

    private func prepareUpcomingSpeech(_ plan: WorkoutAlertPlan) {
        guard foreground, speechEnabled, !plan.cues.isEmpty else { return }
        let phrases = plan.cues.map(\.text).filter { files[$0] == nil && !attemptedPhrases.contains($0) }
        guard !phrases.isEmpty else { return }
        attemptedPhrases.formUnion(phrases)
        let session = sessionID
        let previous = audioPreparation
        audioPreparation = Task {
            await previous?.value
            guard !stopped, !Task.isCancelled, session == sessionID else { return }
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let generated = await cueFiles.prepare(phrases)
            guard !stopped, !Task.isCancelled, session == sessionID else { return }
            files.merge(generated) { _, latest in latest }
            synchronize()
        }
    }

    private func finish(endedEarly: Bool = false) {
        guard !recorded else { return }
        recorded = true
        let overrun = timeline.completedAt.map { max(0, now - $0) } ?? 0
        store?.finish(WorkoutRecord(id: sessionID, routineID: timeline.routine.id, routineName: timeline.routine.name,
            icon: timeline.routine.selectedIcon, startedAt: startedAt, endedAt: max(startedAt, Date().addingTimeInterval(-overrun)),
            activeSeconds: timeline.elapsedSeconds, skippedSteps: timeline.skippedSteps,
            outcome: endedEarly ? .endedEarly : .finished))
        alerts.clear()
        liveActivity.update(id: sessionID, timeline: timeline)
    }

    private func silence() { tones.stop(); speech.stop() }
    private func updateIdleTimer() { UIApplication.shared.isIdleTimerDisabled = foreground && timeline.state == .running }
}

@MainActor
private final class WorkoutBackgroundSave {
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    init() {
        identifier = UIApplication.shared.beginBackgroundTask(withName: "Save workout alerts") { [weak self] in self?.end() }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
