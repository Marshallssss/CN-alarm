import Foundation

struct CalendarExceptionRange: Identifiable, Hashable {
    var title: String
    var note: String
    var start: Date
    var end: Date
    var dateKeys: [String]
    var restDateKeys: [String]
    var kind: CalendarDayMarkerKind

    var id: String { "\(note)-\(dateKeys.first ?? "")-\(dateKeys.last ?? "")" }

    var restStart: Date {
        restDateKeys.first.flatMap { DateKey($0).date(calendar: .chinaAlarm) } ?? start
    }

    var restEnd: Date {
        restDateKeys.last.flatMap { DateKey($0).date(calendar: .chinaAlarm) } ?? end
    }
}

struct CalendarExceptionRangeGrouper {
    var calendar: Calendar = .chinaAlarm

    func leaveRanges(from exceptions: [CalendarException], within allowedKeys: Set<String>? = nil) -> [CalendarExceptionRange] {
        let leaveExceptions = exceptions
            .filter { exception in
                exception.kind == .restDayOverride
                    && isLeaveNote(exception.note)
                    && (allowedKeys?.contains(exception.dateKey) ?? true)
            }
            .sorted { $0.dateKey < $1.dateKey }

        let groupedByNote = Dictionary(grouping: leaveExceptions, by: \.note)
        return groupedByNote.flatMap { note, noteExceptions in
            makeRanges(title: title(for: note), note: note, dateKeys: noteExceptions.map(\.dateKey), kind: .extraRest)
        }
        .sorted { lhs, rhs in
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            return lhs.title < rhs.title
        }
    }

    func restRanges(
        holidayCalendar: HolidayCalendar,
        exceptions: [CalendarException],
        within allowedKeys: Set<String>? = nil
    ) -> [CalendarExceptionRange] {
        var keyedRestTitles: [String: (title: String, note: String, kind: CalendarDayMarkerKind)] = [:]

        for (key, name) in holidayCalendar.restDays where allowedKeys?.contains(key) ?? true {
            keyedRestTitles[key] = (name, "节假日：\(name)", .holidayRest)
        }

        for exception in exceptions where exception.kind == .restDayOverride && (allowedKeys?.contains(exception.dateKey) ?? true) {
            let title = title(for: exception.note)
            keyedRestTitles[exception.dateKey] = (title, exception.note, .extraRest)
        }

        let sortedKeys = keyedRestTitles.keys.sorted()
        guard !sortedKeys.isEmpty else { return [] }

        let candidateKeys = expandedToWholeWeeks(sortedKeys)
        var ranges: [CalendarExceptionRange] = []
        var currentBlock: [String] = []

        func flushCurrentBlock() {
            guard !currentBlock.isEmpty else { return }
            defer { currentBlock.removeAll() }

            let meaningfulInfos = currentBlock.compactMap { keyedRestTitles[$0] }
            guard !meaningfulInfos.isEmpty else { return }
            guard crossesWeek(currentBlock) || currentBlock.count >= 7 else { return }

            let title = meaningfulInfos.map(\.title).reduce("连续休息", combinedTitle)
            let note = Set(meaningfulInfos.map(\.note)).count == 1 ? meaningfulInfos[0].note : "连续休息"
            let kind: CalendarDayMarkerKind = meaningfulInfos.allSatisfy { $0.kind == .holidayRest } ? .holidayRest : .extraRest

            guard let range = makeRange(
                title: title,
                note: note,
                keys: expandedToWholeWeeks(currentBlock),
                kind: kind,
                restKeys: currentBlock
            ) else { return }
            ranges.append(range)
        }

        for key in candidateKeys {
            guard let date = DateKey(key).date(calendar: calendar) else { continue }
            let isExplicitRest = keyedRestTitles[key] != nil
            let isWeekendBridge = calendar.isWeekend(date)
            let isAllowed = allowedKeys?.contains(key) ?? true

            if isAllowed && (isExplicitRest || isWeekendBridge) {
                currentBlock.append(key)
            } else {
                flushCurrentBlock()
            }
        }
        flushCurrentBlock()

        return ranges.sorted { $0.start < $1.start }
    }

