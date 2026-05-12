import SwiftData
import SwiftUI

struct AlarmListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AlarmProfile.createdAt) private var profiles: [AlarmProfile]
    @Query(sort: \AlarmComboTemplate.createdAt) private var templates: [AlarmComboTemplate]
    @Query private var exceptions: [CalendarException]
    @Query private var companyRules: [CompanyCalendarRule]
    @Query private var holidayDatasets: [HolidayDataset]
    @State private var syncStatus: String?
    @State private var selectedDate: Date?
    @State private var draftProfile: AlarmProfile?
    @State private var futurePreviewSnapshot: FuturePreviewSnapshot?
    @State private var pendingFuturePreviewDate: Date?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    MainPageHeader("中国调休闹铃") {
                        addAlarmMenu
                    }
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                if let syncStatus {
                    Section {
                        Text(syncStatus)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    AlarmCalendarOverviewCard(
                        title: "本周与下周",
                        dates: calendarOverviewDates,
                        instances: calendarOverviewInstances,
                        exceptions: exceptions,
                        holidayCalendar: holidayCalendar,
                        companyRules: companyRules,
                        minimumHeight: 250,
                        onSelectDate: { selectedDate = $0 },
                        onFuturePreview: {
                            futurePreviewSnapshot = makeFuturePreviewSnapshot()
                        }
                    )
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                        .listRowBackground(Color.clear)
                }

                Section("已启用") {
                    if profiles.isEmpty {
                        ContentUnavailableView("还没有闹铃", systemImage: "alarm", description: Text("添加普通闹铃或闹铃组合。"))
                    }
                    ForEach(sortedProfiles) { profile in
                        NavigationLink {
                            AlarmEditorView(profile: profile, onSave: { _ in
                                scheduleAfterMutation()
                            })
                        } label: {
                            AlarmRow(profile: profile) {
                                scheduleAfterMutation()
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                modelContext.delete(profile)
                                scheduleAfterMutation()
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }

                Section("未来实例") {
                    if upcomingDayGroups.isEmpty {
                        Text("未来三周暂无闹铃实例")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(upcomingDayGroups.prefix(7)) { group in
                        UpcomingDayRow(group: group)
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .contentMargins(.top, 0, for: .scrollContent)
            .sheet(item: selectedCalendarDateBinding) { selection in
                CalendarDateActionSheet(
                    date: selection.date,
                    profiles: profiles,
                    exceptions: exceptions,
                    onApply: applyCalendarAction,
                    onChanged: scheduleAfterMutation
                )
            }
            .sheet(item: $futurePreviewSnapshot, onDismiss: presentPendingFuturePreviewDate) { snapshot in
                FuturePreviewCalendarSheet(
                    monthGroups: snapshot.monthGroups,
                    exceptions: exceptions,
                    holidayCalendar: holidayCalendar,
                    companyRules: companyRules
                ) { date in
                    pendingFuturePreviewDate = date
                    futurePreviewSnapshot = nil
                }
            }
            .sheet(item: $draftProfile) { profile in
                NavigationStack {
                    AlarmEditorView(
                        profile: profile,
                        isNewProfile: true,
                        onSave: { savedProfile in
                            modelContext.insert(savedProfile)
                            draftProfile = nil
                            scheduleAfterMutation()
                        },
                        onCancel: {
                            draftProfile = nil
                        }
                    )
                }
            }
        }
    }

    private var addAlarmMenu: some View {
        Menu {
            Button {
                draftProfile = AlarmProfile.defaultSingle()
            } label: {
                Label("普通闹铃", systemImage: "alarm")
            }
            Button {
                draftProfile = AlarmProfile.defaultCombo(template: templates.first)
            } label: {
                Label("闹铃组合", systemImage: "square.stack.3d.up")
            }
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.title2)
                .foregroundStyle(.orange)
                .frame(width: 46, height: 46)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(Circle())
        }
        .accessibilityLabel("添加闹铃")
    }

    private var upcomingInstances: [ScheduledAlarmInstance] {
        return AlarmScheduleResolver().resolve(
            profiles: profiles,
            templates: templates,
            holidayCalendar: holidayCalendar,
            companyRules: companyRules,
            exceptions: exceptions,
            days: 21
        )
    }

    private var sortedProfiles: [AlarmProfile] {
        profiles.sorted { lhs, rhs in
            let lhsTime = ClockTime(hour: lhs.hour, minute: lhs.minute)
            let rhsTime = ClockTime(hour: rhs.hour, minute: rhs.minute)
            if lhsTime != rhsTime { return lhsTime < rhsTime }
            if lhs.label != rhs.label { return lhs.label < rhs.label }
            return lhs.createdAt < rhs.createdAt
        }
    }

    private var upcomingDayGroups: [UpcomingDayGroup] {
        let grouped = Dictionary(grouping: upcomingInstances) { DateKey(date: $0.fireDate).rawValue }
        return grouped.compactMap { key, instances in
            guard let date = DateKey(key).date() else { return nil }
            return UpcomingDayGroup(date: date, instances: instances.sorted { $0.fireDate < $1.fireDate })
        }
        .sorted { $0.date < $1.date }
    }

    private var calendarOverviewInstances: [ScheduledAlarmInstance] {
        AlarmScheduleResolver().resolve(
            profiles: profiles,
            templates: templates,
            holidayCalendar: holidayCalendar,
            companyRules: companyRules,
            exceptions: exceptions,
            from: calendarOverviewStartDate,
            days: 14
        )
    }

    private var calendarOverviewDates: [Date] {
        Calendar.chinaAlarm.dateRange(from: calendarOverviewStartDate, days: 14)
    }

    private var futurePreviewInstances: [ScheduledAlarmInstance] {
        AlarmScheduleResolver().resolve(
            profiles: profiles,
            templates: templates,
            holidayCalendar: holidayCalendar,
            companyRules: companyRules,
            exceptions: exceptions,
            from: futurePreviewStartDate,
            days: futurePreviewDayCount
        )
    }

    private var futurePreviewDates: [Date] {
        Calendar.chinaAlarm.dateRange(from: futurePreviewStartDate, days: futurePreviewDayCount)
    }

    private var futurePreviewStartDate: Date {
        calendarOverviewStartDate
    }

    private var futurePreviewDayCount: Int {
        let calendar = Calendar.chinaAlarm
        let currentYear = calendar.component(.year, from: Date())
        let nextYearStart = calendar.date(from: DateComponents(year: currentYear + 1, month: 1, day: 1)) ?? futurePreviewStartDate
        return max(0, calendar.dateComponents([.day], from: futurePreviewStartDate, to: nextYearStart).day ?? 0)
    }

    private var calendarOverviewStartDate: Date {
        let calendar = Calendar.chinaAlarm
        let now = Date()
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        return calendar.date(from: components).map(calendar.startOfDay(for:)) ?? calendar.startOfDay(for: now)
    }

    private var holidayCalendar: HolidayCalendar {
        holidayDatasets.last.map { HolidayCalendar.decodeStored($0.rawJSON) } ?? .fixture2026
    }

    private var selectedCalendarDateBinding: Binding<SelectedCalendarDate?> {
        Binding(
            get: { selectedDate.map(SelectedCalendarDate.init(date:)) },
            set: { selectedDate = $0?.date }
        )
    }

    private func syncSystemAlarms() async {
        do {
            let result = try await AlarmScheduleSyncService().sync(
                profiles: profiles,
                templates: templates,
                holidayDatasets: holidayDatasets,
                companyRules: companyRules,
                exceptions: exceptions
            )
            syncStatus = result.message
        } catch {
            syncStatus = "同步失败：\(error.localizedDescription)"
        }
    }

    private func applyCalendarAction(_ action: CalendarDateAction) {
        let key = Calendar.chinaAlarm.startOfDayKey(for: action.date)
        switch action.kind {
        case .workday:
            removeExceptions(on: key, kinds: [.restDayOverride, .workdayOverride])
            modelContext.insert(CalendarException(dateKey: key, kind: .workdayOverride, note: "首页日历设置"))
        case .restDay:
            removeExceptions(on: key, kinds: [.restDayOverride, .workdayOverride])
            modelContext.insert(CalendarException(dateKey: key, kind: .restDayOverride, note: "首页日历设置"))
        case .skipAlarms:
            removeExceptions(on: key, kinds: [.skipAlarm])
            let targetProfiles = profiles.isEmpty ? [nil] : profiles.map { Optional($0.id) }
            for profileID in targetProfiles {
                modelContext.insert(CalendarException(dateKey: key, kind: .skipAlarm, profileID: profileID, note: "首页日历设置"))
            }
        case .extraAlarm:
            modelContext.insert(CalendarException(dateKey: key, kind: .extraAlarm, hour: action.hour, minute: action.minute, note: "临时闹铃", soundIdentifier: action.soundIdentifier))
        case .clear:
            removeExceptions(on: key, kinds: CalendarExceptionKind.allCases)
        }
        selectedDate = nil
        scheduleAfterMutation()
    }

    private func presentPendingFuturePreviewDate() {
        guard let date = pendingFuturePreviewDate else { return }
        pendingFuturePreviewDate = nil
        selectedDate = date
    }

    private func makeFuturePreviewSnapshot() -> FuturePreviewSnapshot {
        let calendar = Calendar.chinaAlarm
        let holidayCalendar = self.holidayCalendar
        let companyRules = self.companyRules
        let exceptions = self.exceptions
        let dates = futurePreviewDates
        let instances = AlarmScheduleResolver().resolve(
            profiles: profiles,
            templates: templates,
            holidayCalendar: holidayCalendar,
            companyRules: companyRules,
            exceptions: exceptions,
            from: futurePreviewStartDate,
            days: futurePreviewDayCount
        )
        let resolver = WorkdayResolver(calendar: calendar)
        let previewKeys = Set(dates.map { calendar.startOfDayKey(for: $0) })
        let instancesByDate = Dictionary(grouping: instances) { calendar.startOfDayKey(for: $0.fireDate) }
        let restRanges = CalendarExceptionRangeGrouper(calendar: calendar)
            .restRanges(holidayCalendar: holidayCalendar, exceptions: exceptions, within: previewKeys)
        let restRangeGroups = restRanges.map { range in
            let instances = range.dateKeys.flatMap { instancesByDate[$0] ?? [] }
            return FuturePreviewRestRangeGroup(range: range, instances: instances)
        }
        let groupedRestRanges = Dictionary(grouping: restRangeGroups) { group in
            let range = group.range
            let components = calendar.dateComponents([.year, .month], from: range.restStart)
            return calendar.date(from: components).map(calendar.startOfDay(for:)) ?? calendar.startOfDay(for: range.restStart)
        }
        let restKeys = Set(restRanges.flatMap(\.dateKeys))
        let displayDates = dates.filter { !restKeys.contains(calendar.startOfDayKey(for: $0)) }

        let groupedDates = Dictionary(grouping: displayDates) { date in
            let components = calendar.dateComponents([.year, .month], from: date)
            return calendar.date(from: components).map(calendar.startOfDay(for:)) ?? calendar.startOfDay(for: date)
        }
        let monthStarts = Set(groupedDates.keys).union(groupedRestRanges.keys)
        let monthGroups = monthStarts.map { monthStart in
            let sortedDates = (groupedDates[monthStart] ?? []).sorted()
            let datesByWeek = Dictionary(grouping: sortedDates) { date in
                let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
                return calendar.date(from: components).map(calendar.startOfDay(for:)) ?? calendar.startOfDay(for: date)
            }
            let weekGroups = datesByWeek.map { weekStart, weekDates in
                let sortedWeekDates = weekDates.sorted()
                let weekInstances = sortedWeekDates.flatMap { date in
                    instancesByDate[calendar.startOfDayKey(for: date)] ?? []
                }
                let markersByDate = Dictionary(uniqueKeysWithValues: sortedWeekDates.map { date in
                    let key = calendar.startOfDayKey(for: date)
                    return (
                        key,
                        resolver.dayMarkers(
                            for: date,
                            holidayCalendar: holidayCalendar,
                            companyRules: companyRules,
                            exceptions: exceptions
                        )
                    )
                })
                return FuturePreviewWeekGroup(
                    monthStart: monthStart,
                    weekStart: weekStart,
                    dates: sortedWeekDates,
                    instances: weekInstances,
                    markersByDate: markersByDate
                )
            }
            .sorted { $0.weekStart < $1.weekStart }

            return FuturePreviewMonthGroup(
                monthStart: monthStart,
                weekGroups: weekGroups,
                restRanges: groupedRestRanges[monthStart] ?? []
            )
        }
        .sorted { $0.monthStart < $1.monthStart }

        return FuturePreviewSnapshot(monthGroups: monthGroups)
    }

    private func removeExceptions(on dateKey: String, kinds: [CalendarExceptionKind]) {
        for exception in exceptions where exception.dateKey == dateKey && kinds.contains(exception.kind) {
            modelContext.delete(exception)
        }
    }

    private func scheduleAfterMutation() {
        try? modelContext.save()
        Task {
            await Task.yield()
            await syncSystemAlarms()
        }
    }
}

private struct FuturePreviewSnapshot: Identifiable {
    let id = UUID()
    var monthGroups: [FuturePreviewMonthGroup]
}

private struct AlarmRow: View {
    @Bindable var profile: AlarmProfile
    var onChanged: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(ClockTime(hour: profile.hour, minute: profile.minute).displayText)
                    .font(.system(size: 56, weight: .light, design: .rounded))
                    .minimumScaleFactor(0.82)
                    .lineLimit(1)
                    .monospacedDigit()
                HStack(spacing: 8) {
                    Text(profile.label)
                        .font(.subheadline.weight(.medium))
                    Text(profile.mode.title)
                }
                .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("启用", isOn: $profile.isEnabled)
                .labelsHidden()
                .onChange(of: profile.isEnabled) { _, _ in
                    onChanged()
                }
        }
    }
}

private struct UpcomingDayGroup: Identifiable {
    var date: Date
    var instances: [ScheduledAlarmInstance]

    var id: String { DateKey(date: date).rawValue }
}

private struct UpcomingDayRow: View {
    var group: UpcomingDayGroup

    private let columns = [GridItem(.adaptive(minimum: 118), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(dayTitle)
                        .font(.headline)
                    Text(DateKey(date: group.date).rawValue)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(group.instances.count) 次")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(group.instances.prefix(8)) { instance in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(instance.time.displayText)
                            .font(.headline.monospacedDigit())
                        Text(shortLabel(for: instance))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(Color(uiColor: .tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }

            if group.instances.count > 8 {
                Text("还有 \(group.instances.count - 8) 次未显示")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private var dayTitle: String {
        let calendar = Calendar.chinaAlarm
        if calendar.isDateInToday(group.date) { return "今天" }
        if calendar.isDateInTomorrow(group.date) { return "明天" }
        return group.date.formatted(.dateTime.month().day().weekday(.wide).locale(Locale(identifier: "zh_CN")))
    }

    private func shortLabel(for instance: ScheduledAlarmInstance) -> String {
        instance.label
            .replacingOccurrences(of: "工作日闹铃 ", with: "")
            .replacingOccurrences(of: "起床组合 ", with: "")
    }
}

private struct FuturePreviewCalendarSheet: View {
    @Environment(\.dismiss) private var dismiss
    var monthGroups: [FuturePreviewMonthGroup]
    var exceptions: [CalendarException]
    var holidayCalendar: HolidayCalendar
    var companyRules: [CompanyCalendarRule]
    var onSelectDate: (Date) -> Void
    @State private var expandedWeekIDs: Set<String>

    init(
        monthGroups: [FuturePreviewMonthGroup],
        exceptions: [CalendarException],
        holidayCalendar: HolidayCalendar,
        companyRules: [CompanyCalendarRule],
        onSelectDate: @escaping (Date) -> Void
    ) {
        self.monthGroups = monthGroups
        self.exceptions = exceptions
        self.holidayCalendar = holidayCalendar
        self.companyRules = companyRules
        self.onSelectDate = onSelectDate
        _expandedWeekIDs = State(initialValue: Set(monthGroups.flatMap { month in
            month.weekGroups.filter(\.isDefaultExpanded).map(\.id)
        }))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    Text("预览会一直排到本年度结束；普通周默认收起，连续且跨周的休息日会合并成整块展示。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    ForEach(monthGroups) { group in
                        FuturePreviewMonthSection(
                            group: group,
                            exceptions: exceptions,
                            holidayCalendar: holidayCalendar,
                            companyRules: companyRules,
                            expandedWeekIDs: $expandedWeekIDs,
                            onSelectDate: onSelectDate
                        )
                    }

                    if monthGroups.isEmpty {
                        ContentUnavailableView("今年暂无更多预览", systemImage: "calendar", description: Text("本周与下周已经覆盖今年剩余日期。"))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .safeAreaPadding(.bottom, 28)
            .navigationTitle("未来预览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
        .interactiveDismissDisabled()
    }
}

private struct FuturePreviewMonthGroup: Identifiable {
    var monthStart: Date
    var weekGroups: [FuturePreviewWeekGroup]
    var restRanges: [FuturePreviewRestRangeGroup]

    private var calendar: Calendar { .chinaAlarm }

    var id: String { DateKey(date: monthStart).rawValue }

    var title: String {
        monthStart.formatted(.dateTime.year().month(.wide).locale(Locale(identifier: "zh_CN")))
    }

    var rangeText: String {
        let starts = weekGroups.compactMap(\.dates.first) + restRanges.map(\.range.start)
        let ends = weekGroups.compactMap(\.dates.last) + restRanges.map(\.range.end)
        guard let first = starts.min(), let last = ends.max() else { return "" }
        return "\(monthDayText(first))-\(monthDayText(last))"
    }

    private func monthDayText(_ date: Date) -> String {
        let components = calendar.dateComponents([.month, .day], from: date)
        return "\(components.month ?? 0)/\(components.day ?? 0)"
    }
}

private struct FuturePreviewWeekGroup: Identifiable {
    var monthStart: Date
    var weekStart: Date
    var dates: [Date]
    var instances: [ScheduledAlarmInstance]
    var markersByDate: [String: [CalendarDayMarker]]

    private var calendar: Calendar { .chinaAlarm }

    var id: String { "\(DateKey(date: monthStart).rawValue)-\(DateKey(date: weekStart).rawValue)" }

    var title: String {
        guard let first = dates.first, let last = dates.last else { return "" }
        return "\(monthDayText(first))-\(monthDayText(last))"
    }

    var markerKinds: [CalendarDayMarkerKind] {
        let presentKinds = Set(markersByDate.values.flatMap { $0.map(\.kind) })
        return CalendarDayMarkerKind.allCases.filter { presentKinds.contains($0) }
    }

    var markerSummaries: [FuturePreviewMarkerSummary] {
        let allMarkers = markersByDate.values.flatMap { $0 }
        return CalendarDayMarkerKind.allCases.compactMap { kind in
            let markers = allMarkers.filter { $0.kind == kind }
            guard !markers.isEmpty else { return nil }

            let titles = Array(Set(markers.map(\.title))).sorted()
            let title: String
            if (kind == .holidayRest || kind == .extraRest), titles.count == 1, let onlyTitle = titles.first {
                title = onlyTitle
            } else {
                title = kind.legendTitle
            }
            return FuturePreviewMarkerSummary(kind: kind, title: title)
        }
    }

    var isDefaultExpanded: Bool {
        isCurrentWeek || !markerKinds.isEmpty
    }

    var preferredCardHeight: CGFloat {
        let leadingBlanks = dates.first.map { (calendar.weekdayNumber(for: $0) + 5) % 7 } ?? 0
        let rowCount = Int(ceil(Double(leadingBlanks + dates.count) / 7.0))
        let gridHeight = 20 + CGFloat(rowCount) * AlarmCalendarMetrics.dayCellHeight + CGFloat(max(rowCount - 1, 0)) * 8
        return 18 + 22 + 14 + gridHeight + 12 + 42 + 18
    }

    private func monthDayText(_ date: Date) -> String {
        let components = calendar.dateComponents([.month, .day], from: date)
        return "\(components.month ?? 0)/\(components.day ?? 0)"
    }

    private var isCurrentWeek: Bool {
        let currentWeekStart = calendar
            .date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))
            .map(calendar.startOfDay(for:))
        return currentWeekStart.map { calendar.isDate($0, inSameDayAs: weekStart) } ?? false
    }
}

private struct FuturePreviewMarkerSummary: Identifiable, Hashable {
    var kind: CalendarDayMarkerKind
    var title: String

    var id: String { "\(kind.rawValue)-\(title)" }
}

private struct FuturePreviewRestRangeGroup: Identifiable {
    var range: CalendarExceptionRange
    var instances: [ScheduledAlarmInstance]

    var id: String { range.id }
}

private enum FuturePreviewMonthItem: Identifiable {
    case restRange(FuturePreviewRestRangeGroup)
    case week(FuturePreviewWeekGroup)

    var id: String {
        switch self {
        case .restRange(let range): "rest-\(range.id)"
        case .week(let week): "week-\(week.id)"
        }
    }

    var sortDate: Date {
        switch self {
        case .restRange(let group): group.range.restStart
        case .week(let week): week.dates.first ?? week.weekStart
        }
    }
}

private struct FuturePreviewMonthSection: View {
    var group: FuturePreviewMonthGroup
    var exceptions: [CalendarException]
    var holidayCalendar: HolidayCalendar
    var companyRules: [CompanyCalendarRule]
    @Binding var expandedWeekIDs: Set<String>
    var onSelectDate: (Date) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(group.title)
                    .font(.title3.weight(.semibold))
                Spacer()
                Text(group.rangeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 10) {
                ForEach(items) { item in
                    switch item {
                    case .restRange(let group):
                        FuturePreviewRestRangeSection(
                            group: group,
                            exceptions: exceptions,
                            holidayCalendar: holidayCalendar,
                            companyRules: companyRules,
                            onSelectDate: onSelectDate
                        )
                    case .week(let week):
                        FuturePreviewWeekSection(
                            week: week,
                            exceptions: exceptions,
                            holidayCalendar: holidayCalendar,
                            companyRules: companyRules,
                            isExpanded: expandedBinding(for: week),
                            onSelectDate: onSelectDate
                        )
                    }
                }
            }
        }
    }

    private var items: [FuturePreviewMonthItem] {
        (group.restRanges.map(FuturePreviewMonthItem.restRange) + group.weekGroups.map(FuturePreviewMonthItem.week))
            .sorted { $0.sortDate < $1.sortDate }
    }

    private func expandedBinding(for week: FuturePreviewWeekGroup) -> Binding<Bool> {
        Binding(
            get: { expandedWeekIDs.contains(week.id) },
            set: { isExpanded in
                if isExpanded {
                    expandedWeekIDs.insert(week.id)
                } else {
                    expandedWeekIDs.remove(week.id)
                }
            }
        )
    }
}

private struct FuturePreviewRestRangeSection: View {
    var group: FuturePreviewRestRangeGroup
    var exceptions: [CalendarException]
    var holidayCalendar: HolidayCalendar
    var companyRules: [CompanyCalendarRule]
    var onSelectDate: (Date) -> Void

    private var calendar: Calendar { .chinaAlarm }
    private var range: CalendarExceptionRange { group.range }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        CalendarMarkerBadge(kind: range.kind)
                        Text(range.title)
                            .font(.headline)
                    }
                    Text(restRangeSubtitle)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(range.restDateKeys.count) 天休息")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            AlarmCalendarOverviewCard(
                title: "闹铃概览",
                dates: rangeDates,
                instances: group.instances,
                exceptions: exceptions,
                holidayCalendar: holidayCalendar,
                companyRules: companyRules,
                minimumHeight: preferredCardHeight,
                alignsToWeekday: true,
                onSelectDate: onSelectDate
            )
        }
    }

    private var rangeDates: [Date] {
        range.dateKeys.compactMap { DateKey($0).date(calendar: calendar) }
    }

    private var restRangeSubtitle: String {
        let restText = "\(monthDayText(range.restStart))-\(monthDayText(range.restEnd))"
        let displayText = "\(monthDayText(range.start))-\(monthDayText(range.end))"
        return restText == displayText ? restText : "\(restText) · 展示 \(displayText)"
    }

    private var preferredCardHeight: CGFloat {
        let rowCount = max(1, Int(ceil(Double(rangeDates.count) / 7.0)))
        let gridHeight = 20 + CGFloat(rowCount) * AlarmCalendarMetrics.dayCellHeight + CGFloat(max(rowCount - 1, 0)) * 6
        return 18 + 22 + 12 + gridHeight + 18
    }

    private func monthDayText(_ date: Date) -> String {
        let components = calendar.dateComponents([.month, .day], from: date)
        return "\(components.month ?? 0)/\(components.day ?? 0)"
    }
}

