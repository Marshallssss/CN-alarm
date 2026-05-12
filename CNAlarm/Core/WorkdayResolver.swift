import Foundation

enum WorkdayDecision: String {
    case workday
    case restDay
}

enum CalendarDayMarkerKind: String, CaseIterable {
    case holidayRest
    case makeupWorkday
    case companyWorkday
    case extraRest

    var shortTitle: String {
        switch self {
        case .holidayRest: "假"
        case .makeupWorkday: "班"
        case .companyWorkday: "加"
        case .extraRest: "休"
        }
    }

    var legendTitle: String {
        switch self {
        case .holidayRest: "节假日"
        case .makeupWorkday: "调休补班"
        case .companyWorkday: "加班日"
        case .extraRest: "额外休息"
        }
    }
}

struct CalendarDayMarker: Hashable, Identifiable {
    var kind: CalendarDayMarkerKind
    var title: String

    var id: String { "\(kind.rawValue)-\(title)" }
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

    func dayMarkers(
        for date: Date,
        holidayCalendar: HolidayCalendar,
        companyRules: [CompanyCalendarRule],
        exceptions: [CalendarException]
    ) -> [CalendarDayMarker] {
        let key = calendar.startOfDayKey(for: date)
        let exceptionsForDate = exceptions.filter { $0.dateKey == key }
        let hasRestOverride = exceptionsForDate.contains { $0.kind == .restDayOverride }
        let isHolidayRestDay = holidayCalendar.isHolidayRestDay(key)
        let isCompensatedWorkday = holidayCalendar.isCompensatedWorkday(key)
        var markers: [CalendarDayMarker] = []

        if let restOverride = exceptionsForDate.first(where: { $0.kind == .restDayOverride }) {
            markers.append(CalendarDayMarker(kind: .extraRest, title: restOverrideMarkerTitle(restOverride)))
        }
        if isHolidayRestDay {
            markers.append(CalendarDayMarker(kind: .holidayRest, title: holidayCalendar.holidayName(for: key) ?? "节假日"))
        }
        if isCompensatedWorkday {
            markers.append(CalendarDayMarker(kind: .makeupWorkday, title: holidayCalendar.holidayName(for: key) ?? "调休补班"))
        }

        if !hasRestOverride && !isHolidayRestDay && !isCompensatedWorkday {
            let matchedRules = matchedCompanyRules(for: date, companyRules: companyRules)
            markers.append(contentsOf: matchedRules.map {
                CalendarDayMarker(kind: .companyWorkday, title: $0.name.isEmpty ? $0.kind.title : $0.name)
            })
        }

        return uniqueMarkers(markers)
    }

    func matchedCompanyRules(for date: Date, companyRules: [CompanyCalendarRule]) -> [CompanyCalendarRule] {
        companyRules.filter { matches(rule: $0, date: date) }
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

    private func restOverrideMarkerTitle(_ exception: CalendarException) -> String {
        if exception.note.hasPrefix("休假：") { return String(exception.note.dropFirst("休假：".count)) }
        if exception.note.contains("寒假") { return "寒假休息" }
        if exception.note.contains("暑假") { return "暑假休息" }
        return "额外休息"
    }

    private func uniqueMarkers(_ markers: [CalendarDayMarker]) -> [CalendarDayMarker] {
        var seen: Set<CalendarDayMarkerKind> = []
        return markers.filter { marker in
            seen.insert(marker.kind).inserted
        }
    }
}
