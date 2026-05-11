import ActivityKit
import AlarmKit
import Foundation
import SwiftUI

struct CNAlarmMetadata: AlarmMetadata {
    var profileID: UUID
    var label: String
    var comboChildIndex: Int?
}

final class AlarmKitScheduler {
    enum SchedulerError: LocalizedError {
        case authorizationDenied(AlarmManager.AuthorizationState)
        case maximumLimitReached
        case schedulingFailed(String)

        var errorDescription: String? {
            switch self {
            case .authorizationDenied:
                "AlarmKit 授权未开启，无法注册系统闹铃。"
            case .maximumLimitReached:
                "系统闹铃数量已达上限。已尝试清理旧闹铃，请减少未来同步天数或删除一些闹铃后重试。"
            case .schedulingFailed(let message):
                "系统闹铃注册失败：\(message)"
            }
        }
    }

    func requestAuthorization() async throws -> AlarmManager.AuthorizationState {
        try await AlarmManager.shared.requestAuthorization()
    }

    var isAuthorized: Bool {
        AlarmManager.shared.authorizationState == .authorized
    }

    func schedule(instances: [ScheduledAlarmInstance]) async throws -> Int {
        let authorization = try await requestAuthorization()
        guard authorization == .authorized else {
            throw SchedulerError.authorizationDenied(authorization)
        }
        try? SoundAssetManager().installBundledSoundsIfNeeded()
        cancelAllManagedAlarms()
        var scheduledCount = 0
        var firstError: Error?
        for instance in instances {
            let configuration = alarmConfiguration(for: instance)
            do {
                _ = try await AlarmManager.shared.schedule(id: instance.id, configuration: configuration)
                scheduledCount += 1
            } catch AlarmManager.AlarmError.maximumLimitReached {
                break
            } catch {
                firstError = error
                break
            }
        }
        if scheduledCount == 0, let firstError {
            throw SchedulerError.schedulingFailed(firstError.localizedDescription)
        }
        return scheduledCount
    }

    func cancel(ids: [UUID]) {
        for id in ids {
            try? AlarmManager.shared.cancel(id: id)
        }
    }

    func cancelAllManagedAlarms() {
        guard let alarms = try? AlarmManager.shared.alarms else { return }
        for alarm in alarms {
            try? AlarmManager.shared.cancel(id: alarm.id)
        }
    }

    func diagnosticStatus() -> String {
        let authorization = AlarmManager.shared.authorizationState
        let count = (try? AlarmManager.shared.alarms.count) ?? 0
        return "AlarmKit 权限：\(authorization.title)，系统已注册 \(count) 个闹铃"
    }

    func scheduleTestAlarm(after seconds: TimeInterval = 60) async throws -> Date {
        let authorization = try await requestAuthorization()
        guard authorization == .authorized else {
            throw SchedulerError.authorizationDenied(authorization)
        }
        try? SoundAssetManager().installBundledSoundsIfNeeded()
        let fireDate = Date().addingTimeInterval(seconds)
        let instance = ScheduledAlarmInstance(
            id: UUID(),
            profileID: UUID(),
            fireDate: fireDate,
            label: "测试闹铃",
            soundIdentifier: SoundLibrary.defaultSoundIdentifier,
            allowSnooze: false,
            snoozeMinutes: 5,
            comboChildIndex: nil
        )
        let configuration = alarmConfiguration(for: instance)
        do {
            _ = try await AlarmManager.shared.schedule(id: instance.id, configuration: configuration)
            return fireDate
        } catch {
            throw SchedulerError.schedulingFailed(error.localizedDescription)
        }
    }

    private func alarmConfiguration(
        for instance: ScheduledAlarmInstance
    ) -> AlarmManager.AlarmConfiguration<CNAlarmMetadata> {
        let stopButton = AlarmButton(text: "停止", textColor: .white, systemImageName: "stop.fill")
        let snoozeButton = AlarmButton(text: "稍后", textColor: .orange, systemImageName: "zzz")
        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: instance.label),
            stopButton: stopButton,
            secondaryButton: instance.allowSnooze ? snoozeButton : nil,
            secondaryButtonBehavior: instance.allowSnooze ? .countdown : nil
        )
        let presentation = AlarmPresentation(alert: alert)
        let attributes = AlarmAttributes(
            presentation: presentation,
            metadata: CNAlarmMetadata(profileID: instance.profileID, label: instance.label, comboChildIndex: instance.comboChildIndex),
            tintColor: .orange
        )
        return AlarmManager.AlarmConfiguration(
            countdownDuration: instance.allowSnooze ? Alarm.CountdownDuration(preAlert: nil, postAlert: TimeInterval(instance.snoozeMinutes * 60)) : nil,
            schedule: .fixed(instance.fireDate),
            attributes: attributes,
            sound: sound(for: instance.soundIdentifier)
        )
    }

    private func sound(for identifier: String) -> AlertConfiguration.AlertSound {
        identifier == SoundLibrary.alarmKitDefaultIdentifier || !identifier.contains(".") ? .default : .named(identifier)
    }
}

private extension AlarmManager.AuthorizationState {
    var title: String {
        switch self {
        case .notDetermined: "未请求"
        case .denied: "已拒绝"
        case .authorized: "已授权"
        @unknown default: "未知"
        }
    }
}