private struct FuturePreviewWeekSection: View {
    var week: FuturePreviewWeekGroup
    var exceptions: [CalendarException]
    var holidayCalendar: HolidayCalendar
    var companyRules: [CompanyCalendarRule]
    @Binding var isExpanded: Bool
    var onSelectDate: (Date) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: isCollapsedRegularWeek ? 4 : 8) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: isCollapsedRegularWeek ? 2 : 4) {
                        Text(week.title)
                            .font(isCollapsedRegularWeek ? .subheadline.weight(.semibold) : .headline)
                        HStack(spacing: 6) {
                            if week.markerSummaries.isEmpty {
                                Text("常规周")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(week.markerSummaries) { summary in
                                    HStack(spacing: 3) {
                                        CalendarMarkerBadge(kind: summary.kind)
                                        Text(summary.title)
                                            .font(.caption2.weight(.medium))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    Spacer()
                    Text(isExpanded ? "收起" : "展开")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(.vertical, isCollapsedRegularWeek ? 7 : 12)
                .padding(.horizontal, 12)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)

            if isExpanded {
                AlarmCalendarOverviewCard(
                    title: "闹铃概览",
                    dates: week.dates,
                    instances: week.instances,
                    exceptions: exceptions,
                    holidayCalendar: holidayCalendar,
                    companyRules: companyRules,
                    minimumHeight: week.preferredCardHeight,
                    alignsToWeekday: true,
                    onSelectDate: onSelectDate
                )
            }
        }
    }

    private var isCollapsedRegularWeek: Bool {
        !isExpanded && week.markerKinds.isEmpty
    }
}

private enum AlarmCalendarMetrics {
    static let dayCellHeight: CGFloat = 66
}

private struct AlarmCalendarOverviewCard: View {
    var title: String
    var dates: [Date]
    var instances: [ScheduledAlarmInstance]
    var exceptions: [CalendarException]
    var holidayCalendar: HolidayCalendar
    var companyRules: [CompanyCalendarRule]
    var minimumHeight: CGFloat
    var alignsToWeekday = false
    var onSelectDate: (Date) -> Void
    var onFuturePreview: (() -> Void)? = nil

    private let calendar = Calendar.chinaAlarm
    private let weekdays = ["一", "二", "三", "四", "五", "六", "日"]
    private let palette: [Color] = [.orange, .indigo, .teal, .pink, .blue, .green, .purple, .mint]

    var body: some View {
        let instancesByDate = self.instancesByDate
        let exceptionKindsByDate = self.exceptionKindsByDate
        let dayMarkersByDate = self.dayMarkersByDate
        let colorMap = self.colorMap
        let legendItems = self.legendItems
        let markerLegendItems = self.markerLegendItems

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)
                Spacer()
                Text("\(dates.first.map(monthDayText) ?? "")-\(dates.last.map(monthDayText) ?? "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    ForEach(weekdays, id: \.self) { weekday in
                        Text(weekday)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }

                ForEach(Array(calendarRows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 6) {
                        ForEach(row.indices, id: \.self) { index in
                            if let date = row[index] {
                                let dateKey = calendar.startOfDayKey(for: date)
                                AlarmDayCell(
                                    date: date,
                                    instances: instancesByDate[dateKey] ?? [],
                                    exceptionKinds: exceptionKindsByDate[dateKey] ?? [],
                                    markers: dayMarkersByDate[dateKey] ?? [],
                                    colors: colorMap,
                                    isToday: calendar.isDateInToday(date),
                                    onTap: { onSelectDate(date) }
                                )
                            } else {
                                Color.clear
                                    .frame(maxWidth: .infinity)
                                    .frame(height: AlarmCalendarMetrics.dayCellHeight)
                            }
                        }
                    }
                }
            }

            if !markerLegendItems.isEmpty {
                MarkerLegend(items: markerLegendItems)
            }

            if !legendItems.isEmpty {
                FlowLegend(items: legendItems)
            }

            if let onFuturePreview {
                HStack {
                    Spacer()
                    Button("未来预览", action: onFuturePreview)
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                        .tint(.orange)
                }
            }
        }
        .padding(18)
        .frame(minHeight: onFuturePreview == nil ? 0 : minimumHeight, alignment: .top)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var instancesByDate: [String: [ScheduledAlarmInstance]] {
        Dictionary(grouping: instances) { calendar.startOfDayKey(for: $0.fireDate) }
    }

    private var exceptionKindsByDate: [String: Set<CalendarExceptionKind>] {
        Dictionary(grouping: exceptions, by: \.dateKey).mapValues { Set($0.map(\.kind)) }
    }

    private var dayMarkersByDate: [String: [CalendarDayMarker]] {
        let resolver = WorkdayResolver(calendar: calendar)
        return Dictionary(uniqueKeysWithValues: dates.map { date in
            let key = calendar.startOfDayKey(for: date)
            let markers = resolver.dayMarkers(
                for: date,
                holidayCalendar: holidayCalendar,
                companyRules: companyRules,
                exceptions: exceptions
            )
            return (key, markers)
        })
    }

    private var colorMap: [ClockTime: Color] {
        let times = Array(Set(instances.map(\.time))).sorted()
        return Dictionary(uniqueKeysWithValues: times.enumerated().map { index, time in
            (time, palette[index % palette.count])
        })
    }

    private var markerLegendItems: [CalendarDayMarkerKind] {
        let presentKinds = Set(dayMarkersByDate.values.flatMap { $0.map(\.kind) })
        return CalendarDayMarkerKind.allCases.filter { presentKinds.contains($0) }
    }

    private var legendItems: [AlarmLegendItem] {
        colorMap.keys.sorted().map { time in
            AlarmLegendItem(time: time, color: colorMap[time] ?? .orange)
        }
    }

    private var leadingBlankCount: Int {
        guard alignsToWeekday, let firstDate = dates.first else { return 0 }
        return (calendar.weekdayNumber(for: firstDate) + 5) % 7
    }

    private var calendarRows: [[Date?]] {
        var cells = Array<Date?>(repeating: nil, count: leadingBlankCount) + dates.map { Optional($0) }
        while cells.count % 7 != 0 {
            cells.append(nil)
        }

        return stride(from: 0, to: cells.count, by: 7).map { start in
            Array(cells[start..<min(start + 7, cells.count)])
        }
    }

    private func monthDayText(_ date: Date) -> String {
        let components = calendar.dateComponents([.month, .day], from: date)
        return "\(components.month ?? 0)/\(components.day ?? 0)"
    }
}

