import Foundation
import SwiftData
import UserNotifications

enum ReminderNotificationAction: String {
    case check = "CNALARM_CHECK"
    case skip = "CNALARM_SKIP"
    case addTemporary = "CNALARM_ADD_TEMP"
    case adjustDeadline = "CNALARM_ADJUST_DDL"
    case snooze = "CNALARM_SNOOZE"
}

final class NotificationReminderService {
    static let categoryIdentifier = "CNALARM_REMINDER_CATEGORY"

    enum NotificationError: LocalizedError {
        case authorizationDenied

        var errorDescription: String? {
            "通知权限未开启，无法注册关键日期提醒。"
        }
    }

    func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
    }

    func registerCategories() {
        let actions = [
            UNNotificationAction(identifier: ReminderNotificationAction.check.rawValue, title: "检查闹铃", options: [.foreground]),
            UNNotificationAction(identifier: ReminderNotificationAction.skip.rawValue, title: "跳过当天", options: [.foreground]),
            UNNotificationAction(identifier: ReminderNotificationAction.addTemporary.rawValue, title: "新增临时", options: [.foreground])
        ]
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: actions,
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    func schedule(drafts: [ReminderEventDraft]) async throws {
        let authorized = try await requestAuthorization()
        guard authorized else {
            throw NotificationError.authorizationDenied
        }
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: drafts.map { $0.id.uuidString }
        )
        for draft in drafts {
            let content = UNMutableNotificationContent()
            content.title = draft.title
            content.body = draft.message
            content.sound = .default
            content.categoryIdentifier = Self.categoryIdentifier
            content.userInfo = [
                "targetDateKey": draft.targetDateKey,
                "action": draft.actionRaw
            ]
            let components = Calendar.chinaAlarm.dateComponents([.year, .month, .day, .hour, .minute], from: draft.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: draft.id.uuidString, content: content, trigger: trigger)
            try await UNUserNotificationCenter.current().add(request)
        }
    }
}

enum PendingNotificationActionStore {
    private static let key = "pendingNotificationActions"

    static func record(response: UNNotificationResponse) {
        guard response.actionIdentifier != UNNotificationDefaultActionIdentifier else { return }
        let userInfo = response.notification.request.content.userInfo
        let targetDateKey = userInfo["targetDateKey"] as? String ?? ""
        let action = response.actionIdentifier
        let payload = "\(Date().timeIntervalSince1970)|\(action)|\(targetDateKey)"
        append(payload: payload)
    }

    static func record(action: ReminderNotificationAction, targetDateKey: String, date: Date = Date()) {
        append(payload: "\(date.timeIntervalSince1970)|\(action.rawValue)|\(targetDateKey)")
    }

    private static func append(payload: String) {
        var existing = UserDefaults.standard.stringArray(forKey: key) ?? []
        existing.append(payload)
        UserDefaults.standard.set(Array(existing.suffix(20)), forKey: key)
    }

    static func pendingActions() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

struct PendingNotificationAction: Hashable {
    var date: Date
    var action: ReminderNotificationAction
    var targetDateKey: String
}

enum NotificationActionApplier {
    static func pendingActions() -> [PendingNotificationAction] {
        PendingNotificationActionStore.pendingActions().compactMap { raw in
            let parts = raw.split(separator: "|", omittingEmptySubsequences: false)
            guard
                parts.count == 3,
                let timestamp = TimeInterval(parts[0]),
                let action = ReminderNotificationAction(rawValue: String(parts[1]))
            else {
                return nil
            }
            return PendingNotificationAction(
                date: Date(timeIntervalSince1970: timestamp),
                action: action,
                targetDateKey: String(parts[2])
            )
        }
    }

    @MainActor
    static func applyPendingActions(context: ModelContext) {
        let actions = pendingActions()
        guard !actions.isEmpty else { return }
        let profiles = (try? context.fetch(FetchDescriptor<AlarmProfile>())) ?? []
        let existing = (try? context.fetch(FetchDescriptor<CalendarException>())) ?? []
        let targetProfileID = profiles.first?.id
        for action in actions {
            switch action.action {
            case .check, .snooze:
                continue
            case .skip:
                guard !existing.contains(where: { $0.dateKey == action.targetDateKey && $0.kind == .skipAlarm && $0.profileID == nil }) else {
                    continue
                }
                context.insert(
                    CalendarException(
                        dateKey: action.targetDateKey,
                        kind: .skipAlarm,
                        profileID: nil,
                        note: "由提醒快捷操作创建"
                    )
                )
            case .addTemporary:
                guard !existing.contains(where: { $0.dateKey == action.targetDateKey && $0.kind == .extraAlarm && $0.hour == 8 && $0.minute == 0 }) else {
                    continue
                }
                context.insert(
                    CalendarException(
                        dateKey: action.targetDateKey,
                        kind: .extraAlarm,
                        hour: 8,
                        minute: 0,
                        note: "临时闹铃"
                    )
                )
            case .adjustDeadline:
                continue
            }
        }
        PendingNotificationActionStore.clear()
    }
}
