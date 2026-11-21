import Foundation

/// All time inputs use a monotonic clock. Absolute deadlines avoid accumulating timer drift.
struct WorkoutTimeline {
    enum State: Equatable { case ready, running, paused, completed }
    enum Phase: Equatable { case preparation, routine }
    enum Event: Equatable { case stepStarted, countdown(Int), completed }

    let routine: Routine
    let preparationSeconds: Int
    private(set) var state: State = .ready
    private(set) var phase: Phase
    private(set) var stepIndex = 0
    private(set) var remaining: Double
    private var deadline: Double?
    private var lastCountdown: Int?

    init(routine: Routine, preparationSeconds: Int = 6) {
        self.routine = routine
        self.preparationSeconds = max(0, preparationSeconds)
        phase = preparationSeconds > 0 ? .preparation : .routine
        remaining = Double(preparationSeconds > 0 ? preparationSeconds : routine.steps.first?.seconds ?? 0)
    }

    var isPreparing: Bool { phase == .preparation }
    var currentStep: RoutineStep? { !isPreparing && routine.steps.indices.contains(stepIndex) ? routine.steps[stepIndex] : nil }
    var remainingSeconds: Int { Int(ceil(max(0, remaining))) }
    var stepProgress: Double {
        if isPreparing { return min(1, max(0, 1 - remaining / Double(preparationSeconds))) }
        guard let step = currentStep else { return 1 }
        return min(1, max(0, 1 - remaining / Double(step.seconds)))
    }
    var totalRemaining: Int {
        guard state != .completed else { return 0 }
        if isPreparing { return remainingSeconds + routine.totalSeconds }
        return remainingSeconds + routine.steps.dropFirst(stepIndex + 1).reduce(0) { $0 + $1.seconds }
    }

    mutating func start(now: Double) -> [Event] {
        guard state == .ready, routine.isValid else { return [] }
        state = .running
        deadline = now + remaining
        lastCountdown = remainingSeconds
        return isPreparing ? [.countdown(remainingSeconds)] : [.stepStarted]
    }

    mutating func tick(now: Double) -> [Event] {
        guard state == .running, var boundary = deadline else { return [] }
        var moved = false
        while now >= boundary {
            if isPreparing {
                phase = .routine
                boundary += Double(routine.steps[0].seconds)
                moved = true
                lastCountdown = routine.steps[0].seconds
                continue
            }
            guard stepIndex + 1 < routine.steps.count else {
                state = .completed
                remaining = 0
                deadline = nil
                return [.completed]
            }
            stepIndex += 1
            boundary += Double(routine.steps[stepIndex].seconds)
            moved = true
            lastCountdown = routine.steps[stepIndex].seconds
        }
        deadline = boundary
        remaining = max(0, boundary - now)
        if moved { return [.stepStarted] }
        let seconds = remainingSeconds
        if (isPreparing ? seconds > 0 : (1...3).contains(seconds)), seconds != lastCountdown {
            lastCountdown = seconds
            return [.countdown(seconds)]
        }
        return []
    }

    mutating func pause(now: Double) -> [Event] {
        guard state == .running else { return [] }
        let events = tick(now: now)
        if state == .running {
            state = .paused
            deadline = nil
        }
        return events
    }

    mutating func resume(now: Double) {
        guard state == .paused else { return }
        deadline = now + remaining
        state = .running
    }

    mutating func skip(now: Double) -> [Event] {
        guard state == .running || state == .paused else { return [] }
        // Account for a natural boundary before applying an explicit skip.
        let events = tick(now: now)
        guard state != .completed else { return events }
        if isPreparing {
            phase = .routine
            remaining = Double(routine.steps[0].seconds)
            deadline = state == .running ? now + remaining : nil
            lastCountdown = remainingSeconds
            return [.stepStarted]
        }
        guard stepIndex + 1 < routine.steps.count else {
            remaining = 0
            deadline = nil
            state = .completed
            return [.completed]
        }
        stepIndex += 1
        remaining = Double(routine.steps[stepIndex].seconds)
        deadline = state == .running ? now + remaining : nil
        lastCountdown = remainingSeconds
        return [.stepStarted]
    }
}
