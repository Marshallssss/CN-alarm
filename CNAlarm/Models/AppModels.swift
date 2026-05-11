import Foundation
import SwiftData

enum AlarmMode: String, Codable, CaseIterable, Identifiable {
    case single
    case combo

    var id: String { rawValue }
    var title: String { self == .single ? "普通闹铃" : "闹铃组合" }
}

enum ComboAnchorMode: String, Codable, CaseIterable, Identifiable {
    case lastRingIsDeadline
    case firstRingIsDeadline

    var id: String { rawValue }
    var title: String {
        switch self {
        case .lastRingIsDeadline: "最后一响是 DDL"
        case .firstRingIsDeadline: "第一响是 DDL"
        }
    }
}

enum CalendarExceptionKind: String, Codable, CaseIterable, Identifiable {
    case restDayOverride
    case workdayOverride
    case skipAlarm
    case extraAlarm
    case moveComboDeadline
    case childSkip
    case childTime

    var id: String { rawValue }
    var title: String {
        switch self {
        case .restDayOverride: "当天休息"
        case .workdayOverride: "当天上班"
        case .skipAlarm: "跳过闹铃"
        case .extraAlarm: "新增临时闹铃"
        case .moveComboDeadline: "移动组合 DDL"
        case .childSkip: "跳过子闹铃"
        case .childTime: "调整子闹铃"
        }
    }
}

enum CompanyRuleKind: String, Codable, CaseIterable, Identifiable {
    case alternateSaturday
    case lastSaturdayOfMonth
    case nthWeekdayOfMonth
    case singleDayOff

    var id: String { rawValue }
    var title: String {
        switch self {
        case .alternateSaturday: "大小周"
        case .lastSaturdayOfMonth: "月末周六"
        case .nthWeekdayOfMonth: "每月第 N 个周几"
        case .singleDayOff: "单休"
        }
    }
}

enum ReminderRuleKind: String, Codable, CaseIterable, Identifiable {
    case fridayNight
    case holidayLead
    case makeupWorkdayEve

    var id: String { rawValue }
    var title: String {
        switch self {
        case .fridayNight: "周五晚检查"
        case .holidayLead: "节假日前提醒"
        case .makeupWorkdayEve: "调班前一晚"
        }
    }
}

enum SoundKind: String, Codable, CaseIterable, Identifiable {
    case alarmKitDefault
    case bundledSleep
    case imported

    var id: String { rawValue }
    var title: String {
        switch self {
        case .alarmKitDefault: "系统默认"
        case .bundledSleep: "睡眠风格"
        case .imported: "导入铃声"
        }
    }
}

enum SoundLibrary {
    static let alarmKitDefaultIdentifier = "default"
    static let defaultSoundIdentifier = "cnalarm_soft_chime.wav"
}

@Model
final class AlarmProfile {
    @Attribute(.unique) var id: UUID
    var label: String
    var modeRaw: String
    var isEnabled: Bool
    var hour: Int
    var minute: Int
    var recurrenceWeekdaysCSV: String
    var followsSmartWorkday: Bool
    var allowSnooze: Bool
    var snoozeMinutes: Int
    var soundIdentifier: String
    var comboTemplateID: UUID?
    var comboAnchorRaw: String
    var comboOffsetsCSV: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        label: String,
        mode: AlarmMode,
        isEnabled: Bool = true,
        hour: Int,
        minute: Int,
        recurrenceWeekdays: [Int] = [2, 3, 4, 5, 6],
        followsSmartWorkday: Bool = true,
        allowSnooze: Bool = true,
        snoozeMinutes: Int = 5,
        soundIdentifier: String = SoundLibrary.defaultSoundIdentifier,
        comboTemplateID: UUID? = nil,
        comboAnchorMode: ComboAnchorMode = .lastRingIsDeadline,
        comboOffsets: [Int] = [-10, -5, 0],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.label = label
        self.modeRaw = mode.rawValue
        self.isEnabled = isEnabled
        self.hour = hour
        self.minute = minute
        self.recurrenceWeekdaysCSV = recurrenceWeekdays.csvString
        self.followsSmartWorkday = followsSmartWorkday
        self.allowSnooze = allowSnooze
        self.snoozeMinutes = snoozeMinutes
        self.soundIdentifier = soundIdentifier
        self.comboTemplateID = comboTemplateID
        self.comboAnchorRaw = comboAnchorMode.rawValue
        self.comboOffsetsCSV = comboOffsets.csvString
        self.createdAt = createdAt
    }

    var mode: AlarmMode {
        get { AlarmMode(rawValue: modeRaw) ?? .single }
        set { modeRaw = newValue.rawValue }
    }

    var comboAnchorMode: ComboAnchorMode {
        get { ComboAnchorMode(rawValue: comboAnchorRaw) ?? .lastRingIsDeadline }
        set { comboAnchorRaw = newValue.rawValue }
    }

    var recurrenceWeekdays: [Int] {
        get { recurrenceWeekdaysCSV.csvInts }
        set { recurrenceWeekdaysCSV = newValue.csvString }
    }

    var comboOffsets: [Int] {
        get { comboOffsetsCSV.csvInts }
        set { comboOffsetsCSV = newValue.csvString }
    }

    static func defaultSingle() -> AlarmProfile {
        AlarmProfile(label: "工作日闹铃", mode: .single, hour: 8, minute: 30)
    }

    static func defaultCombo(template: AlarmComboTemplate?) -> AlarmProfile {
        AlarmProfile(
            label: "起床组合",
            mode: .combo,
            hour: 9,
            minute: 0,
            allowSnooze: template?.allowSnooze ?? true,
            soundIdentifier: template?.defaultSoundIdentifier ?? SoundLibrary.defaultSoundIdentifier,
            comboTemplateID: template?.id,
            comboAnchorMode: template?.anchorMode ?? .lastRingIsDeadline,
            comboOffsets: template?.offsets ?? [-10, -5, 0]
        )
    }
}

