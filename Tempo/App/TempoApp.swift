import SwiftUI

@main
struct TempoApp: App {
    @UIApplicationDelegateAdaptor(TempoAppDelegate.self) private var appDelegate
    @State private var store = RoutineStore()

    var body: some Scene {
        WindowGroup {
            RoutineLibraryView(store: store)
                .tint(TempoTheme.ink)
                .preferredColorScheme(.light)
        }
    }
}

@MainActor
final class TempoAppDelegate: NSObject, UIApplicationDelegate {
    static var orientationMask: UIInterfaceOrientationMask = .portrait

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
