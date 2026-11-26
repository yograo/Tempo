import Foundation
import Observation

@MainActor @Observable
final class FeatureRequestComposer {
    var draft = FeatureRequestDraft()
    private(set) var isSending = false
    private(set) var isSubmitted = false
    private(set) var cannotLoadDraft = false
    private(set) var message: String?
    private let sender: any FeatureRequestSending
    private let storage: any FeatureRequestDraftPersistence
    private let appVersion: String

    init(sender: any FeatureRequestSending, storage: any FeatureRequestDraftPersistence, appVersion: String = "1.0") {
        self.sender = sender
        self.storage = storage
        self.appVersion = appVersion
        do { draft = try storage.load() }
        catch {
            cannotLoadDraft = true
            message = "Your saved request couldn’t be opened. It hasn’t been changed. Try reopening Tempo, or discard it to start again."
        }
    }

    var canSend: Bool { !isSending && !isSubmitted && !cannotLoadDraft && (draft.pending != nil || draft.isValid) }

    func saveDraft() {
        guard !cannotLoadDraft, !isSending, !isSubmitted else { return }
        do { try storage.save(draft) }
        catch { message = "Your draft couldn’t be saved on this device. Check available storage before leaving this screen." }
    }

    func send() async {
        guard canSend else { return }
        isSending = true
        message = nil
        defer { isSending = false }
        let submission: FeatureRequestSubmission
        do { submission = try draft.pending ?? draft.submission(appVersion: appVersion) }
        catch { message = error.localizedDescription; return }
        var saved = draft
        saved.pending = submission
        // Save the immutable payload and its ID before making a network call.
        do { try storage.save(saved); draft = saved }
        catch { message = "Your request couldn’t be saved on this device. Nothing was sent. Check available storage and try again."; return }
        do {
            try await sender.send(submission)
            isSubmitted = true
            do { try storage.clear() }
            catch { message = "Your request was received, but its saved copy couldn’t be cleared from this device." }
        } catch let error as FeatureRequestError { message = error.localizedDescription }
        catch { message = FeatureRequestError.unconfirmed.localizedDescription }
    }

    func discard() {
        guard !isSending else { return }
        do {
            try storage.clear()
            draft = FeatureRequestDraft()
            isSubmitted = false
            cannotLoadDraft = false
            message = nil
        } catch { message = "The saved request couldn’t be cleared. Please try again." }
    }
}
