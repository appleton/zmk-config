import SwiftUI
import WidgetKit

struct BatteryEntry: TimelineEntry {
    let date: Date
    let report: BatteryReport?
    let receivedAt: Date?
    let devices: [SystemBatteryReading]
    var keyboardName: String? = nil
}

struct BatteryProvider: TimelineProvider {
    func placeholder(in context: Context) -> BatteryEntry {
        BatteryEntry(date: Date(), report: BatteryReport(BatteryReport.demoBytes), receivedAt: nil, devices: [.demo])
    }

    func getSnapshot(in context: Context, completion: @escaping (BatteryEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BatteryEntry>) -> Void) {
        completion(Timeline(entries: [current()], policy: .after(Date().addingTimeInterval(300))))
    }

    private func current() -> BatteryEntry {
        let snapshot = SnapshotStore.load(forExtension: true)
        return BatteryEntry(date: Date(), report: snapshot?.freshReport(), receivedAt: snapshot?.receivedAt,
                            devices: snapshot?.systemBatteries?.freshDevices() ?? [], keyboardName: snapshot?.keyboardName)
    }
}

@main struct ErgoDashBatteryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetConstants.kind, provider: BatteryProvider()) { entry in
            CombinedWidgetContent(entry: entry)
                .environment(\.colorScheme, .dark)
                .containerBackground(for: .widget) { Color.clear }
                .widgetURL(URL(string: "ergodash-monitor://show"))
        }
        .configurationDisplayName("ErgoDash Batteries")
        .description("Mac and connected accessory batteries, plus both ErgoDash halves over USB.")
        .supportedFamilies([.systemMedium, .systemLarge])
        .contentMarginsDisabled()
        .containerBackgroundRemovable(true)
        // Match the host backdrop used by Apple's Batteries widget. A glass
        // view inside containerBackground leaves the host's opaque fill intact.
        .preferredBackgroundStyle(.blur)
    }
}

private struct CombinedWidgetContent: View {
    let entry: BatteryEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        CombinedBatteryWidgetView(report: entry.report, sampledAt: entry.receivedAt,
                                  devices: entry.devices, large: family == .systemLarge, keyboardName: entry.keyboardName)
    }
}