    private func makeRanges(title: String, note: String, dateKeys: [String], kind: CalendarDayMarkerKind) -> [CalendarExceptionRange] {
        var ranges: [CalendarExceptionRange] = []
        var currentKeys: [String] = []
        var previousDate: Date?

        for key in dateKeys.sorted() {
            guard let date = DateKey(key).date(calendar: calendar) else { continue }
            let isContinuous: Bool
            if let previousDate, let expected = calendar.date(byAdding: .day, value: 1, to: previousDate) {
                isContinuous = calendar.isDate(date, inSameDayAs: expected)
            } else {
                isContinuous = true
            }

            if !isContinuous {
                appendRange(title: title, note: note, keys: currentKeys, kind: kind, to: &ranges)
                currentKeys = []
            }

            currentKeys.append(key)
            previousDate = date
        }

        appendRange(title: title, note: note, keys: currentKeys, kind: kind, to: &ranges)
        return ranges
    }

    private func appendRange(title: String, note: String, keys: [String], kind: CalendarDayMarkerKind, to ranges: inout [CalendarExceptionRange]) {
        guard let range = makeRange(title: title, note: note, keys: keys, kind: kind) else { return }
        ranges.append(range)
    }

    private func makeRange(
        title: String,
        note: String,
        keys: [String],
        kind: CalendarDayMarkerKind,
        restKeys: [String]? = nil
    ) -> CalendarExceptionRange? {
        guard
            let firstKey = keys.first,
            let lastKey = keys.last,
            let start = DateKey(firstKey).date(calendar: calendar),
            let end = DateKey(lastKey).date(calendar: calendar)
        else { return nil }

        return CalendarExceptionRange(
            title: title,
            note: note,
            start: start,
            end: end,
            dateKeys: keys,
            restDateKeys: restKeys ?? keys,
            kind: kind
        )
    }

    private func isLeaveNote(_ note: String) -> Bool {
        note.contains("寒假")
            || note.contains("暑假")
            || note.hasPrefix("休假：")
            || note.hasPrefix("设置生成：")
    }

    private func title(for note: String) -> String {
        if note.hasPrefix("休假：") {
            return String(note.dropFirst("休假：".count))
        }
        if note.contains("寒假") { return "寒假休息" }
        if note.contains("暑假") { return "暑假休息" }
        return "连续休息"
    }

    private func combinedTitle(_ lhs: String, _ rhs: String) -> String {
        if lhs == rhs { return lhs }
        if lhs == "连续休息" { return rhs }
        if rhs == "连续休息" { return lhs }
        return "连续休息"
    }

    private func crossesWeek(_ keys: [String]) -> Bool {
        guard
            let firstKey = keys.first,
            let lastKey = keys.last,
            let first = DateKey(firstKey).date(calendar: calendar),
            let last = DateKey(lastKey).date(calendar: calendar)
        else { return false }
        let firstWeek = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: first)
        let lastWeek = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: last)
        return firstWeek.yearForWeekOfYear != lastWeek.yearForWeekOfYear || firstWeek.weekOfYear != lastWeek.weekOfYear
    }

    private func expandedToWholeWeeks(_ keys: [String]) -> [String] {
        guard
            let firstKey = keys.first,
            let lastKey = keys.last,
            let first = DateKey(firstKey).date(calendar: calendar),
            let last = DateKey(lastKey).date(calendar: calendar)
        else { return keys }

        let startComponents = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: first)
        let weekStart = calendar.date(from: startComponents).map(calendar.startOfDay(for:)) ?? first
        let lastWeekdayOffset = 8 - calendar.weekdayNumber(for: last)
        let weekEnd = calendar.date(byAdding: .day, value: lastWeekdayOffset, to: last).map(calendar.startOfDay(for:)) ?? last
        let days = max(0, (calendar.dateComponents([.day], from: weekStart, to: weekEnd).day ?? 0) + 1)
        return calendar.dateRange(from: weekStart, days: days).map { calendar.startOfDayKey(for: $0) }
    }
}
