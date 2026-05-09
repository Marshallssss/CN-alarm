import SwiftData
import SwiftUI

struct ReminderCenterView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var rules: [ReminderRule]
    @Query private var events: [ReminderEvent]
    @Query(sort: \CalendarException.createdAt) private var exceptions: [CalendarException]
    @Query private var holidayDatasets: [HolidayDataset]
    @State private var reminderStatus: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    MainPageTitle("提醒与例外")
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 2, trailing: 0))
                        .listRowBackground(Color.clear)
                }

                Section("关键日期提醒") {
                    ForEach(rules) { rule in
                        ReminderRuleRow(rule: rule)
                    }
                    if let reminderStatus {
                        Text(reminderStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button("重新生成未来提醒") {
                        generateReminderEvents()
                    }
                }

                Section("应用内提醒中心") {
                    if visiblePendingDrafts.isEmpty {
                        Text("未来一年暂无关键提醒")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(visiblePendingDrafts) { draft in
                        ReminderDraftRow(draft: draft)
                    }
                }

                Section("已保存例外") {
                    Text("从首页日历点击日期即可添加或修改特殊安排。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(exceptions) { item in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.dateKey)
                                Text(item.kind.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if [.extraAlarm, .moveComboDeadline, .childTime].contains(item.kind) {
                                Text(ClockTime(hour: item.hour, minute: item.minute).displayText)
                                    .font(.headline.monospacedDigit())
                            }
                        }
                    }
                    .onDelete { offsets in
                        offsets.map { exceptions[$0] }.forEach(modelContext.delete)
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var holidayCalendar: HolidayCalendar {
        holidayDatasets.last.map { HolidayCalendar.decodeStored($0.rawJSON) } ?? .fixture2026
    }

    private var pendingDrafts: [ReminderEventDraft] {
        ReminderPlanner().plan(rules: rules, holidayCalendar: holidayCalendar, from: Date(), days: 370)
    }

    private var visiblePendingDrafts: [ReminderEventDraft] {
        Dictionary(grouping: pendingDrafts, by: \.kind)
            .values
            .flatMap { $0.sorted { $0.fireDate < $1.fireDate }.prefix(2) }
            .sorted { $0.fireDate < $1.fireDate }
    }

    private func generateReminderEvents() {
        let existingIDs = Set(events.map(\.id))
        for draft in pendingDrafts {
            guard !existingIDs.contains(draft.id) else { continue }
            modelContext.insert(
                ReminderEvent(
                    id: draft.id,
                    fireDate: draft.fireDate,
                    title: draft.title,
                    message: draft.message,
                    targetDateKey: draft.targetDateKey,
                    actionRaw: draft.actionRaw
                )
            )
        }
        Task {
            do {
                try await NotificationReminderService().schedule(drafts: Array(pendingDrafts.prefix(60)))
                reminderStatus = "已生成 \(pendingDrafts.count) 条应用内提醒，并注册最近 \(min(pendingDrafts.count, 60)) 条系统通知。"
            } catch {
                reminderStatus = "已生成应用内提醒；系统通知注册失败：\(error.localizedDescription)"
            }
        }
    }
}

private struct ReminderRuleRow: View {
    @Bindable var rule: ReminderRule

    var body: some View {
        Toggle(isOn: $rule.isEnabled) {
            VStack(alignment: .leading, spacing: 4) {
                Text(rule.kind.title)
                Text(rule.detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ReminderDraftRow: View {
    var draft: ReminderEventDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(draft.title)
                    .font(.headline)
                Spacer()
                Text(draft.fireDate, style: .time)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
            }
            Text(draft.fireDate.formatted(date: .long, time: .omitted))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(draft.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
}

private extension ReminderRule {
    var detailText: String {
        let time = String(format: "%02d:%02d", hour, minute)
        switch kind {
        case .fridayNight:
            return "每周五 \(time) 提醒检查周末安排"
        case .holidayLead:
            let leads = (leadDays.isEmpty ? [3, 1] : leadDays).sorted(by: >)
            return "节假日前 \(leads.map(String.init).joined(separator: " / ")) 天 \(time) 提醒"
        case .makeupWorkdayEve:
            return "补班工作日前一天 \(time) 提醒"
        }
    }
}
