import Foundation

protocol FeatureRequestDraftPersistence: Sendable {
    func load() throws -> FeatureRequestDraft
    func save(_ draft: FeatureRequestDraft) throws
    func clear() throws
}

struct FeatureRequestDraftFileStore: FeatureRequestDraftPersistence {
    let url: URL

    func load() throws -> FeatureRequestDraft {
        guard FileManager.default.fileExists(atPath: url.path) else { return FeatureRequestDraft() }
        let draft = try JSONDecoder().decode(FeatureRequestDraft.self, from: Data(contentsOf: url))
        if let pending = draft.pending {
            guard UUID(uuidString: pending.requestId) != nil else { throw CocoaError(.fileReadCorruptFile) }
        }
        return draft
    }

    func save(_ draft: FeatureRequestDraft) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(draft)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        #else
        try data.write(to: url, options: .atomic)
        #endif
        var file = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try file.setResourceValues(values)
    }

    func clear() throws {
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}
