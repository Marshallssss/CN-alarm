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
    private let futurePreviewDayCount = 92

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
                        minimumHeight: 250,
                        onSelectDate: { selectedDate = $0 },
                        onFuturePreview: {
                            futurePreviewSnapshot = FuturePreviewSnapshot(monthGroups: makeFuturePreviewGroups())
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
                    exceptions: exceptions
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
        Calendar.chinaAlarm.date(byAdding: .day, value: 14, to: calendarOverviewStartDate) ?? calendarOverviewStartDate
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

    private func makeFuturePreviewGroups() -> [FuturePreviewMonthGroup] {
        let calendar = Calendar.chinaAlarm
        let dates = futurePreviewDates
        let instances = futurePreviewInstances
        let datesByMonth = Dictionary(grouping: dates) { date in
            let components = calendar.dateComponents([.year, .month], from: date)
            return calendar.date(from: components).map(calendar.startOfDay(for:)) ?? calendar.startOfDay(for: date)
        }
        let instancesByDate = Dictionary(grouping: instances) { calendar.startOfDayKey(for: $0.fireDate) }

        return datesByMonth.map { monthStart, monthDates in
            let sortedDates = monthDates.sorted()
            let monthInstances = sortedDates.flatMap { date in
                instancesByDate[calendar.startOfDayKey(for: date)] ?? []
            }
            return FuturePreviewMonthGroup(
                monthStart: monthStart,
                dates: sortedDates,
                instances: monthInstances
            )
        }
        .sorted { $0.monthStart < $1.monthStart }
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
    var onSelectDate: (Date) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    Text("近 3 个月会按月份分开显示，点击任意日期可继续调整当天闹铃。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    ForEach(monthGroups) { group in
                        AlarmCalendarOverviewCard(
                            title: group.title,
                            dates: group.dates,
                            instances: group.instances,
                            exceptions: exceptions,
                            minimumHeight: group.preferredCardHeight,
                            alignsToWeekday: true,
                            onSelectDate: onSelectDate
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
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
    }
}

private struct FuturePreviewMonthGroup: Identifiable {
    var monthStart: Date
    var dates: [Date]
    var instances: [ScheduledAlarmInstance]

    private var calendar: Calendar { .chinaAlarm }

    var id: String { DateKey(date: monthStart).rawValue }

    var title: String {
        monthStart.formatted(.dateTime.year().month(.wide).locale(Locale(identifier: "zh_CN")))
    }

    var preferredCardHeight: CGFloat {
        let leadingBlanks = dates.first.map { (calendar.weekdayNumber(for: $0) + 5) % 7 } ?? 0
        let rowCount = Int(ceil(Double(leadingBlanks + dates.count) / 7.0))
        let gridHeight = 20 + CGFloat(rowCount) * 52 + CGFloat(max(rowCount - 1, 0)) * 8
        return 18 + 22 + 14 + gridHeight + 12 + 24 + 18
    }
}

private struct AlarmCalendarOverviewCard: View {
    var title: String
    var dates: [Date]
    var instances: [ScheduledAlarmInstance]
    var exceptions: [CalendarException]
    var minimumHeight: CGFloat
    var alignsToWeekday = false
    var onSelectDate: (Date) -> Void
    var onFuturePreview: (() -> Void)? = nil

    private let calendar = Calendar.chinaAlarm
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    private let weekdays = ["一", "二", "三", "四", "五", "六", "日"]
    private let palette: [Color] = [.orange, .indigo, .teal, .pink, .blue, .green, .purple, .mint]

    var body: some View {
        let instancesByDate = self.instancesByDate
        let exceptionKindsByDate = self.exceptionKindsByDate
        let colorMap = self.colorMap
        let legendItems = self.legendItems

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)
                Spacer()
                Text("\(dates.first.map(monthDayText) ?? "")-\(dates.last.map(monthDayText) ?? "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(weekdays, id: \.self) { weekday in
                    Text(weekday)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(0..<leadingBlankCount, id: \.self) { _ in
                    Color.clear
                        .frame(maxWidth: .infinity, minHeight: 52)
                }

                ForEach(dates, id: \.self) { date in
                    AlarmDayCell(
                        date: date,
                        instances: instancesByDate[calendar.startOfDayKey(for: date)] ?? [],
                        exceptionKinds: exceptionKindsByDate[calendar.startOfDayKey(for: date)] ?? [],
                        colors: colorMap,
                        isToday: calendar.isDateInToday(date),
                        onTap: { onSelectDate(date) }
                    )
                }
            }

            if !legendItems.isEmpty {
                FlowLegend(items: legendItems)
                    .frame(height: 22)
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
        .frame(minHeight: minimumHeight, alignment: .top)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var instancesByDate: [String: [ScheduledAlarmInstance]] {
        Dictionary(grouping: instances) { calendar.startOfDayKey(for: $0.fireDate) }
    }

    private var exceptionKindsByDate: [String: Set<CalendarExceptionKind>] {
        Dictionary(grouping: exceptions, by: \.dateKey).mapValues { Set($0.map(\.kind)) }
    }

    private var colorMap: [ClockTime: Color] {
        let times = Array(Set(instances.map(\.time))).sorted()
        return Dictionary(uniqueKeysWithValues: times.enumerated().map { index, time in
            (time, palette[index % palette.count])
        })
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

    private func monthDayText(_ date: Date) -> String {
        let components = calendar.dateComponents([.month, .day], from: date)
        return "\(components.month ?? 0)/\(components.day ?? 0)"
    }
}

private struct AlarmDayCell: View {
    var date: Date
    var instances: [ScheduledAlarmInstance]
    var exceptionKinds: Set<CalendarExceptionKind>
    var colors: [ClockTime: Color]
    var isToday: Bool
    var onTap: () -> Void

    private var calendar: Calendar { .chinaAlarm }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 5) {
                ZStack(alignment: .topTrailing) {
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

                    if isToday {
                        Text("今")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 14, height: 14)
                            .background(Color.orange)
                            .clipShape(Circle())
                            .offset(x: 4, y: -4)
                    }
                }
                .frame(width: 40, height: 38)

                HStack(spacing: 2) {
                    if uniqueTimes.isEmpty {
                        Circle()
                            .fill(Color.gray.opacity(0.45))
                            .frame(width: 5, height: 5)
                    } else {
                        ForEach(uniqueTimes.prefix(4), id: \.self) { time in
                            Circle()
                                .fill(colors[time] ?? .orange)
                                .frame(width: 5, height: 5)
                        }
                    }
                }
                .frame(height: 6)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
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
        if isModified {
            return modifiedColor
        }
        if isToday {
            return .orange
        }
        return primaryColor ?? Color.clear
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
        guard !uniqueTimes.isEmpty else { return "\(key)，无闹铃\(modified)" }
        return "\(key)，闹铃 \(uniqueTimes.map(\.displayText).joined(separator: "、"))\(modified)"
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
        }
    }
}
