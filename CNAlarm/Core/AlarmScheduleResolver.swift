import Foundation

struct ScheduledAlarmInstance: Hashable, Identifiable {
    var id: UUID
    var profileID: UUID
    var fireDate: Date
    var label: String
    var soundIdentifier: String
    var allowSnooze: Bool
    var snoozeMinutes: Int
    var comboChildIndex: Int?

    var time: ClockTime {
        let components = Calendar.chinaAlarm.dateComponents([.hour, .minute], from: fireDate)
        return ClockTime(hour: components.hour ?? 0, minute: components.minute ?? 0)
    }
}

struct AlarmScheduleResolver {
    var calendar: Calendar = .chinaAlarm
    var workdayResolver = WorkdayResolver()

    func resolve(
        profiles: [AlarmProfile],
        templates: [AlarmComboTemplate],
        holidayCalendar: HolidayCalendar,
        companyRules: [CompanyCalendarRule],
        exceptions: [CalendarException],
        from startDate: Date = Date(),
        days: Int = 30
    ) -> [ScheduledAlarmInstance] {
        let start = calendar.startOfDay(for: startDate)
        var instances: [ScheduledAlarmInstance] = []

        for date in calendar.dateRange(from: start, days: days) {
            for profile in profiles where profile.isEnabled {
                guard shouldFire(profile: profile, on: date, holidayCalendar: holidayCalendar, companyRules: companyRules, exceptions: exceptions) else {
                    continue
                }
                switch profile.mode {
                case .single:
                    if let instance = singleInstance(profile: profile, date: date, exceptions: exceptions) {
                        instances.append(instance)
                    }
                case .combo:
                    let template = templates.first(where: { $0.id == profile.comboTemplateID })
                    instances.append(contentsOf: comboInstances(profile: profile, template: template, date: date, exceptions: exceptions))
                }
            }
            instances.append(contentsOf: extraAlarmInstances(on: date, exceptions: exceptions))
        }

        return instances
            .filter { $0.fireDate >= startDate }
            .sorted { $0.fireDate < $1.fireDate }
    }

    func comboTimes(
        deadline: ClockTime,
        anchorMode: ComboAnchorMode,
        offsets: [Int]
    ) -> [ClockTime] {
        offsets.map { deadline.adding(minutes: $0) }
    }

    private func shouldFire(
        profile: AlarmProfile,
        on date: Date,
        holidayCalendar: HolidayCalendar,
        companyRules: [CompanyCalendarRule],
        exceptions: [CalendarException]
    ) -> Bool {
        let key = calendar.startOfDayKey(for: date)
        if exceptions.contains(where: { $0.dateKey == key && $0.profileID == profile.id && $0.kind == .skipAlarm }) {
            return false
        }
        if profile.followsSmartWorkday {
            return workdayResolver.isWorkday(date, holidayCalendar: holidayCalendar, companyRules: companyRules, exceptions: exceptions)
        }
        return profile.recurrenceWeekdays.contains(calendar.weekdayNumber(for: date))
    }

    private func singleInstance(profile: AlarmProfile, date: Date, exceptions: [CalendarException]) -> ScheduledAlarmInstance? {
        let key = calendar.startOfDayKey(for: date)
        let override = exceptions.first {
            $0.dateKey == key && $0.profileID == profile.id && $0.kind == .childTime && $0.childIndex < 0
        }
        let hour = override?.hour ?? profile.hour
        let minute = override?.minute ?? profile.minute
        guard let fireDate = calendar.date(from: key, hour: hour, minute: minute) else { return nil }
        return ScheduledAlarmInstance(
            id: UUID(deterministic: "\(profile.id)-\(key)-single"),
            profileID: profile.id,
            fireDate: fireDate,
            label: profile.label,
            soundIdentifier: profile.soundIdentifier,
            allowSnooze: profile.allowSnooze,
            snoozeMinutes: profile.snoozeMinutes,
            comboChildIndex: nil
        )
    }

    private func comboInstances(
        profile: AlarmProfile,
        template: AlarmComboTemplate?,
        date: Date,
        exceptions: [CalendarException]
    ) -> [ScheduledAlarmInstance] {
        let key = calendar.startOfDayKey(for: date)
        let move = exceptions.first { $0.dateKey == key && $0.profileID == profile.id && $0.kind == .moveComboDeadline }
        let deadline = ClockTime(hour: move?.hour ?? profile.hour, minute: move?.minute ?? profile.minute)
        let offsets = profile.comboOffsets.isEmpty ? (template?.offsets ?? [-10, -5, 0]) : profile.comboOffsets
        let sound = profile.soundIdentifier == SoundLibrary.alarmKitDefaultIdentifier ? (template?.defaultSoundIdentifier ?? profile.soundIdentifier) : profile.soundIdentifier
        guard let deadlineDate = calendar.date(from: key, hour: deadline.hour, minute: deadline.minute) else {
            return []
        }

        return offsets.enumerated().compactMap { index, offset in
            if exceptions.contains(where: { $0.dateKey == key && $0.profileID == profile.id && $0.kind == .childSkip && $0.childIndex == index }) {
                return nil
            }
            let childOverride = exceptions.first {
                $0.dateKey == key && $0.profileID == profile.id && $0.kind == .childTime && $0.childIndex == index
            }
            let fireDate: Date?
            if let childOverride {
                fireDate = calendar.date(from: key, hour: childOverride.hour, minute: childOverride.minute)
            } else {
                fireDate = calendar.date(byAdding: .minute, value: offset, to: deadlineDate)
            }
            guard let fireDate else { return nil }
            return ScheduledAlarmInstance(
                id: UUID(deterministic: "\(profile.id)-\(key)-combo-\(index)"),
                profileID: profile.id,
                fireDate: fireDate,
                label: "\(profile.label) \(index + 1)/\(offsets.count)",
                soundIdentifier: sound,
                allowSnooze: profile.allowSnooze,
                snoozeMinutes: profile.snoozeMinutes,
                comboChildIndex: index
            )
        }
    }

    private func extraAlarmInstances(on date: Date, exceptions: [CalendarException]) -> [ScheduledAlarmInstance] {
        let key = calendar.startOfDayKey(for: date)
        return exceptions
            .filter { $0.dateKey == key && $0.kind == .extraAlarm }
            .compactMap { exception in
                guard let fireDate = calendar.date(from: key, hour: exception.hour, minute: exception.minute) else { return nil }
                return ScheduledAlarmInstance(
                    id: UUID(deterministic: "extra-\(exception.id)-\(key)"),
                    profileID: exception.profileID ?? exception.id,
                    fireDate: fireDate,
                    label: exception.note.isEmpty ? "临时闹铃" : exception.note,
                    soundIdentifier: exception.soundIdentifier ?? SoundLibrary.defaultSoundIdentifier,
                    allowSnooze: true,
                    snoozeMinutes: 5,
                    comboChildIndex: nil
                )
            }
    }
}
