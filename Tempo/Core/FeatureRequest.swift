import Foundation

struct FeatureRequestSubmission: Codable, Equatable, Sendable {
    let requestId: String
    let title: String
    let description: String
    let appVersion: String
    let email: String
}

struct FeatureRequestDraft: Codable, Equatable, Sendable {
    var title = ""
    var details = ""
    var email = ""
    var pending: FeatureRequestSubmission?

    var isEmpty: Bool { title.isEmpty && details.isEmpty && email.isEmpty && pending == nil }
    var titleError: String? {
        let text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return (3...120).contains(text.unicodeScalars.count) && !Self.hasControls(title, allowLines: false)
            ? nil : "Use a single-line title of 3–120 characters."
    }
    var detailsError: String? {
        let text = details.trimmingCharacters(in: .whitespacesAndNewlines)
        return (10...4000).contains(text.unicodeScalars.count) && !Self.hasControls(details, allowLines: true)
            ? nil : "Add 10–4,000 characters describing your idea."
    }
    var emailError: String? {
        return Self.normalizedEmail(email) == nil ? "Enter a reply email such as you@example.com." : nil
    }
    var isValid: Bool { titleError == nil && detailsError == nil && emailError == nil }

    func submission(appVersion: String) throws -> FeatureRequestSubmission {
        if let problem = titleError ?? detailsError ?? emailError { throw FeatureRequestError.validation(problem) }
        guard let replyEmail = Self.normalizedEmail(email) else { throw FeatureRequestError.validation("Enter a reply email such as you@example.com.") }
        let result = FeatureRequestSubmission(requestId: UUID().uuidString.lowercased(),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            description: details.trimmingCharacters(in: .whitespacesAndNewlines),
            appVersion: appVersion, email: replyEmail)
        if try JSONEncoder().encode(result).count > 24 * 1024 {
            throw FeatureRequestError.validation("Your request is too large. Please shorten the details.")
        }
        return result
    }

    static func normalizedEmail(_ raw: String) -> String? {
        guard !hasControls(raw, allowLines: false) else { return nil }
        let email = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard email.utf8.count <= 254 else { return nil }
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let local = String(parts[0]), domain = String(parts[1])
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!#$%&'*+/=?^_`{|}~.-")
        guard !local.isEmpty, local.utf8.count <= 64, local.unicodeScalars.allSatisfy(allowed.contains),
              !local.hasPrefix("."), !local.hasSuffix("."), !local.contains("..") else { return nil }
        let labels = domain.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy({ label in
            label.utf8.count <= 63 && String(label).range(of: "^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?$", options: .regularExpression) != nil
        }) else { return nil }
        return "\(local)@\(domain.lowercased())"
    }

    private static func hasControls(_ value: String, allowLines: Bool) -> Bool {
        value.unicodeScalars.contains { scalar in
            if allowLines && [9, 10, 13].contains(scalar.value) { return false }
            return scalar.value < 32 || scalar.value == 127
        }
    }
}

enum FeatureRequestError: Error, LocalizedError, Sendable {
    case validation(String)
    case rejected
    case retryLater
    case unconfirmed

    var errorDescription: String? {
        switch self {
        case .validation(let message): return message
        case .rejected: return "This request couldn’t be accepted. You can discard it and start again."
        case .retryLater: return "Please wait a moment, then try again. Your request is saved."
        case .unconfirmed: return "We couldn’t confirm receipt. Your request is saved; retrying won’t send a duplicate."
        }
    }
}
