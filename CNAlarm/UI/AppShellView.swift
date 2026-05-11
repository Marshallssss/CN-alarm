import SwiftData
import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case alarms
    case templates
    case reminders
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .alarms: "闹铃"
        case .templates: "组合"
        case .reminders: "提醒"
        case .settings: "设置"
        }
    }

    var icon: String {
        switch self {
        case .alarms: "alarm.fill"
        case .templates: "square.stack.3d.up.fill"
        case .reminders: "bell.badge.fill"
        case .settings: "gearshape.fill"
        }
    }
}

struct AppShellView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \AlarmProfile.createdAt) private var profiles: [AlarmProfile]
    @Query(sort: \AlarmComboTemplate.createdAt) private var templates: [AlarmComboTemplate]
    @Query private var exceptions: [CalendarException]
    @Query private var companyRules: [CompanyCalendarRule]
    @Query private var holidayDatasets: [HolidayDataset]
    @State private var selection: AppTab = .alarms
    @State private var lastAutomaticAlarmSyncSignature: String?

    var body: some View {
        TabView(selection: $selection) {
            AlarmListView()
                .tabItem { Label(AppTab.alarms.title, systemImage: AppTab.alarms.icon) }
                .tag(AppTab.alarms)

            TemplateLibraryView()
                .tabItem { Label(AppTab.templates.title, systemImage: AppTab.templates.icon) }
                .tag(AppTab.templates)

            ReminderCenterView()
                .tabItem { Label(AppTab.reminders.title, systemImage: AppTab.reminders.icon) }
                .tag(AppTab.reminders)

            SettingsView()
                .tabItem { Label(AppTab.settings.title, systemImage: AppTab.settings.icon) }
                .tag(AppTab.settings)
        }
        .tint(.orange)
        .task {
            SeedDataService.seedIfNeeded(context: modelContext)
            NotificationActionApplier.applyPendingActions(context: modelContext)
            await HolidayCalendarCacheService.refreshIfStale(
                context: modelContext,
                sourceURL: UserDefaults.standard.string(forKey: "holidaySourceURL") ?? HolidayCalendarSource.defaultURL.absoluteString
            )
            try? modelContext.save()
            await syncSystemAlarmsIfAuthorized()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                NotificationActionApplier.applyPendingActions(context: modelContext)
                try? modelContext.save()
                Task {
                    await syncSystemAlarmsIfAuthorized()
                }
            }
        }
    }

    private var currentAlarmSyncSignature: String {
        AlarmScheduleSyncSignature.make(
            profiles: profiles,
            templates: templates,
            holidayDatasets: holidayDatasets,
            companyRules: companyRules,
            exceptions: exceptions
        )
    }

    private func syncSystemAlarmsIfAuthorized() async {
        guard AlarmKitScheduler().isAuthorized else { return }
        let signature = currentAlarmSyncSignature
        guard signature != lastAutomaticAlarmSyncSignature else { return }
        do {
            _ = try await AlarmScheduleSyncService().sync(
                profiles: profiles,
                templates: templates,
                holidayDatasets: holidayDatasets,
                companyRules: companyRules,
                exceptions: exceptions
            )
            lastAutomaticAlarmSyncSignature = signature
        } catch {
            // The alarm list screen reports explicit sync failures. Startup repair stays silent.
        }
    }
}

struct MainPageTitle: View {
    var title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        MainPageHeader(title) {
            EmptyView()
        }
    }
}

struct MainPageHeader<Accessory: View>: View {
    var title: String
    var accessory: Accessory

    init(_ title: String, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(title)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Spacer(minLength: 12)

            accessory
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
