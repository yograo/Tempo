import Foundation
import XCTest
@testable import TempoCore

final class FeatureRequestTests: XCTestCase {
    private func draft(email: String = "reply@example.com") -> FeatureRequestDraft {
        FeatureRequestDraft(title: "  Repeat exercise blocks  ", details: "Please repeat a group of exercises five times.", email: email)
    }

    func testRequiredEmailAndNormalizedSubmission() throws {
        let submission = try draft().submission(appVersion: "1.0")
        XCTAssertEqual(submission.email, "reply@example.com")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(submission)) as? [String: Any])
        XCTAssertEqual(json["email"] as? String, "reply@example.com")
        XCTAssertEqual(submission.title, "Repeat exercise blocks")
        XCTAssertNotNil(UUID(uuidString: submission.requestId))
        XCTAssertEqual(submission.requestId[submission.requestId.index(submission.requestId.startIndex, offsetBy: 14)], "4")
        XCTAssertEqual(try draft(email: " Ada+tempo@EXAMPLE.test ").submission(appVersion: "1.0").email, "Ada+tempo@example.test")
        XCTAssertFalse(draft(email: "   ").isValid)
        XCTAssertFalse(draft(email: "").isValid)
    }

    func testInvalidEmailAndUnicodeLimits() {
        for email in ["a@@example.com", "a@.test", "a@-example.test", ".a@example.com", "a..b@example.com",
                      "a@example..test", "a b@example.com", "a@example.com\r\nBcc: b@example.com", "\ta@example.com",
                      "é@example.com", String(repeating: "a", count: 65) + "@example.com", "a@" + String(repeating: "b", count: 64) + ".com"] {
            XCTAssertFalse(draft(email: email).isValid, email)
        }
        var value = draft()
        value.title = String(repeating: "🏋️", count: 60) // Two Unicode scalars each, matching the API.
        value.details = String(repeating: "😀", count: 4000)
        XCTAssertTrue(value.isValid)
        value.title += "x"
        XCTAssertFalse(value.isValid)
        value = draft()
        value.details = "Please add\u{0} something"
        XCTAssertFalse(value.isValid)
    }

    func testClientEncodesContractAndRequiresMatchingReceipt() async throws {
        let submission = try draft(email: "reply@example.com").submission(appVersion: "1.0")
        let client = FeatureRequestClient { request in
            XCTAssertEqual(request.url, FeatureRequestClient.endpoint)
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertEqual(try JSONDecoder().decode(FeatureRequestSubmission.self, from: XCTUnwrap(request.httpBody)), submission)
            let data = try JSONSerialization.data(withJSONObject: ["requestId": submission.requestId, "status": "received"])
            return (data, HTTPURLResponse(url: FeatureRequestClient.endpoint, statusCode: 202, httpVersion: nil, headerFields: nil)!)
        }
        try await client.send(submission)
        for responseBody in ["{}", "{\"requestId\":\"another-id\",\"status\":\"received\"}"] {
            let invalid = FeatureRequestClient { _ in
                (Data(responseBody.utf8), HTTPURLResponse(url: FeatureRequestClient.endpoint, statusCode: 202, httpVersion: nil, headerFields: nil)!)
            }
            do { try await invalid.send(submission); XCTFail("Invalid receipt must not clear the draft") }
            catch { XCTAssertEqual(error.localizedDescription, FeatureRequestError.unconfirmed.localizedDescription) }
        }
    }

    func testClientTreatsFailuresAsFailuresWithoutExposingResponseText() async throws {
        let submission = try draft().submission(appVersion: "1.0")
        for status in [200, 400, 403, 429, 500, 503] {
            let client = FeatureRequestClient { _ in
                (Data("private server detail".utf8), HTTPURLResponse(url: FeatureRequestClient.endpoint, statusCode: status, httpVersion: nil, headerFields: nil)!)
            }
            do { try await client.send(submission); XCTFail("Expected failure for \(status)") }
            catch { XCTAssertFalse(error.localizedDescription.contains("private server detail")) }
        }
    }

    @MainActor
    func testFailedRequestSurvivesRelaunchAndRetriesIdenticalPayload() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = FeatureRequestDraftFileStore(url: folder.appendingPathComponent("draft.json"))
        let sender = RecordingFeatureSender(failOnce: true)
        let composer = FeatureRequestComposer(sender: sender, storage: file)
        composer.draft = draft(email: "Ada+tempo@EXAMPLE.test")
        composer.saveDraft()
        await composer.send()
        XCTAssertFalse(composer.isSubmitted)
        let original = try XCTUnwrap(composer.draft.pending)
        XCTAssertEqual(try file.load().pending, original)
        XCTAssertTrue(try file.url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        let restored = FeatureRequestComposer(sender: sender, storage: file, appVersion: "2.0")
        XCTAssertEqual(restored.draft.pending, original)
        await restored.send()
        XCTAssertTrue(restored.isSubmitted)
        let calls = await sender.submissions()
        XCTAssertEqual(calls, [original, original])
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.url.path))
    }

    @MainActor
    func testNoNetworkRequestWhenSavingFails() async {
        let sender = RecordingFeatureSender()
        let composer = FeatureRequestComposer(sender: sender, storage: UnwritableFeatureDraftStore())
        composer.draft = draft()
        await composer.send()
        let calls = await sender.submissions()
        XCTAssertTrue(calls.isEmpty)
        XCTAssertNil(composer.draft.pending)
        XCTAssertFalse(composer.isSubmitted)
        XCTAssertNotNil(composer.message)
    }

    @MainActor
    func testCorruptDraftIsPreservedUntilExplicitDiscard() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = FeatureRequestDraftFileStore(url: folder.appendingPathComponent("draft.json"))
        let original = Data("broken saved request".utf8)
        try original.write(to: file.url)
        let composer = FeatureRequestComposer(sender: RecordingFeatureSender(), storage: file)
        XCTAssertTrue(composer.cannotLoadDraft)
        composer.saveDraft()
        XCTAssertEqual(try Data(contentsOf: file.url), original)
        XCTAssertFalse(composer.canSend)
        composer.discard()
        XCTAssertFalse(composer.cannotLoadDraft)
        XCTAssertTrue(composer.draft.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.url.path))
    }

    @MainActor
    func testRepeatedSendWhileInFlightMakesOneRequest() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let sender = RecordingFeatureSender()
        let composer = FeatureRequestComposer(sender: sender, storage: FeatureRequestDraftFileStore(url: folder.appendingPathComponent("draft.json")))
        composer.draft = draft()
        async let first: Void = composer.send()
        async let second: Void = composer.send()
        _ = await (first, second)
        let calls = await sender.submissions()
        XCTAssertEqual(calls.count, 1)
    }
}

private actor RecordingFeatureSender: FeatureRequestSending {
    private var received: [FeatureRequestSubmission] = []
    private var failOnce: Bool
    init(failOnce: Bool = false) { self.failOnce = failOnce }
    func send(_ submission: FeatureRequestSubmission) async throws {
        received.append(submission)
        try await Task.sleep(for: .milliseconds(20))
        if failOnce { failOnce = false; throw URLError(.timedOut) }
    }
    func submissions() -> [FeatureRequestSubmission] { received }
}

private struct UnwritableFeatureDraftStore: FeatureRequestDraftPersistence {
    func load() throws -> FeatureRequestDraft { FeatureRequestDraft() }
    func save(_ draft: FeatureRequestDraft) throws { throw CocoaError(.fileWriteOutOfSpace) }
    func clear() throws {}
}
