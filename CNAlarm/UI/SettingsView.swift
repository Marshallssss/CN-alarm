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
    @AppStorage("winterVacationModeEnabled") private var winterVacationModeEnabled = false
    @AppStorage("summerVacationModeEnabled") private var summerVacationModeEnabled = false
    @AppStorage("vacationStartTimestamp") private var vacationStartTimestamp = Date().timeIntervalSince1970
    @AppStorage("vacationEndTimestamp") private var vacationEndTimestamp = Calendar.chinaAlarm.date(byAdding: .day, value: 30, to: Date())?.timeIntervalSince1970 ?? Date().timeIntervalSince1970
    @AppStorage("summerVacationStartTimestamp") private var summerVacationStartTimestamp = Calendar.chinaAlarm.date(byAdding: .month, value: 2, to: Date())?.timeIntervalSince1970 ?? Date().timeIntervalSince1970
    @AppStorage("summerVacationEndTimestamp") private var summerVacationEndTimestamp = Calendar.chinaAlarm.date(byAdding: .month, value: 3, to: Date())?.timeIntervalSince1970 ?? Date().timeIntervalSince1970

    @State private var refreshStatus = "未刷新"
    @State private var importingSound = false
    @State private var soundImportStatus: String?
    @State private var alarmDiagnosticStatus = "未检查"
    @StateObject private var previewPlayer = SoundPreviewPlayer()

    private let soundManager = SoundAssetManager()
    private let winterVacationExceptionNote = "设置生成：寒假休息"
    private let summerVacationExceptionNote = "设置生成：暑假休息"
    private let legacyVacationExceptionNote = "设置生成：寒暑假休息"

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
                    Toggle("寒假休息", isOn: winterVacationModeBinding)
                    if winterVacationModeEnabled {
                        DatePicker("寒假开始", selection: vacationStartBinding, displayedComponents: .date)
                        DatePicker("寒假结束", selection: vacationEndBinding, displayedComponents: .date)
                    }
                    Toggle("暑假休息", isOn: summerVacationModeBinding)
                    if summerVacationModeEnabled {
                        DatePicker("暑假开始", selection: summerVacationStartBinding, displayedComponents: .date)
                        DatePicker("暑假结束", selection: summerVacationEndBinding, displayedComponents: .date)
                    }
                    Text("开启后会参与智能工作日识别；手动日期例外和国家调休仍保持更高优先级。")
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

    private var winterVacationModeBinding: Binding<Bool> {
        Binding(
            get: { winterVacationModeEnabled },
            set: { enabled in
                winterVacationModeEnabled = enabled
                applyVacationExceptions()
            }
        )
    }

    private var summerVacationModeBinding: Binding<Bool> {
        Binding(
            get: { summerVacationModeEnabled },
            set: { enabled in
                summerVacationModeEnabled = enabled
                applyVacationExceptions()
            }
        )
    }

    private var vacationStartBinding: Binding<Date> {
        Binding(
            get: { Date(timeIntervalSince1970: vacationStartTimestamp) },
            set: { date in
                vacationStartTimestamp = Calendar.chinaAlarm.startOfDay(for: date).timeIntervalSince1970
                applyVacationExceptions()
            }
        )
    }

    private var vacationEndBinding: Binding<Date> {
        Binding(
            get: { Date(timeIntervalSince1970: vacationEndTimestamp) },
            set: { date in
                vacationEndTimestamp = Calendar.chinaAlarm.startOfDay(for: date).timeIntervalSince1970
                applyVacationExceptions()
            }
        )
    }

    private var summerVacationStartBinding: Binding<Date> {
        Binding(
            get: { Date(timeIntervalSince1970: summerVacationStartTimestamp) },
            set: { date in
                summerVacationStartTimestamp = Calendar.chinaAlarm.startOfDay(for: date).timeIntervalSince1970
                applyVacationExceptions()
            }
        )
    }

    private var summerVacationEndBinding: Binding<Date> {
        Binding(
            get: { Date(timeIntervalSince1970: summerVacationEndTimestamp) },
            set: { date in
                summerVacationEndTimestamp = Calendar.chinaAlarm.startOfDay(for: date).timeIntervalSince1970
                applyVacationExceptions()
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

    private func applyVacationExceptions() {
        let generatedNotes = [winterVacationExceptionNote, summerVacationExceptionNote, legacyVacationExceptionNote]
        for exception in exceptions where generatedNotes.contains(exception.note) {
            modelContext.delete(exception)
        }

        var insertedDateKeys = Set<String>()
        if winterVacationModeEnabled {
            insertVacationExceptions(
                startTimestamp: vacationStartTimestamp,
                endTimestamp: vacationEndTimestamp,
                note: winterVacationExceptionNote,
                insertedDateKeys: &insertedDateKeys
            )
        }
        if summerVacationModeEnabled {
            insertVacationExceptions(
                startTimestamp: summerVacationStartTimestamp,
                endTimestamp: summerVacationEndTimestamp,
                note: summerVacationExceptionNote,
                insertedDateKeys: &insertedDateKeys
            )
        }

        saveSettingsAndResync()
    }

    private func insertVacationExceptions(startTimestamp: Double, endTimestamp: Double, note: String, insertedDateKeys: inout Set<String>) {
        let calendar = Calendar.chinaAlarm
        let start = calendar.startOfDay(for: Date(timeIntervalSince1970: min(startTimestamp, endTimestamp)))
        let end = calendar.startOfDay(for: Date(timeIntervalSince1970: max(startTimestamp, endTimestamp)))
        let days = min((calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1, 180)
        for date in calendar.dateRange(from: start, days: max(days, 0)) {
            let dateKey = calendar.startOfDayKey(for: date)
            guard insertedDateKeys.insert(dateKey).inserted else { continue }
            modelContext.insert(
                CalendarException(
                    dateKey: dateKey,
                    kind: .restDayOverride,
                    note: note
                )
            )
        }
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
