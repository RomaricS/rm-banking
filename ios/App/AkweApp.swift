import SwiftUI
import UserNotifications
import AkweKit

@main
struct AkweApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var app = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .preferredColorScheme(app.colorScheme)
                .tint(Palette.iris)
                .task {
                    delegate.app = app
                    await app.start()
                }
                .onOpenURL { handle($0) }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { handle(url) }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                if app.faceIDEnabled && !app.isDemo && app.phase == .ready { app.isLocked = true }
            case .active:
                if app.phase == .ready { Task { await app.load() } }
            default: break
            }
        }
    }

    /// akwe://join?code=… or https://<domain>/join?code=… (shared goal invites).
    /// Plaid OAuth redirects (https://<domain>/plaid-oauth) are handled by LinkKit itself.
    private func handle(_ url: URL) {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let isJoin = url.host == "join" || url.path.hasPrefix("/join")
        if isJoin, let code = comps.queryItems?.first(where: { $0.name == "code" })?.value {
            app.pendingInviteCode = code
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    weak var app: AppModel?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in await app?.registerDevice(token: deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("push registration failed:", error)
    }

    // Show banners while the app is open, too.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    // Tapping a notification refreshes data so the screen it points to is current.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await MainActor.run { Task { await app?.load() } }
    }

    static func requestPushPermission() async {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if granted { await MainActor.run { UIApplication.shared.registerForRemoteNotifications() } }
    }
}
