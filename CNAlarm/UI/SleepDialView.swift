import SwiftUI

struct SleepDialView: View {
    var bedtime: ClockTime
    var wakeTime: ClockTime

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let radius = size / 2 - 22
            ZStack {
                Circle()
                    .stroke(Color.black.opacity(0.16), lineWidth: 28)
                Circle()
                    .trim(from: trimStart, to: trimEnd)
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 28, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                ForEach(Array(stride(from: 0, through: 22, by: 2)), id: \.self) { hour in
                    Text("\(hour)")
                        .font(.caption)
                        .foregroundStyle(hour == 0 || hour == 6 || hour == 12 || hour == 18 ? .primary : .secondary)
                        .position(position(for: hour, radius: radius, size: size))
                }
                VStack(spacing: 8) {
                    Image(systemName: "moon.fill")
                        .foregroundStyle(.indigo)
                    Text(durationText)
                        .font(.title2.bold())
                    Image(systemName: "sun.max.fill")
                        .foregroundStyle(.yellow)
                }
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var trimStart: CGFloat {
        CGFloat(bedtime.minutesFromMidnight) / 1440
    }

    private var trimEnd: CGFloat {
        let wake = CGFloat(wakeTime.minutesFromMidnight) / 1440
        return wake <= trimStart ? wake + 1 : wake
    }

    private var durationText: String {
        let diff = (wakeTime.minutesFromMidnight - bedtime.minutesFromMidnight + 1440) % 1440
        return "\(diff / 60)小时"
    }

    private func position(for hour: Int, radius: CGFloat, size: CGFloat) -> CGPoint {
        let angle = (Double(hour) / 24.0 * 360.0 - 90.0) * .pi / 180
        return CGPoint(
            x: size / 2 + cos(angle) * radius,
            y: size / 2 + sin(angle) * radius
        )
    }
}
