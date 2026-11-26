import Foundation

protocol FeatureRequestSending: Sendable {
    func send(_ submission: FeatureRequestSubmission) async throws
}

struct FeatureRequestClient: FeatureRequestSending {
    static let endpoint = URL(string: "https://b9rd3v0sc5.execute-api.us-east-2.amazonaws.com/v1/feature-requests")!
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    private let transport: Transport

    init(transport: @escaping Transport = { request in try await FeatureRequestClient.perform(request) }) { self.transport = transport }

    func send(_ submission: FeatureRequestSubmission) async throws {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(submission)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await transport(request)
        switch response.statusCode {
        case 202:
            struct Receipt: Decodable { let requestId: String; let status: String }
            guard let receipt = try? JSONDecoder().decode(Receipt.self, from: data),
                  receipt.requestId.lowercased() == submission.requestId.lowercased(), receipt.status == "received" else {
                throw FeatureRequestError.unconfirmed
            }
        case 429, 503: throw FeatureRequestError.retryLater
        case 400, 413, 415: throw FeatureRequestError.rejected
        default: throw FeatureRequestError.unconfirmed
        }
    }

    private static func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForResource = 30
        let session = URLSession(configuration: configuration, delegate: NoFeatureRequestRedirects(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw FeatureRequestError.unconfirmed }
        return (data, response)
    }
}

// A request can contain contact details. Never forward it to a redirected host.
private final class NoFeatureRequestRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
