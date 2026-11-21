import Foundation
import XCTest
@testable import TempoCore

final class RoutinePersistenceTests: XCTestCase {
    func testSelectedRoutineAndExerciseIconsSurviveSaving() throws {
        for icon in ExerciseIcon.allCases {
            var routine = Routine.starter
            routine.selectedIcon = icon
            routine.steps[0].selectedIcon = .core
            let restored = try JSONDecoder().decode(Routine.self, from: JSONEncoder().encode(routine))
            XCTAssertEqual(restored, routine)
            XCTAssertEqual(restored.selectedIcon, icon)
            XCTAssertEqual(restored.steps[0].selectedIcon, .core)
            XCTAssertEqual(restored.steps[1].symbol, "wind")
        }
    }

    func testRoutinesSavedBeforeIconSelectionStillOpen() throws {
        var routine = Routine.starter
        routine.selectedIcon = .yoga
        routine.steps[0].selectedIcon = .core
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(routine)) as? [String: Any])
        legacy.removeValue(forKey: "icon")
        legacy["steps"] = (legacy["steps"] as! [[String: Any]]).map { step in
            var oldStep = step
            oldStep.removeValue(forKey: "icon")
            return oldStep
        }
        let restored = try JSONDecoder().decode(Routine.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(restored.id, routine.id)
        XCTAssertEqual(restored.steps.map(\.id), routine.steps.map(\.id))
        XCTAssertEqual(restored.selectedIcon, .intervals)
        XCTAssertEqual(restored.steps[0].selectedIcon, .strength)
        XCTAssertTrue(restored.isValid)
    }

    func testRoutinesRoundTripWithStableStepOrderAndIDs() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = RoutineFileStore(url: folder.appendingPathComponent("routines.json"))
        XCTAssertTrue(try file.load() == nil)
        let routines = (0..<150).map { Routine(name: "Routine \($0)", steps: Routine.starter.steps) }
        try file.save(routines)
        XCTAssertTrue(try file.load() == routines)
        try file.save([])
        XCTAssertTrue(try file.load() == [])
    }

    func testCorruptSaveIsNotSilentlyOverwritten() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = RoutineFileStore(url: folder.appendingPathComponent("routines.json"))
        let original = Data("not valid json".utf8)
        try original.write(to: file.url)
        XCTAssertThrowsError(try file.load())
        XCTAssertTrue(try Data(contentsOf: file.url) == original)
    }

    func testInvalidDurationsInSavedDataAreRejected() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = RoutineFileStore(url: folder.appendingPathComponent("routines.json"))
        try file.save([Routine(name: "Broken", steps: [.init(kind: .exercise, name: "Plank", seconds: -1)])])
        XCTAssertThrowsError(try file.load())
    }

    func testRequiresNameAndAtLeastOneValidExercise() {
        XCTAssertTrue(!Routine(name: "  ", steps: Routine.starter.steps).isValid)
        XCTAssertTrue(!Routine(name: "Rest only", steps: [.init(kind: .rest, name: "Rest", seconds: 15)]).isValid)
        XCTAssertTrue(!RoutineStep(kind: .exercise, name: " ", seconds: 30).isValid)
        XCTAssertTrue(!RoutineStep(kind: .exercise, name: "Plank", seconds: 3600).isValid)
        XCTAssertTrue(RoutineStep(kind: .exercise, name: "Plank", seconds: 1).isValid)
        XCTAssertTrue(RoutineStep(kind: .rest, name: "", seconds: 15).displayName == "Rest")
        XCTAssertTrue(Routine.starter.isValid)
    }

    func testDurationsAreFormattedClearly() {
        XCTAssertTrue(DurationText.clock(65) == "01:05")
        XCTAssertTrue(DurationText.clock(-1) == "00:00")
        XCTAssertTrue(DurationText.short(15) == "15s")
        XCTAssertTrue(DurationText.short(60) == "1 min")
        XCTAssertTrue(DurationText.short(75) == "1m 15s")
    }
}