private struct AlarmDayCell: View {
    var date: Date
    var instances: [ScheduledAlarmInstance]
    var exceptionKinds: Set<CalendarExceptionKind>
    var markers: [CalendarDayMarker]
    var colors: [ClockTime: Color]
    var isToday: Bool
    var onTap: () -> Void

    private var calendar: Calendar { .chinaAlarm }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                ZStack(alignment: .bottom) {
                    Text("\(calendar.component(.day, from: date))")
                        .font(.caption.weight(isToday ? .bold : .semibold))
                        .monospacedDigit()
                        .frame(width: 34, height: 34)
                        .background(backgroundColor)
                        .foregroundStyle(textColor)
                        .overlay {
                            Circle()
                                .strokeBorder(strokeColor, lineWidth: isToday || isModified ? 2 : 1)
                        }
                        .clipShape(Circle())

                    HStack(spacing: 2) {
                        ForEach(markers.prefix(2)) { marker in
                            CalendarMarkerBadge(kind: marker.kind)
                        }
                    }
                    .offset(y: 7)

                    if isToday {
                        VStack {
                            HStack {
                                Spacer()
                                Text("今")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 14, height: 14)
                                    .background(Color.orange)
                                    .clipShape(Circle())
                                    .offset(x: 4, y: -4)
                            }
                            Spacer()
                        }
                    }
                }
                .frame(width: 40, height: 38)

                Text(markerSubtitle)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(markerColor ?? .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .frame(maxWidth: .infinity)
                    .frame(height: 10)

                HStack(spacing: 2) {
                    if !uniqueTimes.isEmpty {
                        ForEach(uniqueTimes.prefix(4), id: \.self) { time in
                            Circle()
                                .fill(colors[time] ?? .orange)
                                .frame(width: 5, height: 5)
                        }
                    }
                }
                .frame(height: 6)
            }
            .frame(maxWidth: .infinity, minHeight: AlarmCalendarMetrics.dayCellHeight)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
    }

    private var uniqueTimes: [ClockTime] {
        Array(Set(instances.map(\.time))).sorted()
    }

    private var primaryColor: Color? {
        uniqueTimes.first.flatMap { colors[$0] }
    }

    private var isModified: Bool {
        !exceptionKinds.isEmpty
    }

    private var backgroundColor: Color {
        if let markerColor {
            return markerColor.opacity(0.22)
        }
        if isModified {
            return modifiedColor.opacity(0.22)
        }
        if isToday {
            return Color.orange.opacity(0.18)
        }
        guard let primaryColor else {
            return Color(uiColor: .tertiarySystemFill)
        }
        return primaryColor.opacity(0.18)
    }

    private var strokeColor: Color {
        if let markerColor {
            return markerColor
        }
        if isModified {
            return modifiedColor
        }
        if isToday {
            return .orange
        }
        return primaryColor ?? Color.clear
    }

    private var markerColor: Color? {
        markers.first.map { Color.calendarMarker($0.kind) }
    }

    private var markerSubtitle: String {
        guard let marker = markers.first(where: { $0.kind == .holidayRest || $0.kind == .extraRest }) else {
            return ""
        }
        return marker.title
    }

    private var modifiedColor: Color {
        if exceptionKinds.contains(.restDayOverride) { return .green }
        if exceptionKinds.contains(.workdayOverride) { return .blue }
        if exceptionKinds.contains(.skipAlarm) { return .red }
        return .purple
    }

    private var textColor: Color {
        primaryColor == nil ? .secondary : .primary
    }

    private var accessibilityText: String {
        let key = DateKey(date: date).rawValue
        let modified = isModified ? "，已手动修改" : ""
        let markerText = markers.isEmpty ? "" : "，\(markers.map(\.title).joined(separator: "、"))"
        guard !uniqueTimes.isEmpty else { return "\(key)\(markerText)，无闹铃\(modified)" }
        return "\(key)\(markerText)，闹铃 \(uniqueTimes.map(\.displayText).joined(separator: "、"))\(modified)"
    }
}

