import SwiftUI

struct BatteryWidgetView: View {
    let report: BatteryReport?
    var sampledAt: Date? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "keyboard")
                .resizable().scaledToFit()
                .frame(width: 20, height: 20)
                .frame(width: 22, height: 22)
                .foregroundStyle(.primary)
                .accessibilityHidden(true)
            Text("Ergodash").foregroundStyle(.primary)
            Spacer(minLength: 6)
            HStack(spacing: 10) {
                halfCell(side: 0)
                // Match the table separators without the system Divider's
                // appearance-dependent color in the widget host.
                Rectangle().fill(Color.white.opacity(0.22))
                    .frame(width: 0.5, height: 22)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                halfCell(side: 1)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .font(.system(size: 11))
        .lineLimit(1)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private func halfCell(side: Int) -> some View {
        let name = side == 0 ? "Left" : "Right"
        let reading = report?.halves[side]
        let batteryCurrent = reading?.current == true
        let signalPercent = reading?.signalPercent
        let timestamp = sampledAt.map { " · Updated \($0.formatted(date: .omitted, time: .standard))" } ?? ""
        HStack(spacing: 5) {
            // Give the signal its own widget interaction region. Keep help on
            // the Link itself, rather than only its archived image label.
            Link(destination: URL(string: "ergodash-monitor://show")!) {
                Image(systemName: signalPercent == nil ? "wifi.slash" : "wifi",
                      variableValue: signalPercent.map { Double($0) / 100 } ?? 0)
                    .font(.system(size: 10))
                    .foregroundStyle(signalPercent == nil ? .secondary : .primary)
                    .frame(width: 14, height: 12)
                    .contentShape(Rectangle())
            }
                .buttonStyle(.plain)
                .help("\(name) · " + (reading?.signalTooltip ?? "Signal unavailable"))
                .accessibilityLabel("\(name) signal")
                .accessibilityValue(reading?.signalTooltip ?? "Unavailable")
            HStack(spacing: 6) {
                Text(batteryCurrent ? "\(reading!.percent)%" : "—")
                    .monospacedDigit()
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(batteryCurrent ? .primary : .secondary)
                NativeBatteryGauge(percent: batteryCurrent ? Int(reading!.percent) : 0,
                    charging: batteryCurrent && reading?.usbPowered == true,
                    tint: batteryTint(reading))
            }
                .help((reading?.batteryTooltip ?? "Battery unavailable") + timestamp)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(name) battery")
                .accessibilityValue(reading?.batteryTooltip ?? "Unavailable")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(name) keyboard half")
    }

    private func batteryTint(_ reading: HalfReading?) -> Color {
        guard let reading = reading, reading.current else { return .secondary }
        return reading.percent <= 20 && !reading.usbPowered ? .red : .green
    }
}
