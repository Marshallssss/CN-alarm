import SwiftUI

struct WheelTimePicker: View {
    @Binding var hour: Int
    @Binding var minute: Int
    var fontSize: CGFloat = 28
    var pickerHeight: CGFloat = 170

    var body: some View {
        HStack(spacing: 0) {
            Picker("小时", selection: $hour) {
                ForEach(0..<24, id: \.self) { value in
                    Text(String(format: "%02d", value))
                        .font(.system(size: fontSize, weight: .regular, design: .rounded))
                        .monospacedDigit()
                        .tag(value)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            .clipped()

            Text(":")
                .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .accessibilityHidden(true)

            Picker("分钟", selection: $minute) {
                ForEach(0..<60, id: \.self) { value in
                    Text(String(format: "%02d", value))
                        .font(.system(size: fontSize, weight: .regular, design: .rounded))
                        .monospacedDigit()
                        .tag(value)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            .clipped()
        }
        .frame(height: pickerHeight)
        .accessibilityElement(children: .contain)
    }
}