private struct CalendarMarkerBadge: View {
    var kind: CalendarDayMarkerKind

    var body: some View {
        Text(kind.shortTitle)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 13, height: 12)
            .background(Color.calendarMarker(kind))
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
    }
}

private struct SelectedCalendarDate: Identifiable {
    var date: Date
    var id: String { DateKey(date: date).rawValue }
}

private enum CalendarDateActionKind {
    case workday
    case restDay
    case skipAlarms
    case extraAlarm
    case clear
}

private struct CalendarDateAction {
    var date: Date
    var kind: CalendarDateActionKind
    var hour: Int = 8
    var minute: Int = 0
    var soundIdentifier: String = SoundLibrary.defaultSoundIdentifier
}

private struct CalendarDateActionSheet: View {
    @Environment(\.dismiss) private var dismiss
    var date: Date
    var profiles: [AlarmProfile]
    var exceptions: [CalendarException]
    var onApply: (CalendarDateAction) -> Void
    var onChanged: () -> Void

    @Query(sort: \SoundAsset.createdAt) private var sounds: [SoundAsset]
    @State private var hour = 8
    @State private var minute = 0
    @State private var temporarySoundIdentifier = SoundLibrary.defaultSoundIdentifier
    @StateObject private var previewPlayer = SoundPreviewPlayer()

