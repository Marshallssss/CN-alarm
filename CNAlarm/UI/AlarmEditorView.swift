import SwiftData
import SwiftUI

struct AlarmEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var profile: AlarmProfile
    @Query(sort: \AlarmComboTemplate.createdAt) private var templates: [AlarmComboTemplate]
    @Query(sort: \SoundAsset.createdAt) private var sounds: [SoundAsset]
    @StateObject private var previewPlayer = SoundPreviewPlayer()
    @State private var saveInvoked = false
    @State private var comboEditorID = UUID()
    var isNewProfile = false
    var onSave: ((AlarmProfile) -> Void)?
    var onCancel: (() -> Void)?

    var body: some View {
        Form {
            Section {
                WheelTimePicker(hour: $profile.hour, minute: $profile.minute)
            }

            Section("闹铃") {
                Picker("模式", selection: $profile.modeRaw) {
                    ForEach(AlarmMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                HStack {
                    Text("闹铃标题")
                    TextField("闹铃", text: $profile.label)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                }
                Toggle("使用中国调休工作日", isOn: $profile.followsSmartWorkday)
                Toggle("稍后提醒", isOn: $profile.allowSnooze)
                Stepper("稍后提醒 \(profile.snoozeMinutes) 分钟", value: $profile.snoozeMinutes, in: 1...30)
            }

            if profile.mode == .combo {
                comboSection
                Section("预览") {
                    ForEach(Array(previewTimes.enumerated()), id: \.offset) { index, time in
                        HStack {
                            Text("第 \(index + 1) 响")
                            Spacer()
                            Text(time.displayText)
                                .font(.headline.monospacedDigit())
                        }
                    }
                }
            }
            Section("声音") {
                Picker("铃声", selection: $profile.soundIdentifier) {
                    Text("AlarmKit 系统默认").tag(SoundLibrary.alarmKitDefaultIdentifier)
                    ForEach(sounds) { sound in
                        Text(sound.name).tag(sound.filename)
                    }
                }
                Button("试听当前铃声") {
                    previewPlayer.preview(identifier: profile.soundIdentifier)
                }
                if let status = previewPlayer.status {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(profile.mode.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isNewProfile {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        saveInvoked = true
                        onCancel?()
                        dismiss()
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("保存") {
                    saveInvoked = true
                    onSave?(profile)
                    dismiss()
                }
                .fontWeight(.semibold)
            }
        }
        .onDisappear {
            if !isNewProfile && !saveInvoked {
                onSave?(profile)
            }
        }
    }

    private var comboSection: some View {
        Section("闹铃组合") {
            Picker("组合模板", selection: comboTemplateSelection) {
                Text("自定义").tag(Optional<UUID>.none)
                ForEach(templates) { template in
                    Text(template.name).tag(Optional(template.id))
                }
            }
            .disabled(templates.isEmpty)

            Picker("目标时间含义", selection: $profile.comboAnchorRaw) {
                ForEach(ComboAnchorMode.allCases) { anchor in
                    Text(anchor.title).tag(anchor.rawValue)
                }
            }
            ComboOffsetEditor(anchorMode: profile.comboAnchorMode, offsets: Binding(get: {
                profile.comboOffsets
            }, set: {
                profile.comboOffsets = $0
            }))
            .id(comboEditorID)
        }
    }

    private var comboTemplateSelection: Binding<UUID?> {
        Binding(
            get: { profile.comboTemplateID },
            set: { templateID in
                guard let templateID else {
                    profile.comboTemplateID = nil
                    comboEditorID = UUID()
                    return
                }
                if let template = templates.first(where: { $0.id == templateID }) {
                    applyTemplate(template)
                }
            }
        )
    }

    private func applyTemplate(_ template: AlarmComboTemplate) {
        profile.comboTemplateID = template.id
        profile.comboAnchorMode = template.anchorMode
        profile.comboOffsets = template.offsets
        profile.soundIdentifier = template.defaultSoundIdentifier
        profile.allowSnooze = template.allowSnooze
        comboEditorID = UUID()
    }

    private var previewTimes: [ClockTime] {
        AlarmScheduleResolver().comboTimes(
            deadline: ClockTime(hour: profile.hour, minute: profile.minute),
            anchorMode: profile.comboAnchorMode,
            offsets: profile.comboOffsets
        )
    }
}
