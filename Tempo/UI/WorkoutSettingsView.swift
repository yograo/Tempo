import SwiftUI
import UserNotifications

struct WorkoutSettingsView: View {
    @AppStorage("spokenCuesEnabled") private var speechEnabled = true
    @Environment(\.scenePhase) private var scenePhase
    @State private var authorization: UNAuthorizationStatus = .notDetermined
    @State private var requesting = false
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                Toggle("Spoken cues", isOn: $speechEnabled).accessibilityIdentifier("spoken-cues-setting")
            } header: { Text("Audio") } footer: {
                Text("Hear exercise names, durations, countdowns, and completion. Turn this off for tones only. You can mute all audio during a workout.")
            }
            Section {
                Label("Lock Screen countdown", systemImage: "lock.rectangle")
                Text("The overall workout countdown appears as a Live Activity when you start. Tap it to return to Tempo and pause or skip a step.")
                    .font(.subheadline).foregroundStyle(TempoTheme.muted)
                Button(authorization == .notDetermined ? "Enable interval alerts" : "Notification settings") {
                    if authorization == .notDetermined {
                        requesting = true
                        Task {
                            do {
                                _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                                await refresh()
                            } catch { message = "Notifications couldn’t be enabled. Try again in Settings." }
                            requesting = false
                        }
                    } else if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .disabled(requesting).accessibilityIdentifier("enable-interval-alerts")
                if authorization == .authorized || authorization == .provisional {
                    Label("Interval alerts enabled", systemImage: "checkmark.circle")
                } else if authorization == .denied {
                    Text("Alerts are off. Your timer still continues when locked.").font(.footnote)
                }
                if let message { Text(message).font(.footnote) }
            } header: { Text("When your screen locks") } footer: {
                Text("Enable alerts before starting a workout to hear spoken intervals on the Lock Screen. Alerts follow Focus, silent mode, and notification sound settings. If speech audio is unavailable, you’ll hear a tone. For long routines, Tempo schedules the next 63 interval alerts plus completion; reopen the app to refresh them. Live Activities can run for up to 8 hours.")
            }
            Section {
                Label("Saved on this device", systemImage: "iphone")
                Text("Routines and workout history stay on your device. No account or network connection is required.")
                    .font(.subheadline).foregroundStyle(TempoTheme.muted)
            }
            Section {
                NavigationLink { FeatureRequestView() } label: {
                    Label("Request a feature", systemImage: "lightbulb")
                }.accessibilityIdentifier("request-feature")
            } header: { Text("Help shape Tempo") } footer: {
                Text("Have an idea? Send it privately to Tempo’s developer, with your email so we can reply.")
            }
        }
        .scrollContentBackground(.hidden).tempoBackground().foregroundStyle(TempoTheme.ink)
        .navigationTitle("Workout settings").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task { await refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await refresh() } } }
    }

    private func refresh() async { authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus }
}
