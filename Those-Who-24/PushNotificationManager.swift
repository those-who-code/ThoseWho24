import UIKit
import UserNotifications
import Observation

@MainActor
@Observable
final class PushNotificationManager {
    static let shared = PushNotificationManager()

    private(set) var deviceToken: String?
    private(set) var pendingRoomCode: String?

    #if DEBUG
    static let apnsEnvironment = "development"
    #else
    static let apnsEnvironment = "production"
    #endif

    private init() {}

    func requestAuthorizationAndRegister() {
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            switch settings.authorizationStatus {
            case .notDetermined:
                if (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) == true {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            case .authorized, .provisional, .ephemeral:
                UIApplication.shared.registerForRemoteNotifications()
            case .denied:
                break
            @unknown default:
                break
            }
        }
    }

    func didRegister(deviceToken data: Data) {
        deviceToken = data.map { String(format: "%02x", $0) }.joined()
        Task { await FriendsManager.shared.registerPendingDeviceToken() }
    }

    func receiveNotification(userInfo: [AnyHashable: Any]) {
        guard userInfo["friend_event"] as? String == "room_invite",
              let roomCode = userInfo["room_code"] as? String else { return }
        let normalizedCode = roomCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalizedCode.count == 6 else { return }
        pendingRoomCode = normalizedCode
    }

    func consumeRoomInvite() {
        pendingRoomCode = nil
        UIApplication.shared.applicationIconBadgeNumber = 0
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        if let userInfo = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            Task { @MainActor in
                PushNotificationManager.shared.receiveNotification(userInfo: userInfo)
            }
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            PushNotificationManager.shared.didRegister(deviceToken: deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // The app remains fully usable when notifications are unavailable.
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        Task { @MainActor in
            await FriendsManager.shared.refreshConnections()
        }
        return [.banner, .sound, .badge]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run {
            PushNotificationManager.shared.receiveNotification(
                userInfo: response.notification.request.content.userInfo
            )
        }
        await FriendsManager.shared.refreshConnections()
    }
}
