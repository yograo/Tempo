import SwiftUI

@MainActor @Observable
final class WorkoutStore {
    private(set) var archive = WorkoutArchive()
    private(set) var controller: WorkoutController?
    private(set) var errorMessage: String?
    let alerts = WorkoutAlerts()
    private let file: WorkoutHistoryFileStore
    private var loadFailed = false

    init() {
        let manager = FileManager.default
        let base = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let args = ProcessInfo.processInfo.arguments
        let testing = args.contains("-ui-testing")
        file = WorkoutHistoryFileStore(url: base.appendingPathComponent(testing ? "TempoUITests/history.json" : "Tempo/history.json"))
        if testing && !args.contains("-preserve-routines") {
            try? manager.removeItem(at: file.url)
            UserDefaults.standard.removeObject(forKey: "spokenCuesEnabled")
        }
        do { archive = try file.load() }
        catch {
            loadFailed = true
            errorMessage = "Your workout history couldn’t be opened. The saved file has been preserved. Close and reopen Tempo to try again."
        }
        WorkoutLiveActivity.removeOrphans(keeping: archive.active?.id)
        if let active = archive.active {
            controller = WorkoutController(saved: active, store: self)
        } else {
            alerts.clear()
        }
    }

    func start(_ routine: Routine) {
        guard controller == nil, routine.isValid else { return }
        controller = WorkoutController(routine: routine, store: self)
    }

    func close() {
        controller?.stop()
        controller = nil
    }

    func checkpoint(_ workout: SavedWorkout) {
        guard !archive.records.contains(where: { $0.id == workout.id }) else { return }
        archive.active = workout
        persist()
    }

    func finish(_ record: WorkoutRecord) {
        archive.finish(record)
        persist()
    }

    func delete(_ id: UUID) {
        archive.records.removeAll { $0.id == id }
        persist()
    }

    func retrySave() { persist() }

    private func persist() {
        guard !loadFailed else { return }
        do {
            try file.save(archive)
            errorMessage = nil
        } catch {
            errorMessage = "Workout history couldn’t be saved. Free some space, then tap Retry. Keep Tempo open until saving succeeds."
        }
    }
}
