import XCTest
import SwiftData
@testable import CNAlarm

final class CNAlarmCoreTests: XCTestCase {
    private let calendar = Calendar.chinaAlarm

    func testHolidayParserMarksLaborHolidayAndMakeupWorkday() throws {
        let holiday = HolidayCalendar.fixture2026

        XCTAssertTrue(holiday.isHolidayRestDay("2026-05-01"))
        XCTAssertTrue(holiday.isHolidayRestDay("2026-05-05"))
        XCTAssertTrue(holiday.isCompensatedWorkday("2026-05-09"))
    }

    func testWorkdayResolverPrecedenceUsesExceptionBeforeHolidayAndRules() throws {
        let resolver = WorkdayResolver(calendar: calendar)
        let laborDay = try XCTUnwrap(calendar.date(from: "2026-05-01"))
        let makeupDay = try XCTUnwrap(calendar.date(from: "2026-05-09"))

        XCTAssertFalse(resolver.isWorkday(laborDay, holidayCalendar: .fixture2026, companyRules: [], exceptions: []))
        XCTAssertTrue(resolver.isWorkday(makeupDay, holidayCalendar: .fixture2026, companyRules: [], exceptions: []))

        let restException = CalendarException(dateKey: "2026-05-09", kind: .restDayOverride)
        XCTAssertFalse(resolver.isWorkday(makeupDay, holidayCalendar: .fixture2026, companyRules: [], exceptions: [restException]))

        let workdayException = CalendarException(dateKey: "2026-05-01", kind: .workdayOverride)
        XCTAssertTrue(resolver.isWorkday(laborDay, holidayCalendar: .fixture2026, companyRules: [], exceptions: [workdayException]))
    }

    func testCompanyRulesSupportAlternateAndLastSaturday() throws {
        let resolver = WorkdayResolver(calendar: calendar)
        let anchor = try XCTUnwrap(calendar.date(from: "2026-05-02"))
        let alternate = CompanyCalendarRule(name: "大小周", kind: .alternateSaturday, anchorDate: anchor)
        let firstSaturday = try XCTUnwrap(calendar.date(from: "2026-05-02"))
        let secondSaturday = try XCTUnwrap(calendar.date(from: "2026-05-09"))

        XCTAssertTrue(resolver.isWorkday(firstSaturday, holidayCalendar: .empty, companyRules: [alternate], exceptions: []))
        XCTAssertFalse(resolver.isWorkday(secondSaturday, holidayCalendar: .empty, companyRules: [alternate], exceptions: []))

        let lastSaturdayRule = CompanyCalendarRule(name: "月末周六", kind: .lastSaturdayOfMonth)
        let lastSaturday = try XCTUnwrap(calendar.date(from: "2026-05-30"))
        XCTAssertTrue(resolver.isWorkday(lastSaturday, holidayCalendar: .empty, companyRules: [lastSaturdayRule], exceptions: []))

        let singleDayOffRule = CompanyCalendarRule(name: "单休", kind: .singleDayOff)
        XCTAssertTrue(resolver.isWorkday(secondSaturday, holidayCalendar: .empty, companyRules: [singleDayOffRule], exceptions: []))
    }

    func testComboTimesSupportBothDeadlineAnchors() {
        let resolver = AlarmScheduleResolver(calendar: calendar)

        let lastIsDeadline = resolver.comboTimes(
            deadline: ClockTime(hour: 9, minute: 0),
            anchorMode: .lastRingIsDeadline,
            offsets: [-10, -5, 0]
        )
        XCTAssertEqual(lastIsDeadline.map(\.displayText), ["08:50", "08:55", "09:00"])

        let firstIsDeadline = resolver.comboTimes(
            deadline: ClockTime(hour: 9, minute: 0),
            anchorMode: .firstRingIsDeadline,
            offsets: [0, 5, 10]
        )
        XCTAssertEqual(firstIsDeadline.map(\.displayText), ["09:00", "09:05", "09:10"])
    }

    func testComboTemplateCanBeCopiedAndOverriddenWithoutMutatingTemplate() throws {
        let template = AlarmComboTemplate(name: "三段叫醒", anchorMode: .firstRingIsDeadline, offsets: [0, 5, 10])
        let profile = AlarmProfile.defaultCombo(template: template)

        profile.comboOffsets = [0, 3, 6, 9]

        XCTAssertEqual(template.offsets, [0, 5, 10])
        XCTAssertEqual(profile.comboOffsets, [0, 3, 6, 9])
    }

    func testMoveWholeComboAndChildOverridesAffectScheduledInstances() throws {
        let profile = AlarmProfile(label: "早起组合", mode: .combo, hour: 9, minute: 0, comboAnchorMode: .firstRingIsDeadline, comboOffsets: [0, 5, 10])
        let move = CalendarException(dateKey: "2026-05-11", kind: .moveComboDeadline, profileID: profile.id, hour: 8, minute: 0)
        let childSkip = CalendarException(dateKey: "2026-05-11", kind: .childSkip, profileID: profile.id, childIndex: 1)
        let childTime = CalendarException(dateKey: "2026-05-11", kind: .childTime, profileID: profile.id, childIndex: 2, hour: 8, minute: 20)
        let start = try XCTUnwrap(calendar.date(from: "2026-05-11"))

        let instances = AlarmScheduleResolver(calendar: calendar).resolve(
            profiles: [profile],
            templates: [],
            holidayCalendar: .empty,
            companyRules: [],
            exceptions: [move, childSkip, childTime],
            from: start,
            days: 1
        )

        XCTAssertEqual(instances.map { $0.time.displayText }, ["08:00", "08:20"])
    }

