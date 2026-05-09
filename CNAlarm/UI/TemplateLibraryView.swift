import SwiftData
import SwiftUI

struct TemplateLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AlarmComboTemplate.createdAt) private var templates: [AlarmComboTemplate]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    MainPageTitle("组合模板")
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 2, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                Section("可复用组合") {
                    ForEach(templates) { template in
                        NavigationLink {
                            TemplateEditorView(template: template)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(template.name)
                                Text(template.comboSummary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        offsets.map { templates[$0] }.forEach(modelContext.delete)
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        modelContext.insert(
                            AlarmComboTemplate(name: "新组合", anchorMode: .lastRingIsDeadline, offsets: [-10, -5, 0])
                        )
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .accessibilityLabel("添加组合模板")
                }
            }
        }
    }
}

struct TemplateEditorView: View {
    @Bindable var template: AlarmComboTemplate
    @Query(sort: \SoundAsset.createdAt) private var sounds: [SoundAsset]

    var body: some View {
        Form {
            Section("模板") {
                TextField("名称", text: $template.name)
                Picker("目标时间含义", selection: $template.anchorRaw) {
                    ForEach(ComboAnchorMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                ComboOffsetEditor(anchorMode: template.anchorMode, offsets: Binding(get: {
                    template.offsets
                }, set: {
                    template.offsets = $0
                }))
            }

            Section("默认") {
                Toggle("允许稍后提醒", isOn: $template.allowSnooze)
                Picker("铃声", selection: $template.defaultSoundIdentifier) {
                    Text("系统默认闹铃声").tag(SoundLibrary.alarmKitDefaultIdentifier)
                    ForEach(sounds) { sound in
                        Text(sound.name).tag(sound.filename)
                    }
                }
            }
        }
        .navigationTitle(template.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension AlarmComboTemplate {
    var comboSummary: String {
        let count = max(offsets.count, 1)
        let sorted = offsets.sorted()
        let interval = zip(sorted.dropFirst(), sorted).map { abs($0 - $1) }.filter { $0 > 0 }.first ?? 5
        switch anchorMode {
        case .firstRingIsDeadline:
            return "从目标时间开始，每 \(interval) 分钟响一次，共 \(count) 次"
        case .lastRingIsDeadline:
            return "提前 \(max(count - 1, 0) * interval) 分钟开始，共 \(count) 次"
        }
    }
}
