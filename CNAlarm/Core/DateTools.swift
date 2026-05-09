import Foundation

struct DateKey: Hashable, Codable, Comparable, CustomStringConvertible {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    init(date: Date, calendar: Calendar = .chinaAlarm) {
        rawValue = DateKey.formatter(calendar: calendar).string(from: date)
    }

    var description: String { rawValue }

    static func < (lhs: DateKey, rhs: DateKey) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    func date(calendar: Calendar = .chinaAlarm) -> Date? {
        DateKey.formatter(calendar: calendar).date(from: rawValue)
    }

    private static func formatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}

struct ClockTime: Hashable, Codable, Comparable {
    var hour: Int
    var minute: Int

    static func < (lhs: ClockTime, rhs: ClockTime) -> Bool {
        lhs.minutesFromMidnight < rhs.minutesFromMidnight
    }

    var minutesFromMidnight: Int {
        hour * 60 + minute
    }

    var displayText: String {
        String(format: "%02d:%02d", hour, minute)
    }

    func adding(minutes delta: Int) -> ClockTime {
        let total = ((minutesFromMidnight + delta) % 1440 + 1440) % 1440
        return ClockTime(hour: total / 60, minute: total % 60)
    }
}

extension Calendar {
    static var chinaAlarm: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        calendar.firstWeekday = 2
        return calendar
    }

    func startOfDayKey(for date: Date) -> String {
        DateKey(date: startOfDay(for: date), calendar: self).rawValue
    }

    func date(from key: String, hour: Int = 0, minute: Int = 0) -> Date? {
        guard let day = DateKey(key).date(calendar: self) else { return nil }
        return date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }

    func dateRange(from start: Date, days: Int) -> [Date] {
        (0..<days).compactMap { date(byAdding: .day, value: $0, to: startOfDay(for: start)) }
    }

    func weekdayNumber(for date: Date) -> Int {
        component(.weekday, from: date)
    }

    func isWeekend(_ date: Date) -> Bool {
        [1, 7].contains(weekdayNumber(for: date))
    }
}

extension UUID {
    init(deterministic text: String) {
        var hashA: UInt64 = 1469598103934665603
        var hashB: UInt64 = 1099511628211
        for byte in text.utf8 {
            hashA ^= UInt64(byte)
            hashA &*= 1099511628211
            hashB &+= UInt64(byte) &* 16777619
            hashB ^= hashB << 13
            hashB ^= hashB >> 7
            hashB ^= hashB << 17
        }
        var bytes = [UInt8](repeating: 0, count: 16)
        for index in 0..<8 {
            bytes[index] = UInt8((hashA >> UInt64((7 - index) * 8)) & 0xff)
            bytes[index + 8] = UInt8((hashB >> UInt64((7 - index) * 8)) & 0xff)
        }
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        self.init(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
