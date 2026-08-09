import UIKit
import UserNotifications
import Observation

@MainActor
@Observable
final class PushNotificationManager {
    static let shared = PushNotificationManager()

    private(set) var deviceToken: String?
    private(set) var pendingRoomCode: String?
    private(set) var pendingDailyPuzzle = false
    private(set) var pendingFriendRequests = false

    private let dailyReminderIdentifier = "daily-puzzle-reminder"
    private let dailyReminderDateKey = "scheduledDailyPuzzleReminderUTC"

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
        if userInfo["friend_event"] as? String == "request_received" {
            pendingFriendRequests = true
            UIApplication.shared.applicationIconBadgeNumber = 0
            return
        }

        if userInfo["daily_puzzle"] as? Bool == true {
            guard !DailyPuzzleManager.shared.hasCompletedToday else {
                pendingDailyPuzzle = false
                cancelDailyPuzzleReminder()
                UIApplication.shared.applicationIconBadgeNumber = 0
                return
            }
            pendingDailyPuzzle = true
            UIApplication.shared.applicationIconBadgeNumber = 0
            return
        }

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

    func consumeDailyPuzzleReminder() {
        pendingDailyPuzzle = false
        UIApplication.shared.applicationIconBadgeNumber = 0
    }

    func consumeFriendRequests() {
        pendingFriendRequests = false
        UIApplication.shared.applicationIconBadgeNumber = 0
    }

    /// Schedules at most one daily-puzzle reminder for a UTC puzzle day.
    /// iOS does not expose phone-pickup events, so app activation is used as
    /// the closest privacy-preserving signal.
    func scheduleDailyPuzzleReminderIfNeeded(
        hasCompletedToday: Bool,
        utcDateKey: String
    ) async {
        let center = UNUserNotificationCenter.current()

        if hasCompletedToday {
            cancelDailyPuzzleReminder()
            return
        }

        guard UserDefaults.standard.string(forKey: dailyReminderDateKey) != utcDateKey else {
            return
        }

        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            guard (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) == true else {
                return
            }
        } else if settings.authorizationStatus == .denied {
            return
        }

        let now = Date()
        let thirtyMinutesFromNow = now.addingTimeInterval(30 * 60)
        let calendar = Calendar.autoupdatingCurrent
        let todayAtEight = calendar.date(
            bySettingHour: 8,
            minute: 0,
            second: 0,
            of: now
        )
        let fireDate = todayAtEight.map { $0 > now ? min($0, thirtyMinutesFromNow) : thirtyMinutesFromNow }
            ?? thirtyMinutesFromNow

        let content = UNMutableNotificationContent()
        content.title = "Daily Puzzle"
        content.body = "Today’s puzzle is ready. Can you make 24?"
        content.sound = .default
        content.userInfo = ["daily_puzzle": true]

        center.removePendingNotificationRequests(withIdentifiers: [dailyReminderIdentifier])
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, fireDate.timeIntervalSince(now)),
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: dailyReminderIdentifier,
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
            UserDefaults.standard.set(utcDateKey, forKey: dailyReminderDateKey)
        } catch {
            // The next app activation will retry if scheduling failed.
        }
    }

    func cancelDailyPuzzleReminder() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [dailyReminderIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [dailyReminderIdentifier])
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
        if notification.request.content.userInfo["daily_puzzle"] as? Bool == true {
            let hasCompletedToday = await MainActor.run {
                DailyPuzzleManager.shared.hasCompletedToday
            }
            if hasCompletedToday {
                await MainActor.run {
                    PushNotificationManager.shared.cancelDailyPuzzleReminder()
                    UIApplication.shared.applicationIconBadgeNumber = 0
                }
                return []
            }
        }
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
