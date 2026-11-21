import SwiftUI

@MainActor @Observable
final class RoutineStore {
    private(set) var routines: [Routine] = []
    var errorMessage: String?
    private let file: RoutineFileStore
    private var loadFailed = false

    init() {
        let manager = FileManager.default
        let base = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let testing = ProcessInfo.processInfo.arguments.contains("-ui-testing")
        file = RoutineFileStore(url: base.appendingPathComponent(testing ? "TempoUITests/routines.json" : "Tempo/routines.json"))
        if testing && !ProcessInfo.processInfo.arguments.contains("-preserve-routines") {
            try? manager.removeItem(at: file.url)
        }
        do {
            if let saved = try file.load() {
                routines = saved
            } else {
                routines = [Routine.starter]
                try file.save(routines)
            }
        } catch {
            loadFailed = true
            errorMessage = "Your routines couldn’t be opened. Your saved file has been kept safe. Close and reopen Tempo to try again."
        }
    }

    @discardableResult
    func save(_ routine: Routine) -> Bool {
        guard routine.isValid else { return false }
        var updated = routines
        var clean = routine
        clean.name = clean.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = updated.firstIndex(where: { $0.id == clean.id }) {
            updated[index] = clean
        } else {
            updated.append(clean)
        }
        return persist(updated)
    }

    @discardableResult
    func delete(_ id: UUID) -> Bool { persist(routines.filter { $0.id != id }) }

    func duplicate(_ routine: Routine) {
        var copy = routine
        copy.id = UUID()
        copy.name += " copy"
        copy.steps = copy.steps.map { step in
            var next = step
            next.id = UUID()
            return next
        }
        save(copy)
    }

    private func persist(_ updated: [Routine]) -> Bool {
        guard !loadFailed else {
            errorMessage = "Saving is unavailable until your existing routines can be read. Close and reopen Tempo to try again."
            return false
        }
        do {
            try file.save(updated)
            routines = updated
            return true
        } catch {
            errorMessage = "Your changes couldn’t be saved. Check the free space on your device and try again."
            return false
        }
    }
}
