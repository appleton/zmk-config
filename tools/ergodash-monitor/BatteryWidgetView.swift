import SwiftUI

struct BatteryWidgetView: View {
    let report: BatteryReport?
    var sampledAt: Date? = nil

    var body: some View {
        HStack(spacing: 14) {
            halfCell(side: 0)
            Divider().frame(height: 22)
            halfCell(side: 1)
        }
        .font(.system(size: 11))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private func halfCell(side: Int) -> some View {
        let name = side == 0 ? "Left" : "Right"
        let reading = report?.halves[side]
        let batteryCurrent = reading?.current == true
        let signalPercent = reading?.signalPercent
        let timestamp = sampledAt.map { " · Updated \($0.formatted(date: .omitted, time: .standard))" } ?? ""
        HStack(spacing: 5) {
            Text(name).fontWeight(.medium).foregroundStyle(.primary)
            Spacer(minLength: 0)
            Image(systemName: signalPercent == nil ? "wifi.slash" : "wifi",
                  variableValue: signalPercent.map { Double($0) / 100 } ?? 0)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(signalPercent == nil ? .secondary : .primary)
                .frame(width: 17, height: 22)
                .help((reading?.signalTooltip ?? "Signal unavailable") + timestamp)
                .accessibilityLabel("\(name) signal")
                .accessibilityValue(reading?.signalTooltip ?? "Unavailable")
            HStack(spacing: 3) {
                Text(batteryCurrent ? "\(reading!.percent)%" : "—")
                    .monospacedDigit()
                    .foregroundStyle(batteryCurrent ? .primary : .secondary)
                Image(systemName: reading?.batterySymbol ?? "battery.0percent")
                    .font(.system(size: 16))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(batteryTint(reading), Color.primary.opacity(0.6))
                    .frame(width: 26, height: 22)
            }
                .help((reading?.batteryTooltip ?? "Battery unavailable") + timestamp)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(name) battery")
                .accessibilityValue(reading?.batteryTooltip ?? "Unavailable")
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private func batteryTint(_ reading: HalfReading?) -> Color {
        guard let reading = reading, reading.current else { return .secondary }
        return reading.percent <= 20 && !reading.usbPowered ? .red : .green
    }
}
