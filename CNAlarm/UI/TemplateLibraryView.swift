import SwiftData
import SwiftUI

struct TemplateLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AlarmComboTemplate.createdAt) private var templates: [AlarmComboTemplate]
    @Query private var profiles: [AlarmProfile]
    @State private var pendingTemplateDelete: AlarmComboTemplate?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    MainPageHeader("组合模板") {
                        Button {
                            modelContext.insert(
                                AlarmComboTemplate(name: "新组合", anchorMode: .lastRingIsDeadline, offsets: [-10, -5, 0])
                            )
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.orange)
                                .frame(width: 46, height: 46)
                                .background(Color(uiColor: .secondarySystemGroupedBackground))
                                .clipShape(Circle())
                        }
                        .accessibilityLabel("添加组合模板")
                    }
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                Section("可复用组合") {
                    ForEach(sortedTemplates) { template in
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
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                pendingTemplateDelete = template
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .contentMargins(.top, 0, for: .scrollContent)
            .confirmationDialog(
                "删除组合模板？",
                isPresented: deleteConfirmationBinding,
                titleVisibility: .visible
            ) {
                if let template = pendingTemplateDelete {
                    Button("删除“\(template.name)”", role: .destructive) {
                        deleteTemplate(template)
                        pendingTemplateDelete = nil
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("已套用到闹铃的组合会保留当前时间安排，只会解除模板引用。")
            }
        }
    }

    private var sortedTemplates: [AlarmComboTemplate] {
        templates.sorted { $0.createdAt < $1.createdAt }
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingTemplateDelete != nil },
            set: { isPresented in
                if !isPresented {
                    pendingTemplateDelete = nil
                }
            }
        )
    }

    private func deleteTemplate(_ template: AlarmComboTemplate) {
        for profile in profiles where profile.comboTemplateID == template.id {
            profile.comboTemplateID = nil
        }
        modelContext.delete(template)
        try? modelContext.save()
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
                    Text("AlarmKit 系统默认").tag(SoundLibrary.alarmKitDefaultIdentifier)
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
        let gaps = zip(sorted.dropFirst(), sorted).map { abs($0 - $1) }.filter { $0 > 0 }
        let interval = gaps.first ?? 5
        let isUniform = !gaps.isEmpty && gaps.allSatisfy { $0 == interval }
        switch anchorMode {
        case .firstRingIsDeadline:
            if !isUniform {
                return "复杂：\(firstRingDescriptions(from: sorted).joined(separator: "、"))，共 \(count) 次"
            }
            return "从目标时间开始，每 \(interval) 分钟响一次，共 \(count) 次"
        case .lastRingIsDeadline:
            if !isUniform {
                return "复杂：\(lastRingDescriptions(from: sorted).joined(separator: "、"))，共 \(count) 次"
            }
            return "提前 \(max(count - 1, 0) * interval) 分钟开始，共 \(count) 次"
        }
    }

    private func firstRingDescriptions(from offsets: [Int]) -> [String] {
        offsets.prefix(8).map { offset in
            offset == 0 ? "目标时间" : "目标后 \(max(offset, 0)) 分钟"
        }
    }

    private func lastRingDescriptions(from offsets: [Int]) -> [String] {
        offsets.prefix(8).map { offset in
            offset == 0 ? "目标时间" : "目标前 \(abs(min(offset, 0))) 分钟"
        }
    }
}
