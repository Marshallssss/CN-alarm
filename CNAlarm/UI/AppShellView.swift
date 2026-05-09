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
    @State private var selection: AppTab = .alarms

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
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                NotificationActionApplier.applyPendingActions(context: modelContext)
            }
        }
    }
}

struct MainPageTitle: View {
    var title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 34, weight: .bold, design: .rounded))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
    }
}
