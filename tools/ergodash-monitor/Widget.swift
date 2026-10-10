import SwiftUI
import WidgetKit

struct BatteryEntry: TimelineEntry {
    let date: Date
    let report: BatteryReport?
    let receivedAt: Date?
}

struct BatteryProvider: TimelineProvider {
    func placeholder(in context: Context) -> BatteryEntry {
        BatteryEntry(date: Date(), report: BatteryReport(BatteryReport.demoBytes), receivedAt: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (BatteryEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BatteryEntry>) -> Void) {
        completion(Timeline(entries: [current()], policy: .after(Date().addingTimeInterval(300))))
    }

    private func current() -> BatteryEntry {
        let snapshot = SnapshotStore.load(forExtension: true)
        return BatteryEntry(date: Date(), report: snapshot?.freshReport(), receivedAt: snapshot?.receivedAt)
    }
}

@main struct ErgoDashBatteryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetConstants.kind, provider: BatteryProvider()) { entry in
            BatteryWidgetView(report: entry.report, sampledAt: entry.receivedAt)
                .containerBackground(.regularMaterial, for: .widget)
                .widgetURL(URL(string: "ergodash-monitor://show"))
        }
        .configurationDisplayName("ErgoDash Batteries")
        .description("Left and right keyboard battery levels and signal strength over USB.")
        .supportedFamilies([.systemMedium])
    }
}