    func testReminderPlannerCreatesFridayHolidayAndMakeupDrafts() throws {
        let rules = ReminderRule.defaults()
        let start = try XCTUnwrap(calendar.date(from: "2026-04-24"))
        let drafts = ReminderPlanner(calendar: calendar).plan(
            rules: rules,
            holidayCalendar: .fixture2026,
            from: start,
            days: 20
        )

        XCTAssertTrue(drafts.contains(where: { $0.title == "周五晚检查闹铃" }))
        XCTAssertTrue(drafts.contains(where: { $0.title.contains("劳动节前 3 天") }))
        XCTAssertTrue(drafts.contains(where: { $0.title == "明天调班上班" && $0.targetDateKey == "2026-05-09" }))
    }

    func testReminderPlannerStillCreatesHolidayAndMakeupDraftsAfterMay() throws {
        let rules = ReminderRule.defaults()
        let start = try XCTUnwrap(calendar.date(from: "2026-05-09", hour: 16, minute: 0))
        let drafts = ReminderPlanner(calendar: calendar).plan(
            rules: rules,
            holidayCalendar: .fixture2026,
            from: start,
            days: 370
        )

        XCTAssertTrue(drafts.contains(where: { $0.title.contains("端午节前 3 天") && $0.targetDateKey == "2026-06-19" }))
        XCTAssertTrue(drafts.contains(where: { $0.title == "明天调班上班" && $0.targetDateKey == "2026-09-20" }))
        XCTAssertTrue(drafts.contains(where: { $0.title == "明天调班上班" && $0.targetDateKey == "2026-10-10" }))
    }

    func testResolverFiltersAlreadyElapsedInstancesOnStartDay() throws {
        let profile = AlarmProfile(label: "早上", mode: .single, hour: 8, minute: 30, recurrenceWeekdays: [7], followsSmartWorkday: false)
        let start = try XCTUnwrap(calendar.date(from: "2026-05-09", hour: 12, minute: 0))

        let instances = AlarmScheduleResolver(calendar: calendar).resolve(
            profiles: [profile],
            templates: [],
            holidayCalendar: .empty,
            companyRules: [],
            exceptions: [],
            from: start,
            days: 1
        )

        XCTAssertTrue(instances.isEmpty)
    }

    func testExtraAlarmKeepsSelectedSound() throws {
        let start = try XCTUnwrap(calendar.date(from: "2026-05-09", hour: 7, minute: 0))
        let extra = CalendarException(
            dateKey: "2026-05-09",
            kind: .extraAlarm,
            hour: 8,
            minute: 10,
            note: "临时闹铃",
            soundIdentifier: "cnalarm_bright_ping.wav"
        )

        let instances = AlarmScheduleResolver(calendar: calendar).resolve(
            profiles: [],
            templates: [],
            holidayCalendar: .empty,
            companyRules: [],
            exceptions: [extra],
            from: start,
            days: 1
        )

        XCTAssertEqual(instances.map(\.time.displayText), ["08:10"])
        XCTAssertEqual(instances.first?.soundIdentifier, "cnalarm_bright_ping.wav")
    }

    func testComboDeadlineOffsetsCanCrossMidnight() throws {
        let profile = AlarmProfile(
            label: "午夜组合",
            mode: .combo,
            hour: 0,
            minute: 5,
            recurrenceWeekdays: [1],
            followsSmartWorkday: false,
            comboOffsets: [-10, -5, 0]
        )
        let start = try XCTUnwrap(calendar.date(from: "2026-05-09", hour: 20, minute: 0))

        let instances = AlarmScheduleResolver(calendar: calendar).resolve(
            profiles: [profile],
            templates: [],
            holidayCalendar: .empty,
            companyRules: [],
            exceptions: [],
            from: start,
            days: 2
        )

        XCTAssertEqual(instances.map { calendar.startOfDayKey(for: $0.fireDate) }, ["2026-05-09", "2026-05-10", "2026-05-10"])
        XCTAssertEqual(instances.map { $0.time.displayText }, ["23:55", "00:00", "00:05"])
    }

    func testReminderPlannerFiltersAlreadyElapsedReminders() throws {
        let start = try XCTUnwrap(calendar.date(from: "2026-05-01", hour: 21, minute: 0))

        let drafts = ReminderPlanner(calendar: calendar).plan(
            rules: ReminderRule.defaults(),
            holidayCalendar: .fixture2026,
            from: start,
            days: 10
        )

        XCTAssertFalse(drafts.contains { $0.fireDate < start })
    }

    @MainActor
    func testNotificationShortcutActionsBecomeCalendarExceptions() throws {
        PendingNotificationActionStore.clear()
        let schema = Schema([AlarmProfile.self, CalendarException.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let profile = AlarmProfile.defaultSingle()
        context.insert(profile)

        PendingNotificationActionStore.record(action: .skip, targetDateKey: "2026-05-09")
        PendingNotificationActionStore.record(action: .addTemporary, targetDateKey: "2026-05-10")
        NotificationActionApplier.applyPendingActions(context: context)

        let exceptions = try context.fetch(FetchDescriptor<CalendarException>())
        XCTAssertTrue(exceptions.contains { $0.dateKey == "2026-05-09" && $0.kind == .skipAlarm && $0.profileID == profile.id })
        XCTAssertTrue(exceptions.contains { $0.dateKey == "2026-05-10" && $0.kind == .extraAlarm })
        XCTAssertTrue(PendingNotificationActionStore.pendingActions().isEmpty)
    }
}
