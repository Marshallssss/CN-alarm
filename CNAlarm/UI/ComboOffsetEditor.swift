import SwiftUI

struct ComboOffsetEditor: View {
    var anchorMode: ComboAnchorMode
    @Binding var offsets: [Int]
    @State private var advancedMode = false
    private let minuteRange = 0...240

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("复杂模式", isOn: advancedModeBinding)

            if advancedMode {
                advancedEditor
            } else {
                compactStepper(title: "响铃次数", valueText: "\(ringCount) 次", binding: ringCountBinding, range: 1...8)
                compactStepper(title: "每次间隔", valueText: "\(intervalMinutes) 分钟", binding: intervalBinding, range: 1...30)
            }

            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear {
            if offsets.isEmpty {
                rebuild(count: 3, interval: 5)
            }
            advancedMode = !isSimplePattern(offsets)
        }
        .onChange(of: anchorMode) { _, _ in
            offsets = normalized(offsets)
            advancedMode = !isSimplePattern(offsets)
        }
    }

    private var advancedEditor: some View {
        let values = displayValues
        return VStack(alignment: .leading, spacing: 12) {
            Button {
                applyDensePreset()
            } label: {
                Label(densePresetTitle, systemImage: "wand.and.stars")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.orange)

            VStack(spacing: 8) {
                ForEach(values.indices, id: \.self) { index in
                    advancedRow(index: index, displayMinute: values[index], allValues: values)
                }
            }

            Menu {
                ForEach(addablePresetMinutes, id: \.self) { minute in
                    Button(displayText(for: minute)) {
                        addDisplayMinute(minute)
                    }
                }
            } label: {
                Label("添加一响", systemImage: "plus.circle.fill")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.orange)
            .disabled(addablePresetMinutes.isEmpty)
        }
    }

    private func advancedRow(index: Int, displayMinute: Int, allValues: [Int]) -> some View {
        let limits = limitsForDisplayMinute(at: index, values: allValues)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("第 \(index + 1) 响")
                    .font(.subheadline.weight(.semibold))
                Text(displayText(for: displayMinute))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            HStack(spacing: 0) {
                Button {
                    setDisplayMinute(at: index, to: displayMinute - 1)
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 42, height: 34)
                }
                .disabled(displayMinute <= limits.lowerBound)

                Divider()
                    .frame(height: 22)

                Button {
                    setDisplayMinute(at: index, to: displayMinute + 1)
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 42, height: 34)
                }
                .disabled(displayMinute >= limits.upperBound)
            }
            .font(.title3.weight(.semibold))
            .buttonStyle(.plain)
            .background(Color(uiColor: .tertiarySystemGroupedBackground))
            .clipShape(Capsule())

            Button {
                removeAdvancedOffset(at: index)
            } label: {
                Image(systemName: "trash")
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .foregroundStyle(allValues.count > 1 ? .red : .secondary)
            .disabled(allValues.count <= 1)
            .accessibilityLabel("删除第 \(index + 1) 响")
        }
        .font(.body)
        .frame(minHeight: 48)
    }

    private func compactStepper(title: String, valueText: String, binding: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
            Text(valueText)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Stepper(title, value: binding, in: range)
                .labelsHidden()
                .frame(width: 120)
        }
        .font(.body)
        .frame(minHeight: 42)
    }

    private var ringCount: Int {
        max(offsets.count, 1)
    }

    private var intervalMinutes: Int {
        let sorted = offsets.sorted()
        guard sorted.count > 1 else { return 5 }
        let gaps = zip(sorted.dropFirst(), sorted).map { abs($0 - $1) }.filter { $0 > 0 }
        return gaps.first ?? 5
    }

    private var ringCountBinding: Binding<Int> {
        Binding(
            get: { ringCount },
            set: { rebuild(count: $0, interval: intervalMinutes) }
        )
    }

    private var intervalBinding: Binding<Int> {
        Binding(
            get: { intervalMinutes },
            set: { rebuild(count: ringCount, interval: $0) }
        )
    }

    private var advancedModeBinding: Binding<Bool> {
        Binding(
            get: { advancedMode },
            set: { enabled in
                advancedMode = enabled
                if !enabled {
                    rebuild(count: ringCount, interval: intervalMinutes)
                }
            }
        )
    }

    private var sortedOffsets: [Int] {
        normalized(offsets)
    }

    private var displayValues: [Int] {
        sortedOffsets.map(displayMinutes(for:))
    }

    private var summary: String {
        if advancedMode {
            return advancedSummary
        }
        switch anchorMode {
        case .firstRingIsDeadline:
            return "从目标时间开始，每 \(intervalMinutes) 分钟响一次，共 \(ringCount) 次。"
        case .lastRingIsDeadline:
            let lead = max(ringCount - 1, 0) * intervalMinutes
            return "从目标时间前 \(lead) 分钟开始，每 \(intervalMinutes) 分钟响一次，最后一次是目标时间。"
        }
    }

    private var advancedSummary: String {
        let values = displayValues
        guard !values.isEmpty else { return "还没有设置响铃时间。" }
        switch anchorMode {
        case .firstRingIsDeadline:
            let joined = values.map { $0 == 0 ? "目标时间" : "目标后 \($0) 分钟" }.joined(separator: "、")
            return "将在 \(joined) 响铃，可用于非等间隔叫醒。"
        case .lastRingIsDeadline:
            let joined = values.map { $0 == 0 ? "目标时间" : "目标前 \($0) 分钟" }.joined(separator: "、")
            return "将在 \(joined) 响铃，可用于非等间隔叫醒。"
        }
    }

    private var densePresetTitle: String {
        switch anchorMode {
        case .firstRingIsDeadline:
            return "套用密集叫醒：目标后 0、1、2、3、5、8 分钟"
        case .lastRingIsDeadline:
            return "套用密集叫醒：目标前 10、8、5、3、2、1 分钟"
        }
    }

    private var addablePresetMinutes: [Int] {
        let existing = Set(displayValues)
        return candidateMinutes.filter { !existing.contains($0) }
    }

    private var candidateMinutes: [Int] {
        switch anchorMode {
        case .firstRingIsDeadline:
            return [0, 1, 2, 3, 5, 8, 10, 15, 20, 30, 45, 60, 90, 120]
        case .lastRingIsDeadline:
            return [0, 1, 2, 3, 5, 8, 10, 15, 20, 30, 45, 60, 90, 120]
        }
    }

    private func rebuild(count: Int, interval: Int) {
        let safeCount = max(count, 1)
        let safeInterval = max(interval, 1)
        switch anchorMode {
        case .firstRingIsDeadline:
            offsets = (0..<safeCount).map { $0 * safeInterval }
        case .lastRingIsDeadline:
            offsets = (0..<safeCount).map { -((safeCount - 1 - $0) * safeInterval) }
        }
    }

    private func displayText(for minutes: Int) -> String {
        if minutes == 0 { return "目标时间" }
        switch anchorMode {
        case .firstRingIsDeadline:
            return "目标后 \(minutes) 分钟"
        case .lastRingIsDeadline:
            return "目标前 \(minutes) 分钟"
        }
    }

    private func applyDensePreset() {
        switch anchorMode {
        case .firstRingIsDeadline:
            offsets = [0, 1, 2, 3, 5, 8]
        case .lastRingIsDeadline:
            offsets = [-10, -8, -5, -3, -2, -1]
        }
    }

    private func addDisplayMinute(_ minute: Int) {
        offsets = normalized(sortedOffsets + [storedOffset(fromDisplayMinutes: minute)])
    }

    private func removeAdvancedOffset(at index: Int) {
        var values = sortedOffsets
        guard values.count > 1, values.indices.contains(index) else { return }
        values.remove(at: index)
        offsets = normalized(values)
    }

    private func setDisplayMinute(at index: Int, to minute: Int) {
        var values = displayValues
        guard values.indices.contains(index) else { return }
        let limits = limitsForDisplayMinute(at: index, values: values)
        values[index] = min(max(minute, limits.lowerBound), limits.upperBound)
        offsets = normalized(values.map(storedOffset(fromDisplayMinutes:)))
    }

    private func limitsForDisplayMinute(at index: Int, values: [Int]) -> ClosedRange<Int> {
        guard values.indices.contains(index) else { return minuteRange }
        switch anchorMode {
        case .firstRingIsDeadline:
            let lower = max(index == values.startIndex ? minuteRange.lowerBound : values[index - 1] + 1, minuteRange.lowerBound)
            let upper = min(index == values.index(before: values.endIndex) ? minuteRange.upperBound : values[index + 1] - 1, minuteRange.upperBound)
            guard lower <= upper else { return values[index]...values[index] }
            return lower...upper
        case .lastRingIsDeadline:
            let lower = max(index == values.index(before: values.endIndex) ? minuteRange.lowerBound : values[index + 1] + 1, minuteRange.lowerBound)
            let upper = min(index == values.startIndex ? minuteRange.upperBound : values[index - 1] - 1, minuteRange.upperBound)
            guard lower <= upper else { return values[index]...values[index] }
            return lower...upper
        }
    }

    private func displayMinutes(for offset: Int) -> Int {
        switch anchorMode {
        case .firstRingIsDeadline:
            return max(offset, 0)
        case .lastRingIsDeadline:
            return abs(min(offset, 0))
        }
    }

    private func storedOffset(fromDisplayMinutes minutes: Int) -> Int {
        switch anchorMode {
        case .firstRingIsDeadline:
            return max(minutes, 0)
        case .lastRingIsDeadline:
            return -max(minutes, 0)
        }
    }

    private func normalized(_ values: [Int]) -> [Int] {
        values
            .map { storedOffset(fromDisplayMinutes: displayMinutes(for: $0)) }
            .sorted()
    }

    private func isSimplePattern(_ values: [Int]) -> Bool {
        let sorted = normalized(values)
        guard !sorted.isEmpty else { return true }
        let gaps = zip(sorted.dropFirst(), sorted).map { $0 - $1 }
        let interval = abs(gaps.first ?? 5)
        switch anchorMode {
        case .firstRingIsDeadline:
            return sorted == (0..<sorted.count).map { $0 * max(interval, 1) }
        case .lastRingIsDeadline:
            return sorted == (0..<sorted.count).map { -((sorted.count - 1 - $0) * max(interval, 1)) }
        }
    }
}
