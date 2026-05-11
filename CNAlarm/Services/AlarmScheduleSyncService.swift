import Foundation
import SwiftData

@MainActor
final class AlarmScheduleSyncService {
    struct SyncResult {
        var scheduledCount: Int
        var requestedCount: Int

        var message: String {
            if scheduledCount == requestedCount {
                return "已同步 \(scheduledCount) 个未来系统闹铃"
            }
            if scheduledCount == 0 {
                return "计划已保存，但系统闹铃暂未注册成功。请确认 AlarmKit 权限开启，并删除一些系统闹铃后再刷新。"
            }
            return "已同步 \(scheduledCount) 个系统闹铃；其余计划已保存在 App 内，系统闹铃数量上限释放后可再刷新。"
        }
    }

    private let defaults: UserDefaults
    private let scheduler: AlarmKitScheduler
    private let scheduledIDsKey = "scheduledAlarmInstanceIDs"

    init(defaults: UserDefaults = .standard, scheduler: AlarmKitScheduler = AlarmKitScheduler()) {
        self.defaults = defaults
        self.scheduler = scheduler
    }

    func sync(
        profiles: [AlarmProfile],
        templates: [AlarmComboTemplate],
        holidayDatasets: [HolidayDataset],
        companyRules: [CompanyCalendarRule],
        exceptions: [CalendarException],
        from now: Date = Date()
    ) async throws -> SyncResult {
        let previousIDs = defaults.stringArray(forKey: scheduledIDsKey)?.compactMap(UUID.init(uuidString:)) ?? []
        scheduler.cancel(ids: previousIDs)

        let holiday = holidayDatasets.last.map { HolidayCalendar.decodeStored($0.rawJSON) } ?? .fixture2026
        let instances = AlarmScheduleResolver().resolve(
            profiles: profiles,
            templates: templates,
            holidayCalendar: holiday,
            companyRules: companyRules,
            exceptions: exceptions,
            from: now,
            days: 7
        )

        let limitedInstances = Array(instances.prefix(32))
        let scheduledCount = try await scheduler.schedule(instances: limitedInstances)
        defaults.set(limitedInstances.prefix(scheduledCount).map { $0.id.uuidString }, forKey: scheduledIDsKey)
        return SyncResult(scheduledCount: scheduledCount, requestedCount: limitedInstances.count)
    }
}

enum AlarmScheduleSyncSignature {
    static func make(
        profiles: [AlarmProfile],
        templates: [AlarmComboTemplate],
        holidayDatasets: [HolidayDataset],
        companyRules: [CompanyCalendarRule],
        exceptions: [CalendarException]
    ) -> String {
        [
            profileSignature(profiles),
            templateSignature(templates),
            holidaySignature(holidayDatasets),
            companyRuleSignature(companyRules),
            exceptionSignature(exceptions)
        ].joined(separator: "||")
    }

    private static func profileSignature(_ profiles: [AlarmProfile]) -> String {
        profiles
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map {
                [
                    $0.id.uuidString,
                    $0.label,
                    $0.modeRaw,
                    String($0.isEnabled),
                    String($0.hour),
                    String($0.minute),
                    $0.recurrenceWeekdaysCSV,
                    String($0.followsSmartWorkday),
                    String($0.allowSnooze),
                    String($0.snoozeMinutes),
                    $0.soundIdentifier,
                    $0.comboTemplateID?.uuidString ?? "",
                    $0.comboAnchorRaw,
                    $0.comboOffsetsCSV
                ].joined(separator: "|")
            }
            .joined(separator: "\n")
    }

    private static func templateSignature(_ templates: [AlarmComboTemplate]) -> String {
        templates
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map {
                [
                    $0.id.uuidString,
                    $0.name,
                    $0.anchorRaw,
                    $0.offsetsCSV,
                    $0.defaultSoundIdentifier,
                    String($0.allowSnooze)
                ].joined(separator: "|")
            }
            .joined(separator: "\n")
    }

    private static func holidaySignature(_ holidayDatasets: [HolidayDataset]) -> String {
        holidayDatasets
            .sorted { $0.fetchedAt < $1.fetchedAt }
            .map {
                [
                    $0.id.uuidString,
                    $0.sourceURL,
                    String($0.fetchedAt.timeIntervalSince1970),
                    $0.rawJSON
                ].joined(separator: "|")
            }
            .joined(separator: "\n")
    }

    private static func companyRuleSignature(_ rules: [CompanyCalendarRule]) -> String {
        rules
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map {
                [
                    $0.id.uuidString,
                    $0.name,
                    $0.kindRaw,
                    String($0.isEnabled),
                    String($0.anchorDate.timeIntervalSince1970),
                    String($0.ordinal),
                    String($0.weekday)
                ].joined(separator: "|")
            }
            .joined(separator: "\n")
    }

    private static func exceptionSignature(_ exceptions: [CalendarException]) -> String {
        exceptions
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map {
                [
                    $0.id.uuidString,
                    $0.dateKey,
                    $0.kindRaw,
                    $0.profileID?.uuidString ?? "",
                    String($0.childIndex),
                    String($0.hour),
                    String($0.minute),
                    $0.note,
                    $0.soundIdentifier ?? ""
                ].joined(separator: "|")
            }
            .joined(separator: "\n")
    }
}
