import SwiftUI
import AppKit

// Native Batteries table proportions, with the split keyboard in one extra row.
// No device-name, vendor, or product list lives in this view: glyph selection is
// supplied by Apple's BatteryCenterUI and may include internal SF symbols.
struct CombinedBatteryWidgetView: View {
    let report: BatteryReport?
    let sampledAt: Date?
    let devices: [SystemBatteryReading]
    var large: Bool = true
    var keyboardName: String? = nil

    var body: some View {
        GeometryReader { geometry in
            let slots = max(large ? 6 : 3, devices.count + 1)
            let rowHeight = geometry.size.height / Double(slots)
            VStack(spacing: 0) {
                ForEach(0..<slots, id: \.self) { index in
                    ZStack {
                        if index < devices.count {
                            deviceRow(devices[index], rowHeight: rowHeight)
                        } else if index == devices.count {
                            BatteryWidgetView(report: report, sampledAt: sampledAt,
                                              keyboardName: keyboardName, rowHeight: rowHeight)
                                .padding(.leading, 16)
                                .padding(.trailing, 20)
                        }
                    }
                    .frame(height: rowHeight)
                    .overlay(alignment: .bottom) {
                        if index < slots - 1 {
                            Rectangle().fill(Color.white.opacity(0.22))
                                .frame(height: 0.5).padding(.leading, 50)
                        }
                    }
                }
            }
        }
    }

    private func deviceRow(_ device: SystemBatteryReading, rowHeight: CGFloat) -> some View {
        HStack(spacing: 12) {
            glyph(device)
                .frame(width: 20, height: min(20, rowHeight))
                .frame(width: 22, height: min(22, rowHeight))
                .accessibilityHidden(true)
            Text(device.name).lineLimit(1)
            Spacer(minLength: 6)
            HStack(spacing: 8) {
                Text("\(device.percent)%")
                NativeBatteryGauge(percent: device.percent, charging: device.charging,
                    tint: device.lowPowerMode ? .yellow : device.lowBattery && !device.charging ? .red : .green)
            }
        }
        .font(.system(size: min(11, rowHeight * 0.45)))
        .foregroundStyle(.white)
        .padding(.leading, 16)
        .padding(.trailing, 20)
        .help(device.help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(device.help)
    }

    @ViewBuilder private func glyph(_ device: SystemBatteryReading) -> some View {
        if let png = device.glyphPNG, let image = NSImage(data: png) {
            Image(nsImage: image).renderingMode(.template).resizable().scaledToFit()
        } else {
            // Apple's table uses internal symbols too (not all are accepted
            // by the public systemName initializer). Preserve those glyphs.
            Image(_internalSystemName: device.glyph).resizable().scaledToFit()
        }
    }
}

struct NativeBatteryGauge: View {
    let percent: Int
    let charging: Bool
    let tint: Color
    var body: some View {
        if charging {
            Image(systemName: "battery.100percent.bolt")
                .resizable()
                .symbolRenderingMode(.palette)
                .foregroundStyle(tint, Color.white.opacity(0.65))
                // SF battery glyphs include alignment bearings. Normalize
                // their visible outline to the same 21×9 pt battery below.
                .frame(width: 21, height: 12)
                .offset(x: 2)
                .frame(width: 22, height: 12, alignment: .leading)
        } else {
            // Native list batteries show a continuous level, not 25% steps.
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2.5)
                    .strokeBorder(Color.white.opacity(0.65), lineWidth: 1)
                    .frame(width: 18.5, height: 9)
                RoundedRectangle(cornerRadius: 1)
                    .fill(tint).frame(width: 14.5 * Double(percent) / 100, height: 5)
                    .padding(.leading, 2)
                Capsule().fill(Color.white.opacity(0.65)).frame(width: 1.5, height: 3.5)
                    .offset(x: 19.5)
            }.frame(width: 22, height: 12)
        }
    }
}
