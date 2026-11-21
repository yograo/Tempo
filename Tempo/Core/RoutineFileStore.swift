import Foundation

struct RoutineFileStore {
    let url: URL

    func load() throws -> [Routine]? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let routines = try JSONDecoder().decode([Routine].self, from: Data(contentsOf: url))
        guard routines.allSatisfy(\.isValid), Set(routines.map(\.id)).count == routines.count,
              routines.allSatisfy({ Set($0.steps.map(\.id)).count == $0.steps.count }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return routines
    }

    func save(_ routines: [Routine]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(routines).write(to: url, options: .atomic)
    }
}
