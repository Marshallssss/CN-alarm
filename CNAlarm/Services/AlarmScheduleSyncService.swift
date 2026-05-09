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
