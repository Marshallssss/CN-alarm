import Foundation

enum WorkdayDecision: String {
    case workday
    case restDay
}

struct WorkdayResolver {
    var calendar: Calendar = .chinaAlarm

    func decision(
        for date: Date,
        holidayCalendar: HolidayCalendar,
        companyRules: [CompanyCalendarRule],
        exceptions: [CalendarException]
    ) -> WorkdayDecision {
        let key = calendar.startOfDayKey(for: date)
        if exceptions.contains(where: { $0.dateKey == key && $0.kind == .workdayOverride }) {
            return .workday
        }
        if exceptions.contains(where: { $0.dateKey == key && $0.kind == .restDayOverride }) {
            return .restDay
        }
        if holidayCalendar.isCompensatedWorkday(key) {
            return .workday
        }
        if holidayCalendar.isHolidayRestDay(key) {
            return .restDay
        }
        if companyRules.contains(where: { matches(rule: $0, date: date) }) {
            return .workday
        }
        return calendar.isWeekend(date) ? .restDay : .workday
    }

    func isWorkday(
        _ date: Date,
        holidayCalendar: HolidayCalendar,
        companyRules: [CompanyCalendarRule],
        exceptions: [CalendarException]
    ) -> Bool {
        decision(for: date, holidayCalendar: holidayCalendar, companyRules: companyRules, exceptions: exceptions) == .workday
    }

    private func matches(rule: CompanyCalendarRule, date: Date) -> Bool {
        guard rule.isEnabled else { return false }
        switch rule.kind {
        case .alternateSaturday:
            guard calendar.weekdayNumber(for: date) == 7 else { return false }
            let start = calendar.startOfDay(for: rule.anchorDate)
            let target = calendar.startOfDay(for: date)
            let days = calendar.dateComponents([.day], from: start, to: target).day ?? 0
            return days >= 0 && (days / 7).isMultiple(of: 2)
        case .lastSaturdayOfMonth:
            guard calendar.weekdayNumber(for: date) == 7 else { return false }
            guard let nextWeek = calendar.date(byAdding: .day, value: 7, to: date) else { return false }
            return calendar.component(.month, from: nextWeek) != calendar.component(.month, from: date)
        case .nthWeekdayOfMonth:
            guard calendar.weekdayNumber(for: date) == rule.weekday else { return false }
            let day = calendar.component(.day, from: date)
            let ordinal = ((day - 1) / 7) + 1
            return ordinal == rule.ordinal
        case .singleDayOff:
            return calendar.weekdayNumber(for: date) == 7
        }
    }
}
