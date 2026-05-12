import SwiftData
import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var holidayDatasets: [HolidayDataset]
    @Query private var sounds: [SoundAsset]
    @Query private var profiles: [AlarmProfile]
    @Query private var templates: [AlarmComboTemplate]
    @Query private var exceptions: [CalendarException]
    @Query private var companyRules: [CompanyCalendarRule]
    @AppStorage("holidaySourceURL") private var sourceURL = HolidayCalendarSource.defaultURL.absoluteString
    @State private var refreshStatus = "未刷新"
    @State private var importingSound = false
    @State private var soundImportStatus: String?
    @State private var alarmDiagnosticStatus = "未检查"
    @State private var editingLeaveType: LeaveType?
    @StateObject private var previewPlayer = SoundPreviewPlayer()

    private let soundManager = SoundAssetManager()
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    MainPageTitle("设置")
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 2, trailing: 0))
                        .listRowBackground(Color.clear)
                }

                Section("中国调休日历") {
                    TextField("日历 JSON URL", text: $sourceURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("立即刷新") {
                        Task { await refreshHolidayCalendar() }
                    }
                    Text(refreshStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("中国特色工作制") {
                    Toggle("月末周六上班", isOn: companyRuleEnabledBinding(kind: .lastSaturdayOfMonth, name: "月末周六"))
                    Toggle("大小周周六上班", isOn: companyRuleEnabledBinding(kind: .alternateSaturday, name: "大小周"))
                    if isCompanyRuleEnabled(.alternateSaturday) {
                        DatePicker("大小周起始周六", selection: alternateSaturdayAnchorBinding, displayedComponents: .date)
                    }
                    Toggle("单休（周六上班）", isOn: companyRuleEnabledBinding(kind: .singleDayOff, name: "单休"))
                    Text("开启后会参与智能工作日识别；手动日期例外和国家调休仍保持更高优先级。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("休假") {
                    ForEach(LeaveType.defaults) { leaveType in
                        Button {
                            editingLeaveType = leaveType
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(leaveType.title)
                                        .foregroundStyle(.primary)
                                    Text(leaveSubtitle(for: leaveType))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "calendar.badge.plus")
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    Text("适合寒假、暑假、年假、婚假、产假/陪产假、病假、事假、调休假等连续多日休息。进入后在日历上点选，或按住日期滑动经过来多选。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Apple Watch") {
                    Label("AlarmKit 闹铃由系统转发到配对手表", systemImage: "applewatch")
                    Label("关键日期提醒依赖 iPhone 通知镜像", systemImage: "bell.badge")
                    Text("震动不自定义，使用系统闹铃/睡眠类默认触感。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("闹铃诊断") {
                    Text(alarmDiagnosticStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("刷新 AlarmKit 状态") {
                        alarmDiagnosticStatus = AlarmKitScheduler().diagnosticStatus()
                    }
                    Button("60 秒后测试系统闹铃") {
                        Task { await scheduleAlarmKitTest() }
                    }
                    Button("60 秒后测试本地通知兜底") {
                        Task { await scheduleFallbackNotificationTest() }
                    }
                    Text("如果系统闹铃测试不响，本地通知测试响，问题就在 AlarmKit 授权/系统注册链路。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("铃声") {
                    Button("修复内置铃声") {
                        do {
                            try soundManager.installBundledSoundsIfNeeded()
                            soundImportStatus = "内置铃声已就绪"
                        } catch {
                            soundImportStatus = "修复失败：\(error.localizedDescription)"
                        }
                    }
                    Button("导入铃声") {
                        importingSound = true
                    }
                    Text("AlarmKit 只公开一个系统 default 声音，不公开 iOS 时钟 App 的完整铃声库；这里另外支持 App 内置铃声和导入的 wav/caf/aiff。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let soundImportStatus {
                        Text(soundImportStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(sounds) { sound in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(sound.name)
                                Text(sound.kind.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("试听") {
                                previewPlayer.preview(identifier: sound.filename)
                            }
                            .buttonStyle(.borderless)
                            if sound.kind == .imported {
                                Button(role: .destructive) {
                                    deleteImportedSound(sound)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("删除\(sound.name)")
                            }
                        }
                    }
                    if let status = previewPlayer.status {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .contentMargins(.top, 0, for: .scrollContent)
            .fileImporter(
                isPresented: $importingSound,
                allowedContentTypes: soundManager.supportedTypes,
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else {
                        soundImportStatus = "未选择音频"
                        return
                    }
                    do {
                        let sound = try soundManager.importSound(from: url)
                        modelContext.insert(sound)
                        soundImportStatus = "已导入：\(sound.name)"
                    } catch {
                        soundImportStatus = "导入失败：\(error.localizedDescription)"
                    }
                case .failure(let error):
                    soundImportStatus = "导入失败：\(error.localizedDescription)"
                }
            }
            .sheet(item: $editingLeaveType) { leaveType in
                LeaveCalendarSelectionSheet(
                    leaveType: leaveType,
                    initialSelectedKeys: leaveDateKeys(for: leaveType)
                ) { selectedKeys in
                    applyLeaveSelection(leaveType, selectedDateKeys: selectedKeys)
                    editingLeaveType = nil
                } onCancel: {
                    editingLeaveType = nil
                }
            }
        }
    }

    private func refreshHolidayCalendar() async {
        guard let url = URL(string: sourceURL) else {
            refreshStatus = "URL 无效"
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            _ = try HolidayCalendarParser().parse(data: data)
            let dataset = holidayDatasets.last ?? HolidayDataset(sourceURL: sourceURL)
            dataset.sourceURL = sourceURL
            dataset.fetchedAt = Date()
            dataset.rawJSON = String(data: data, encoding: .utf8) ?? ""
            if holidayDatasets.isEmpty {
                modelContext.insert(dataset)
            }
            refreshStatus = "已刷新 \(dataset.fetchedAt.formatted(date: .abbreviated, time: .shortened))"
        } catch {
            refreshStatus = "刷新失败：\(error.localizedDescription)"
        }
    }

    private func companyRuleEnabledBinding(kind: CompanyRuleKind, name: String) -> Binding<Bool> {
        Binding(
            get: { isCompanyRuleEnabled(kind) },
            set: { enabled in
                let rule = ensureCompanyRule(kind: kind, name: name)
                rule.isEnabled = enabled
                saveSettingsAndResync()
            }
        )
    }

    private func isCompanyRuleEnabled(_ kind: CompanyRuleKind) -> Bool {
        companyRules.first { $0.kind == kind }?.isEnabled == true
    }

    private var alternateSaturdayAnchorBinding: Binding<Date> {
        Binding(
            get: { companyRules.first { $0.kind == .alternateSaturday }?.anchorDate ?? defaultAlternateSaturdayAnchor() },
            set: { date in
                let rule = ensureCompanyRule(kind: .alternateSaturday, name: "大小周")
                rule.anchorDate = Calendar.chinaAlarm.startOfDay(for: date)
                saveSettingsAndResync()
            }
        )
    }

    private func ensureCompanyRule(kind: CompanyRuleKind, name: String) -> CompanyCalendarRule {
        if let existing = companyRules.first(where: { $0.kind == kind }) {
            return existing
        }
        let rule = CompanyCalendarRule(
            name: name,
            kind: kind,
            anchorDate: kind == .alternateSaturday ? defaultAlternateSaturdayAnchor() : Date()
        )
        modelContext.insert(rule)
        return rule
    }

    private func defaultAlternateSaturdayAnchor() -> Date {
        let calendar = Calendar.chinaAlarm
        var candidate = calendar.startOfDay(for: Date())
        while calendar.weekdayNumber(for: candidate) != 7 {
            guard let next = calendar.date(byAdding: .day, value: 1, to: candidate) else { break }
            candidate = next
        }
        return candidate
    }

    private func leaveSubtitle(for leaveType: LeaveType) -> String {
        let ranges = CalendarExceptionRangeGrouper(calendar: .chinaAlarm)
            .leaveRanges(from: exceptions.filter { leaveType.matches(note: $0.note) })
        guard !ranges.isEmpty else { return "未设置" }
        if ranges.count == 1, let range = ranges.first {
            return "\(compactDate(range.start)) - \(compactDate(range.end))，\(range.dateKeys.count) 天"
        }
        let totalDays = ranges.reduce(0) { $0 + $1.dateKeys.count }
        return "\(ranges.count) 段，共 \(totalDays) 天"
    }

    private func leaveDateKeys(for leaveType: LeaveType) -> Set<String> {
        Set(exceptions.filter { $0.kind == .restDayOverride && leaveType.matches(note: $0.note) }.map(\.dateKey))
    }

    private func applyLeaveSelection(_ leaveType: LeaveType, selectedDateKeys: Set<String>) {
        for exception in exceptions where exception.kind == .restDayOverride && leaveType.matches(note: exception.note) {
            modelContext.delete(exception)
        }
        for key in selectedDateKeys.sorted() {
            modelContext.insert(CalendarException(dateKey: key, kind: .restDayOverride, note: leaveType.note))
        }
        saveSettingsAndResync()
    }

    private func compactDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.twoDigits).day(.twoDigits).locale(Locale(identifier: "zh_CN")))
    }

    private func saveSettingsAndResync() {
        do {
            try modelContext.save()
            Task { await resyncAfterSettingsChange() }
        } catch {
            refreshStatus = "保存失败：\(error.localizedDescription)"
        }
    }

    private func resyncAfterSettingsChange() async {
        do {
            _ = try await AlarmScheduleSyncService().sync(
                profiles: profiles,
                templates: templates,
                holidayDatasets: holidayDatasets,
                companyRules: companyRules,
                exceptions: exceptions
            )
        } catch {
            refreshStatus = "设置已保存，但闹铃同步失败：\(error.localizedDescription)"
        }
    }

    private func scheduleAlarmKitTest() async {
        do {
            let fireDate = try await AlarmKitScheduler().scheduleTestAlarm(after: 60)
            alarmDiagnosticStatus = "已注册系统测试闹铃：\(fireDate.formatted(date: .omitted, time: .standard))"
        } catch {
            alarmDiagnosticStatus = "系统测试闹铃失败：\(error.localizedDescription)"
        }
    }

    private func scheduleFallbackNotificationTest() async {
        do {
            try SoundAssetManager().installBundledSoundsIfNeeded()
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            guard granted else {
                alarmDiagnosticStatus = "本地通知权限未开启"
                return
            }
            let content = UNMutableNotificationContent()
            content.title = "测试闹铃"
            content.body = "这是本地通知兜底测试。"
            content.sound = UNNotificationSound(named: UNNotificationSoundName(SoundLibrary.defaultSoundIdentifier))
            let request = UNNotificationRequest(
                identifier: "cnalarm.fallback.test.\(UUID().uuidString)",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false)
            )
            try await UNUserNotificationCenter.current().add(request)
            alarmDiagnosticStatus = "已注册本地通知测试：60 秒后"
        } catch {
            alarmDiagnosticStatus = "本地通知测试失败：\(error.localizedDescription)"
        }
    }

    private func deleteImportedSound(_ sound: SoundAsset) {
        do {
            try soundManager.deleteImportedSound(sound)
            replaceDeletedSoundReferences(sound.filename)
            modelContext.delete(sound)
            try modelContext.save()
            soundImportStatus = "已删除：\(sound.name)"
            Task { await resyncAfterSoundDeletion() }
        } catch {
            soundImportStatus = "删除失败：\(error.localizedDescription)"
        }
    }

    private func replaceDeletedSoundReferences(_ filename: String) {
        for profile in profiles where profile.soundIdentifier == filename {
            profile.soundIdentifier = SoundLibrary.defaultSoundIdentifier
        }
        for template in templates where template.defaultSoundIdentifier == filename {
            template.defaultSoundIdentifier = SoundLibrary.defaultSoundIdentifier
        }
        for exception in exceptions where exception.soundIdentifier == filename {
            exception.soundIdentifier = SoundLibrary.defaultSoundIdentifier
        }
    }

    private func resyncAfterSoundDeletion() async {
        do {
            _ = try await AlarmScheduleSyncService().sync(
                profiles: profiles,
                templates: templates,
                holidayDatasets: holidayDatasets,
                companyRules: companyRules,
                exceptions: exceptions
            )
        } catch {
            soundImportStatus = "已删除铃声，但系统闹铃同步失败：\(error.localizedDescription)"
        }
    }
}

private struct LeaveType: Identifiable, Hashable {
    var id: String { note }
    var title: String
    var note: String
    var legacyNotes: [String] = []

    static let defaults: [LeaveType] = [
        LeaveType(title: "寒假", note: "休假：寒假", legacyNotes: ["设置生成：寒假休息", "设置生成：寒暑假休息"]),
        LeaveType(title: "暑假", note: "休假：暑假", legacyNotes: ["设置生成：暑假休息", "设置生成：寒暑假休息"]),
        LeaveType(title: "年假", note: "休假：年假"),
        LeaveType(title: "婚假", note: "休假：婚假"),
        LeaveType(title: "产假/陪产假", note: "休假：产假/陪产假"),
        LeaveType(title: "病假", note: "休假：病假"),
        LeaveType(title: "事假", note: "休假：事假"),
        LeaveType(title: "调休假", note: "休假：调休假")
    ]

    func matches(note otherNote: String) -> Bool {
        otherNote == note || legacyNotes.contains(otherNote)
    }
}

private struct LeaveCalendarSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    var leaveType: LeaveType
    var initialSelectedKeys: Set<String>
    var onSave: (Set<String>) -> Void
    var onCancel: () -> Void

    @State private var visibleMonth: Date
    @State private var selectedKeys: Set<String>
    @State private var dragTouchedKeys: Set<String> = []
    @State private var isDraggingSelection = false

    private let calendar = Calendar.chinaAlarm
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)
    private let weekdays = ["一", "二", "三", "四", "五", "六", "日"]
    private let gridSpacing: CGFloat = 8
    private let rowSpacing: CGFloat = 10
    private let dateCellHeight: CGFloat = 44

    init(
        leaveType: LeaveType,
        initialSelectedKeys: Set<String>,
        onSave: @escaping (Set<String>) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.leaveType = leaveType
        self.initialSelectedKeys = initialSelectedKeys
        self.onSave = onSave
        self.onCancel = onCancel
        if let firstKey = initialSelectedKeys.sorted().first, let firstDate = DateKey(firstKey).date() {
            _visibleMonth = State(initialValue: Calendar.chinaAlarm.date(from: Calendar.chinaAlarm.dateComponents([.year, .month], from: firstDate)) ?? firstDate)
        } else {
            let now = Date()
            _visibleMonth = State(initialValue: Calendar.chinaAlarm.date(from: Calendar.chinaAlarm.dateComponents([.year, .month], from: now)) ?? now)
        }
        _selectedKeys = State(initialValue: initialSelectedKeys)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack {
                    Button {
                        shiftMonth(-1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: 42, height: 42)
                    }

                    Spacer()

                    Text(visibleMonth.formatted(.dateTime.year().month(.wide).locale(Locale(identifier: "zh_CN"))))
                        .font(.title3.weight(.semibold))

                    Spacer()

                    Button {
                        shiftMonth(1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .frame(width: 42, height: 42)
                    }
                }
                .buttonStyle(.bordered)

                HStack(spacing: gridSpacing) {
                    ForEach(weekdays, id: \.self) { weekday in
                        Text(weekday)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }

                GeometryReader { proxy in
                    LazyVGrid(columns: columns, spacing: rowSpacing) {
                        ForEach(0..<leadingBlankCount, id: \.self) { _ in
                            Color.clear.frame(height: dateCellHeight)
                        }

                        ForEach(monthDates, id: \.self) { date in
                            LeaveDateCell(
                                date: date,
                                isSelected: selectedKeys.contains(calendar.startOfDayKey(for: date)),
                                isToday: calendar.isDateInToday(date)
                            )
                            .onTapGesture {
                                guard !isDraggingSelection else { return }
                                toggle(date)
                            }
                        }
                    }
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 8, coordinateSpace: .local)
                            .onChanged { value in
                                isDraggingSelection = true
                                selectDate(at: value.location, gridWidth: proxy.size.width)
                            }
                            .onEnded { _ in
                                dragTouchedKeys.removeAll()
                                DispatchQueue.main.async {
                                    isDraggingSelection = false
                                }
                            }
                    )
                }
                .frame(height: dateGridHeight)

                HStack {
                    Text("\(selectedKeys.count) 天已选")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("清空") {
                        selectedKeys.removeAll()
                    }
                    .disabled(selectedKeys.isEmpty)
                }

                Text("点选日期可切换；按住日期滑动经过会连续加入多天。保存后这些日期会作为额外休息日参与工作日识别，并在首页与未来预览中显示“休”。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }
            .padding(20)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(leaveType.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        onSave(selectedKeys)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var monthDates: [Date] {
        guard let range = calendar.range(of: .day, in: .month, for: visibleMonth) else { return [] }
        return range.compactMap { day in
            calendar.date(bySetting: .day, value: day, of: visibleMonth)
        }
    }

    private var leadingBlankCount: Int {
        guard let first = monthDates.first else { return 0 }
        return (calendar.weekdayNumber(for: first) + 5) % 7
    }

    private var dateGridHeight: CGFloat {
        CGFloat(max(rowCount, 1)) * dateCellHeight + CGFloat(max(rowCount - 1, 0)) * rowSpacing
    }

    private var rowCount: Int {
        Int(ceil(Double(leadingBlankCount + monthDates.count) / 7.0))
    }

    private func shiftMonth(_ delta: Int) {
        visibleMonth = calendar.date(byAdding: .month, value: delta, to: visibleMonth) ?? visibleMonth
    }

    private func toggle(_ date: Date) {
        let key = calendar.startOfDayKey(for: date)
        if selectedKeys.contains(key) {
            selectedKeys.remove(key)
        } else {
            selectedKeys.insert(key)
        }
    }

    private func selectDuringDrag(_ date: Date) {
        let key = calendar.startOfDayKey(for: date)
        guard dragTouchedKeys.insert(key).inserted else { return }
        selectedKeys.insert(key)
    }

    private func selectDate(at location: CGPoint, gridWidth: CGFloat) {
        guard let date = date(at: location, gridWidth: gridWidth) else { return }
        selectDuringDrag(date)
    }

    private func date(at location: CGPoint, gridWidth: CGFloat) -> Date? {
        guard location.x >= 0, location.y >= 0 else { return nil }
        let cellWidth = (gridWidth - gridSpacing * 6) / 7
        let columnStride = cellWidth + gridSpacing
        let rowStride = dateCellHeight + rowSpacing
        let column = Int(location.x / columnStride)
        let row = Int(location.y / rowStride)
        guard column >= 0, column < 7, row >= 0 else { return nil }

        let xInCell = location.x - CGFloat(column) * columnStride
        let yInCell = location.y - CGFloat(row) * rowStride
        guard xInCell <= cellWidth, yInCell <= dateCellHeight else { return nil }

        let dateIndex = row * 7 + column - leadingBlankCount
        guard monthDates.indices.contains(dateIndex) else { return nil }
        return monthDates[dateIndex]
    }
}

private struct LeaveDateCell: View {
    var date: Date
    var isSelected: Bool
    var isToday: Bool

    private var calendar: Calendar { .chinaAlarm }

    var body: some View {
        Text("\(calendar.component(.day, from: date))")
            .font(.body.weight(isSelected || isToday ? .bold : .medium))
            .monospacedDigit()
            .foregroundStyle(isSelected ? .white : .primary)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(isSelected ? Color.green : Color(uiColor: .secondarySystemGroupedBackground))
            .overlay {
                if isToday && !isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.orange, lineWidth: 2)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
    }
}