    private var dateKey: String { DateKey(date: date).rawValue }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.title.weight(.semibold))
                        .padding(.horizontal, 4)
                    if !currentExceptionTitles.isEmpty {
                        Text(currentExceptionTitles.joined(separator: "、"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                    }

                    CalendarActionSection(title: "当天安排") {
                        CalendarOptionButton(title: "当天休息", tint: .orange) {
                            onApply(CalendarDateAction(date: date, kind: .restDay))
                        }
                        Divider()
                        CalendarOptionButton(title: "当天上班", tint: .orange) {
                            onApply(CalendarDateAction(date: date, kind: .workday))
                        }
                        Divider()
                        CalendarOptionButton(title: "跳过当天闹铃", tint: .red) {
                            onApply(CalendarDateAction(date: date, kind: .skipAlarms))
                        }
                    }

                    CalendarActionSection(title: "需要时间的操作") {
                        WheelTimePicker(hour: $hour, minute: $minute, fontSize: 22, pickerHeight: 140)
                            .padding(.vertical, 2)
                        Divider()
                        TimeActionButton(
                            title: "新增临时闹铃",
                            time: ClockTime(hour: hour, minute: minute),
                            systemImage: "plus.circle.fill"
                        ) {
                            onApply(CalendarDateAction(date: date, kind: .extraAlarm, hour: hour, minute: minute, soundIdentifier: temporarySoundIdentifier))
                        }
                    }

                    CalendarActionSection(title: "声音") {
                        Menu {
                            Button("AlarmKit 系统默认") {
                                temporarySoundIdentifier = SoundLibrary.alarmKitDefaultIdentifier
                            }
                            ForEach(sounds) { sound in
                                Button(sound.name) {
                                    temporarySoundIdentifier = sound.filename
                                }
                            }
                        } label: {
                            HStack {
                                Text("铃声")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(soundName(for: temporarySoundIdentifier))
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(.orange)
                            .frame(minHeight: 52)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider()
                        Button("试听当前铃声") {
                            previewPlayer.preview(identifier: temporarySoundIdentifier)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: 52)
                        if let status = previewPlayer.status {
                            Divider()
                            Text(status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                        }
                    }

                    if !temporaryExceptions.isEmpty {
                        CalendarActionSection(title: "当天临时闹铃") {
                            ForEach(temporaryExceptions) { exception in
                                NavigationLink {
                                    TemporaryAlarmExceptionEditor(exception: exception, onChanged: onChanged)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(exception.note.isEmpty ? "临时闹铃" : exception.note)
                                                .font(.body.weight(.medium))
                                            Text(soundName(for: exception.soundIdentifier ?? SoundLibrary.defaultSoundIdentifier))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Text(ClockTime(hour: exception.hour, minute: exception.minute).displayText)
                                            .font(.body.monospacedDigit().weight(.semibold))
                                    }
                                    .frame(minHeight: 50)
                                }
                            }
                        }
                    }

                    if !currentExceptions.isEmpty {
                        Button(role: .destructive) {
                            onApply(CalendarDateAction(date: date, kind: .clear))
                        } label: {
                            Text("清除当天所有修改")
                                .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("调整日期")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var currentExceptions: [CalendarException] {
        exceptions.filter { $0.dateKey == dateKey }
    }

    private var temporaryExceptions: [CalendarException] {
        currentExceptions
            .filter { $0.kind == .extraAlarm }
            .sorted { lhs, rhs in
                ClockTime(hour: lhs.hour, minute: lhs.minute) < ClockTime(hour: rhs.hour, minute: rhs.minute)
            }
    }

    private var currentExceptionTitles: [String] {
        Array(Set(currentExceptions.map { $0.kind.title })).sorted()
    }

    private func soundName(for identifier: String) -> String {
        if identifier == SoundLibrary.alarmKitDefaultIdentifier {
            return "AlarmKit 系统默认"
        }
        return sounds.first { $0.filename == identifier }?.name ?? "未知铃声"
    }
}

private struct TemporaryAlarmExceptionEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var exception: CalendarException
    var onChanged: () -> Void

    @Query(sort: \SoundAsset.createdAt) private var sounds: [SoundAsset]
    @StateObject private var previewPlayer = SoundPreviewPlayer()

    var body: some View {
        Form {
            Section {
                WheelTimePicker(hour: $exception.hour, minute: $exception.minute)
            }

            Section("临时闹铃") {
                HStack {
                    Text("闹铃标题")
                    TextField("临时闹铃", text: $exception.note)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                }
                Picker("铃声", selection: soundSelection) {
                    Text("AlarmKit 系统默认").tag(SoundLibrary.alarmKitDefaultIdentifier)
                    ForEach(sounds) { sound in
                        Text(sound.name).tag(sound.filename)
                    }
                }
                Button("试听当前铃声") {
                    previewPlayer.preview(identifier: soundSelection.wrappedValue)
                }
                if let status = previewPlayer.status {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("编辑临时闹铃")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("保存") {
                    onChanged()
                    dismiss()
                }
                .fontWeight(.semibold)
            }
        }
    }

    private var soundSelection: Binding<String> {
        Binding(
            get: { exception.soundIdentifier ?? SoundLibrary.defaultSoundIdentifier },
            set: { exception.soundIdentifier = $0 }
        )
    }
}

private struct CalendarActionSection<Content: View>: View {
    var title: String
    var content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

private struct CalendarOptionButton: View {
    var title: String
    var tint: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.body.weight(.medium))
                Spacer()
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .tint(tint)
    }
}

private struct TimeActionButton: View {
    var title: String
    var time: ClockTime
    var systemImage: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.body)
                Text(title)
                    .font(.body.weight(.medium))
                Spacer(minLength: 12)
                Text(time.displayText)
                    .font(.body.monospacedDigit().weight(.semibold))
            }
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
    }
}

private struct AlarmLegendItem: Identifiable {
    var id: String { time.displayText }
    var time: ClockTime
    var color: Color
}

private struct FlowLegend: View {
    var items: [AlarmLegendItem]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(items) { item in
                    HStack(spacing: 5) {
                        Circle()
                            .fill(item.color)
                            .frame(width: 7, height: 7)
                        Text(item.time.displayText)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }
}

private struct MarkerLegend: View {
    var items: [CalendarDayMarkerKind]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.rawValue) { item in
                    HStack(spacing: 4) {
                        CalendarMarkerBadge(kind: item)
                        Text(item.legendTitle)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }
}

private extension Color {
    static func calendarMarker(_ kind: CalendarDayMarkerKind) -> Color {
        switch kind {
        case .holidayRest: .pink
        case .makeupWorkday: .blue
        case .companyWorkday: .orange
        case .extraRest: .green
        }
    }
}