@Model
final class AlarmComboTemplate {
    @Attribute(.unique) var id: UUID
    var name: String
    var anchorRaw: String
    var offsetsCSV: String
    var defaultSoundIdentifier: String
    var allowSnooze: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        anchorMode: ComboAnchorMode,
        offsets: [Int],
        defaultSoundIdentifier: String = SoundLibrary.defaultSoundIdentifier,
        allowSnooze: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.anchorRaw = anchorMode.rawValue
        self.offsetsCSV = offsets.csvString
        self.defaultSoundIdentifier = defaultSoundIdentifier
        self.allowSnooze = allowSnooze
        self.createdAt = createdAt
    }

    var anchorMode: ComboAnchorMode {
        get { ComboAnchorMode(rawValue: anchorRaw) ?? .lastRingIsDeadline }
        set { anchorRaw = newValue.rawValue }
    }

    var offsets: [Int] {
        get { offsetsCSV.csvInts }
        set { offsetsCSV = newValue.csvString }
    }

    static func defaultTemplates() -> [AlarmComboTemplate] {
        [
            AlarmComboTemplate(name: "三段叫醒", anchorMode: .firstRingIsDeadline, offsets: [0, 5, 10]),
            AlarmComboTemplate(name: "DDL 倒推", anchorMode: .lastRingIsDeadline, offsets: [-10, -5, 0])
        ]
    }
}

@Model
final class AlarmComboInstance {
    @Attribute(.unique) var id: UUID
    var profileID: UUID
    var templateID: UUID?
    var anchorRaw: String
    var offsetsCSV: String

    init(
        id: UUID = UUID(),
        profileID: UUID,
        templateID: UUID?,
        anchorMode: ComboAnchorMode,
        offsets: [Int]
    ) {
        self.id = id
        self.profileID = profileID
        self.templateID = templateID
        self.anchorRaw = anchorMode.rawValue
        self.offsetsCSV = offsets.csvString
    }
}

@Model
final class AlarmComboChildOverride {
    @Attribute(.unique) var id: UUID
    var profileID: UUID
    var dateKey: String
    var childIndex: Int
    var skip: Bool
    var hour: Int
    var minute: Int

    init(id: UUID = UUID(), profileID: UUID, dateKey: String, childIndex: Int, skip: Bool, hour: Int, minute: Int) {
        self.id = id
        self.profileID = profileID
        self.dateKey = dateKey
        self.childIndex = childIndex
        self.skip = skip
        self.hour = hour
        self.minute = minute
    }
}

@Model
final class HolidayDataset {
    @Attribute(.unique) var id: UUID
    var sourceURL: String
    var fetchedAt: Date
    var rawJSON: String

    init(
        id: UUID = UUID(),
        sourceURL: String = HolidayCalendarSource.defaultURL.absoluteString,
        fetchedAt: Date = Date.distantPast,
        rawJSON: String = ""
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.fetchedAt = fetchedAt
        self.rawJSON = rawJSON
    }
}

