import SwiftData
import SwiftUI
import UserNotifications

@main
struct CNAlarmApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let container: ModelContainer = {
        let schema = Schema([
            AlarmProfile.self,
            AlarmComboTemplate.self,
            AlarmComboInstance.self,
            AlarmComboChildOverride.self,
            HolidayDataset.self,
            CompanyCalendarRule.self,
            CalendarException.self,
            ReminderRule.self,
            ReminderEvent.self,
            SoundAsset.self
        ])
        let configuration = ModelConfiguration(schema: schema)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Unable to create SwiftData container: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            AppShellView()
                .modelContainer(container)
                .task {
                    NotificationReminderService().registerCategories()
                }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        PendingNotificationActionStore.record(response: response)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
