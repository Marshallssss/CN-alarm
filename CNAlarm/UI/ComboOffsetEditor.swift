import SwiftUI

struct ComboOffsetEditor: View {
    var anchorMode: ComboAnchorMode
    @Binding var offsets: [Int]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            compactStepper(title: "响铃次数", valueText: "\(ringCount) 次", binding: ringCountBinding, range: 1...8)
            compactStepper(title: "每次间隔", valueText: "\(intervalMinutes) 分钟", binding: intervalBinding, range: 1...30)
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear {
            if offsets.isEmpty {
                rebuild(count: 3, interval: 5)
            }
        }
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

    private var summary: String {
        switch anchorMode {
        case .firstRingIsDeadline:
            return "从目标时间开始，每 \(intervalMinutes) 分钟响一次，共 \(ringCount) 次。"
        case .lastRingIsDeadline:
            let lead = max(ringCount - 1, 0) * intervalMinutes
            return "从目标时间前 \(lead) 分钟开始，每 \(intervalMinutes) 分钟响一次，最后一次是目标时间。"
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
}