@Model
final class CompanyCalendarRule {
    @Attribute(.unique) var id: UUID
    var name: String
    var kindRaw: String
    var isEnabled: Bool
    var anchorDate: Date
    var ordinal: Int
    var weekday: Int

    init(
        id: UUID = UUID(),
        name: String,
        kind: CompanyRuleKind,
        isEnabled: Bool = true,
        anchorDate: Date = Date(),
        ordinal: Int = 1,
        weekday: Int = 7
    ) {
        self.id = id
        self.name = name
        self.kindRaw = kind.rawValue
        self.isEnabled = isEnabled
        self.anchorDate = anchorDate
        self.ordinal = ordinal
        self.weekday = weekday
    }

    var kind: CompanyRuleKind {
        get { CompanyRuleKind(rawValue: kindRaw) ?? .lastSaturdayOfMonth }
        set { kindRaw = newValue.rawValue }
    }
}

@Model
final class CalendarException {
    @Attribute(.unique) var id: UUID
    var dateKey: String
    var kindRaw: String
    var profileID: UUID?
    var childIndex: Int
    var hour: Int
    var minute: Int
    var note: String
    var soundIdentifier: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        dateKey: String,
        kind: CalendarExceptionKind,
        profileID: UUID? = nil,
        childIndex: Int = -1,
        hour: Int = 8,
        minute: Int = 0,
        note: String = "",
        soundIdentifier: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.dateKey = dateKey
        self.kindRaw = kind.rawValue
        self.profileID = profileID
        self.childIndex = childIndex
        self.hour = hour
        self.minute = minute
        self.note = note
        self.soundIdentifier = soundIdentifier
        self.createdAt = createdAt
    }

    var kind: CalendarExceptionKind {
        get { CalendarExceptionKind(rawValue: kindRaw) ?? .skipAlarm }
        set { kindRaw = newValue.rawValue }
    }
}

@Model
final class ReminderRule {
    @Attribute(.unique) var id: UUID
    var kindRaw: String
    var isEnabled: Bool
    var hour: Int
    var minute: Int
    var leadDaysCSV: String

    init(
        id: UUID = UUID(),
        kind: ReminderRuleKind,
        isEnabled: Bool = true,
        hour: Int = 20,
        minute: Int = 0,
        leadDays: [Int] = []
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.isEnabled = isEnabled
        self.hour = hour
        self.minute = minute
        self.leadDaysCSV = leadDays.csvString
    }

    var kind: ReminderRuleKind {
        get { ReminderRuleKind(rawValue: kindRaw) ?? .fridayNight }
        set { kindRaw = newValue.rawValue }
    }

    var leadDays: [Int] {
        get { leadDaysCSV.csvInts }
        set { leadDaysCSV = newValue.csvString }
    }

    static func defaults() -> [ReminderRule] {
        [
            ReminderRule(kind: .fridayNight),
            ReminderRule(kind: .holidayLead, leadDays: [3, 1]),
            ReminderRule(kind: .makeupWorkdayEve)
        ]
    }
}

@Model
final class ReminderEvent {
    @Attribute(.unique) var id: UUID
    var fireDate: Date
    var title: String
    var message: String
    var targetDateKey: String
    var actionRaw: String
    var isResolved: Bool

    init(
        id: UUID = UUID(),
        fireDate: Date,
        title: String,
        message: String,
        targetDateKey: String,
        actionRaw: String,
        isResolved: Bool = false
    ) {
        self.id = id
        self.fireDate = fireDate
        self.title = title
        self.message = message
        self.targetDateKey = targetDateKey
        self.actionRaw = actionRaw
        self.isResolved = isResolved
    }
}

@Model
final class SoundAsset {
    @Attribute(.unique) var id: UUID
    var name: String
    var kindRaw: String
    var filename: String
    var createdAt: Date

    init(id: UUID = UUID(), name: String, kind: SoundKind, filename: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.kindRaw = kind.rawValue
        self.filename = filename
        self.createdAt = createdAt
    }

    var kind: SoundKind {
        get { SoundKind(rawValue: kindRaw) ?? .alarmKitDefault }
        set { kindRaw = newValue.rawValue }
    }
}

extension Array where Element == Int {
    var csvString: String { map(String.init).joined(separator: ",") }
}

extension String {
    var csvInts: [Int] {
        split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }
}
