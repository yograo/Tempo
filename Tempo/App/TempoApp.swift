import SwiftUI
import UserNotifications

@main
struct TempoApp: App {
    @UIApplicationDelegateAdaptor(TempoAppDelegate.self) private var appDelegate
    @State private var store = RoutineStore()
    @State private var workouts = WorkoutStore()

    var body: some Scene {
        WindowGroup {
            RoutineLibraryView(store: store)
                .environment(workouts)
                .tint(TempoTheme.ink)
                .preferredColorScheme(.light)
                .fullScreenCover(item: Binding(get: { workouts.controller }, set: { if $0 == nil { workouts.close() } })) { controller in
                    WorkoutView(controller: controller)
                }
        }
    }
}

@MainActor
final class TempoAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static var orientationMask: UIInterfaceOrientationMask = .portrait

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // The foreground timer already plays its own cue.
        completionHandler([])
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.orientationMask
    }

    static func setWorkoutOrientation(_ active: Bool) {
        orientationMask = active ? .landscape : .portrait
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }
        for window in scene.windows {
            var controller = window.rootViewController
            while let current = controller {
                current.setNeedsUpdateOfSupportedInterfaceOrientations()
                controller = current.presentedViewController
            }
        }
        let requested: UIInterfaceOrientationMask = active ? .landscapeRight : .portrait
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: requested))
    }
}
