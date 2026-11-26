import SwiftUI

struct FeatureRequestView: View {
    @Environment(FeatureRequestComposer.self) private var composer
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Field?
    @State private var showingDiscard = false
    private enum Field { case title, details, email }

    var body: some View {
        @Bindable var composer = composer
        Group {
            if composer.isSubmitted { success }
            else {
                Form {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: "lightbulb").font(.system(size: 30)).foregroundStyle(TempoTheme.ink)
                            Text("What would make Tempo better?").font(.system(.title2, design: .rounded, weight: .semibold))
                            Text("Share an idea, a small improvement, or something you wish you could do.")
                                .foregroundStyle(TempoTheme.muted)
                        }.padding(.vertical, 10)
                    }.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))

                    Section {
                        TextField("Give your idea a short title", text: $composer.draft.title)
                            .focused($focused, equals: .title).submitLabel(.next).onSubmit { focused = .details }
                            .accessibilityIdentifier("feature-title")
                    } header: { Text("Title") } footer: {
                        if !composer.draft.title.isEmpty, let error = composer.draft.titleError { Text(error).foregroundStyle(.red) }
                        else { Text("3–120 characters") }
                    }.disabled(composer.isSending || composer.draft.pending != nil || composer.cannotLoadDraft)

                    Section {
                        TextField("How would this help your workouts?", text: $composer.draft.details, axis: .vertical)
                            .lineLimit(5...8)
                            .focused($focused, equals: .details)
                            .accessibilityLabel("Describe your idea").accessibilityIdentifier("feature-details")
                    } header: { Text("Details") } footer: {
                        HStack(alignment: .top) {
                            Text(composer.draft.details.isEmpty ? "How would this help your workouts?" : (composer.draft.detailsError ?? ""))
                            Spacer()
                            Text("\(composer.draft.details.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count)/4,000")
                                .monospacedDigit()
                        }
                    }.disabled(composer.isSending || composer.draft.pending != nil || composer.cannotLoadDraft)

                    Section {
                        TextField("", text: $composer.draft.email, prompt: Text(verbatim: "you@example.com").foregroundStyle(.secondary))
                            .keyboardType(.emailAddress).textContentType(.emailAddress)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .focused($focused, equals: .email).submitLabel(.done).onSubmit { focused = nil }
                            .accessibilityLabel("Reply email, required").accessibilityIdentifier("feature-email")
                    } header: { Text("Reply email · required") } footer: {
                        if !composer.draft.email.isEmpty, let error = composer.draft.emailError { Text(error).foregroundStyle(.red) }
                        else { Text("We need an email so we can reply, including when your idea is available. It’s used only to respond about this request.") }
                    }.disabled(composer.isSending || composer.draft.pending != nil || composer.cannotLoadDraft)

                    Section {
                        if let message = composer.message {
                            Text(message).font(.subheadline).accessibilityIdentifier("feature-error")
                        } else if composer.draft.pending != nil && !composer.isSending {
                            Text("Your request is saved and ready to retry. Retrying won’t send a duplicate.").font(.subheadline)
                        }
                        Button {
                            focused = nil
                            Task { await composer.send() }
                        } label: {
                            HStack {
                                Text(composer.isSending ? "Sending…" : composer.draft.pending == nil ? "Send request" : "Retry request")
                                    .font(.system(.headline, design: .rounded))
                                Spacer()
                                if composer.isSending { ProgressView() }
                                else { Image(systemName: "paperplane") }
                            }.padding(.vertical, 8)
                        }.disabled(!composer.canSend).accessibilityIdentifier("send-feature-request")
                            .listRowBackground(composer.canSend ? TempoTheme.lime : .white)
                    } footer: {
                        Text("Your request and email address are sent privately to Tempo’s developer. They aren’t shown to other users. A draft stays on this device until sent or discarded. Sending requires an internet connection.")
                    }
                }.scrollDismissesKeyboard(.interactively).scrollContentBackground(.hidden)
            }
        }
        .tempoBackground().foregroundStyle(TempoTheme.ink)
        .navigationTitle("Request a feature").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !composer.isSubmitted && (!composer.draft.isEmpty || composer.cannotLoadDraft) {
                    Button("Discard", role: .destructive) { focused = nil; showingDiscard = true }
                        .disabled(composer.isSending).accessibilityIdentifier("discard-feature-request")
                }
            }
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = nil } }
        }
        .confirmationDialog("Discard this saved request?", isPresented: $showingDiscard, titleVisibility: .visible) {
            Button("Discard request", role: .destructive) { composer.discard() }
        } message: {
            Text(composer.draft.pending == nil ? "Your draft will be removed from this device." : "Your saved copy will be removed. If the request already reached us, discarding it won’t remove it from our inbox.")
        }
        .onChange(of: composer.draft) { _, _ in composer.saveDraft() }
        .onDisappear { if composer.isSubmitted { composer.discard() } }
    }

    private var success: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 54)).foregroundStyle(TempoTheme.ink)
                    .padding(22).background(TempoTheme.lime, in: RoundedRectangle(cornerRadius: 26))
                Text("Request received").font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .accessibilityIdentifier("feature-request-received")
                Text("Thanks for helping shape Tempo.").font(.title3)
                if let email = composer.draft.pending?.email {
                    Text("If we have an update about your request, we can reply to \(email).")
                        .foregroundStyle(TempoTheme.muted)
                } else {
                    Text("Your idea is in our inbox.").foregroundStyle(TempoTheme.muted)
                }
                if let message = composer.message { Text(message).font(.footnote) }
                PrimaryButton(title: "Done", symbol: "checkmark") { dismiss() }
                    .accessibilityIdentifier("feature-request-done")
            }.padding(26).padding(.top, 30).frame(maxWidth: 600, alignment: .leading).frame(maxWidth: .infinity)
        }
    }
}
