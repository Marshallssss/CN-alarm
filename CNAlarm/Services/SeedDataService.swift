import Foundation
import SwiftData

enum SeedDataService {
    static func seedIfNeeded(context: ModelContext) {
        seedSoundsIfNeeded(context: context)
        seedTemplatesIfNeeded(context: context)
        seedReminderRulesIfNeeded(context: context)
        seedHolidayDatasetIfNeeded(context: context)
    }

    private static func seedSoundsIfNeeded(context: ModelContext) {
        let manager = SoundAssetManager()
        try? manager.installBundledSoundsIfNeeded()

        let descriptor = FetchDescriptor<SoundAsset>()
        let existing = (try? context.fetch(descriptor)) ?? []
        let existingFilenames = Set(existing.map(\.filename))
        for sound in manager.builtInSoundAssetDefinitions() where !existingFilenames.contains(sound.filename) {
            context.insert(sound)
        }
    }

    private static func seedTemplatesIfNeeded(context: ModelContext) {
        let descriptor = FetchDescriptor<AlarmComboTemplate>()
        let existing = (try? context.fetch(descriptor)) ?? []
        guard existing.isEmpty else { return }
        AlarmComboTemplate.defaultTemplates().forEach(context.insert)
    }

    private static func seedReminderRulesIfNeeded(context: ModelContext) {
        let descriptor = FetchDescriptor<ReminderRule>()
        let existing = (try? context.fetch(descriptor)) ?? []
        guard existing.isEmpty else { return }
        ReminderRule.defaults().forEach(context.insert)
    }

    private static func seedHolidayDatasetIfNeeded(context: ModelContext) {
        let descriptor = FetchDescriptor<HolidayDataset>()
        let existing = (try? context.fetch(descriptor)) ?? []
        guard existing.isEmpty else { return }
        let encoded = (try? JSONEncoder().encode(HolidayCalendar.fixture2026)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        context.insert(HolidayDataset(rawJSON: encoded))
    }
}

enum HolidayCalendarCacheService {
    @MainActor
    static func refreshIfStale(
        context: ModelContext,
        sourceURL: String,
        maxAge: TimeInterval = 6 * 60 * 60,
        now: Date = Date()
    ) async {
        let descriptor = FetchDescriptor<HolidayDataset>()
        let datasets = (try? context.fetch(descriptor)) ?? []
        let dataset = datasets.last ?? HolidayDataset(sourceURL: sourceURL)
        if datasets.isEmpty {
            context.insert(dataset)
        }
        guard now.timeIntervalSince(dataset.fetchedAt) > maxAge else { return }
        guard let url = URL(string: sourceURL) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            _ = try HolidayCalendarParser().parse(data: data)
            dataset.sourceURL = sourceURL
            dataset.fetchedAt = now
            dataset.rawJSON = String(data: data, encoding: .utf8) ?? ""
        } catch {
            // Keep the cached or fixture calendar; alarm scheduling must keep working offline.
        }
    }
}
