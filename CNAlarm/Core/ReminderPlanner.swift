import Foundation

struct ReminderEventDraft: Hashable, Identifiable {
    var id: UUID
    var kind: ReminderRuleKind
    var fireDate: Date
    var title: String
    var message: String
    var targetDateKey: String
    var actionRaw: String
}

struct ReminderPlanner {
    var calendar: Calendar = .chinaAlarm

    func plan(
        rules: [ReminderRule],
        holidayCalendar: HolidayCalendar,
        from startDate: Date,
        days: Int
    ) -> [ReminderEventDraft] {
        let enabledRules = rules.filter(\.isEnabled)
        var drafts: [ReminderEventDraft] = []
        let range = calendar.dateRange(from: startDate, days: days)

        if let rule = enabledRules.first(where: { $0.kind == .fridayNight }) {
            drafts += fridayNightDrafts(rule: rule, dates: range)
        }
        if let rule = enabledRules.first(where: { $0.kind == .holidayLead }) {
            drafts += holidayLeadDrafts(rule: rule, holidayCalendar: holidayCalendar, from: startDate, days: days)
        }
        if let rule = enabledRules.first(where: { $0.kind == .makeupWorkdayEve }) {
            drafts += makeupWorkdayEveDrafts(rule: rule, holidayCalendar: holidayCalendar, from: startDate, days: days)
        }

        return Array(Set(drafts))
            .filter { $0.fireDate >= startDate }
            .sorted { $0.fireDate < $1.fireDate }
    }

    private func fridayNightDrafts(rule: ReminderRule, dates: [Date]) -> [ReminderEventDraft] {
        dates.compactMap { date in
            guard calendar.weekdayNumber(for: date) == 6 else { return nil }
            let key = calendar.startOfDayKey(for: date)
            guard let fireDate = calendar.date(from: key, hour: rule.hour, minute: rule.minute) else { return nil }
            return ReminderEventDraft(
                id: UUID(deterministic: "friday-\(key)-\(rule.hour)-\(rule.minute)"),
                kind: .fridayNight,
                fireDate: fireDate,
                title: "周五晚检查闹铃",
                message: "周末、加班或临时安排有变化吗？可以提前调整闹铃组合。",
                targetDateKey: key,
                actionRaw: "check"
            )
        }
    }

    private func holidayLeadDrafts(
        rule: ReminderRule,
        holidayCalendar: HolidayCalendar,
        from startDate: Date,
        days: Int
    ) -> [ReminderEventDraft] {
        let windowEnd = calendar.date(byAdding: .day, value: days, to: startDate) ?? startDate
        return holidayCalendar.periods.flatMap { period -> [ReminderEventDraft] in
            guard let start = calendar.date(from: period.startKey), start >= calendar.startOfDay(for: startDate), start <= windowEnd else {
                return []
            }
            let leadDays = rule.leadDays.isEmpty ? [3, 1] : rule.leadDays
            return leadDays.compactMap { leadDay in
                guard
                    let fireDay = calendar.date(byAdding: .day, value: -leadDay, to: start),
                    let fireDate = calendar.date(
                        from: calendar.startOfDayKey(for: fireDay),
                        hour: rule.hour,
                        minute: rule.minute
                    )
                else { return nil }
                let targetKey = calendar.startOfDayKey(for: start)
                return ReminderEventDraft(
                    id: UUID(deterministic: "holiday-\(period.name)-\(leadDay)-\(targetKey)"),
                    kind: .holidayLead,
                    fireDate: fireDate,
                    title: "\(period.name)前 \(leadDay) 天",
                    message: "假期快到了，确认要跳过、提前或新增哪几组闹铃。",
                    targetDateKey: targetKey,
                    actionRaw: "check"
                )
            }
        }
    }

    private func makeupWorkdayEveDrafts(
        rule: ReminderRule,
        holidayCalendar: HolidayCalendar,
        from startDate: Date,
        days: Int
    ) -> [ReminderEventDraft] {
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.date(byAdding: .day, value: days, to: start) ?? start
        return holidayCalendar.compWorkdays.keys.compactMap { key in
            guard
                let target = calendar.date(from: key),
                target >= start,
                target <= end,
                let eve = calendar.date(byAdding: .day, value: -1, to: target),
                let fireDate = calendar.date(from: calendar.startOfDayKey(for: eve), hour: rule.hour, minute: rule.minute)
            else { return nil }
            return ReminderEventDraft(
                id: UUID(deterministic: "makeup-\(key)-\(rule.hour)-\(rule.minute)"),
                kind: .makeupWorkdayEve,
                fireDate: fireDate,
                title: "明天调班上班",
                message: "明天是补班工作日，确认智能闹铃或闹铃组合已经开启。",
                targetDateKey: key,
                actionRaw: "check"
            )
        }
    }
}
