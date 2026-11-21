import UserNotifications

@MainActor
final class WorkoutAlerts {
    private let center = UNUserNotificationCenter.current()
    private var revision = 0
    private var updates: Task<Void, Never>?
    private(set) var unavailable = false

    func replace(id: UUID, plan: WorkoutAlertPlan, date: Date, sound: Bool, speech: Bool, files: [String: String]) {
        revision += 1
        let version = revision
        let previous = updates
        updates = Task {
            await previous?.value
            guard version == revision else { return }
            let pending = await center.pendingNotificationRequests()
            center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix("tempo-") })
            guard version == revision else { return }
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                unavailable = !plan.cues.isEmpty
                return
            }
            unavailable = false
            for cue in plan.cues {
                guard version == revision else { return }
                let interval = date.addingTimeInterval(cue.offset).timeIntervalSinceNow
                guard interval > 0 else { continue }
                let content = UNMutableNotificationContent()
                content.title = cue.isCompletion ? "Tempo · workout complete" : "Tempo · next interval"
                content.body = cue.text
                content.threadIdentifier = id.uuidString
                if sound {
                    let name = speech ? files[cue.text] : nil
                    content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: name ?? (cue.isCompletion ? "complete.wav" : "transition.wav")))
                }
                do {
                    try await center.add(UNNotificationRequest(identifier: "tempo-\(id)-\(cue.key)", content: content,
                        trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(0.1, interval), repeats: false)))
                } catch { unavailable = true }
            }
        }
    }

    func clear() {
        replace(id: UUID(), plan: WorkoutAlertPlan(timeline: WorkoutTimeline(routine: .starter)), date: Date(), sound: false, speech: false, files: [:])
        center.removeAllDeliveredNotifications()
    }

    func flush() async { await updates?.value }
}
