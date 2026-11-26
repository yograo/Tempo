import Foundation

extension FeatureRequestComposer {
    static func configured() -> FeatureRequestComposer {
        let arguments = ProcessInfo.processInfo.arguments
        #if DEBUG
        let testing = arguments.contains("-ui-testing")
        #else
        let testing = false
        #endif
        let directory = URL.applicationSupportDirectory.appendingPathComponent("Tempo", isDirectory: true)
        let store = FeatureRequestDraftFileStore(url: directory.appendingPathComponent(testing ? "feature-request-ui-test.json" : "feature-request-draft.json"))
        if testing && !arguments.contains("-preserve-feature-request") { try? store.clear() }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        #if DEBUG
        if testing {
            return FeatureRequestComposer(sender: FeatureRequestUITestSender(failOnce: arguments.contains("-feature-request-fail-once")), storage: store, appVersion: version)
        }
        #endif
        return FeatureRequestComposer(sender: FeatureRequestClient(), storage: store, appVersion: version)
    }
}

#if DEBUG
private actor FeatureRequestUITestSender: FeatureRequestSending {
    private var shouldFail: Bool
    init(failOnce: Bool) { shouldFail = failOnce }
    func send(_ submission: FeatureRequestSubmission) async throws {
        try await Task.sleep(for: .milliseconds(500))
        if shouldFail { shouldFail = false; throw URLError(.notConnectedToInternet) }
    }
}
#endif
