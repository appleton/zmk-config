import Foundation

enum WidgetConstants {
    static let kind = "ErgoDashBatteryWidget"
    static let extensionID = "dev.andy.ergodash-usb-monitor.widget"
}

struct WidgetSnapshot: Codable {
    let version: Int
    let bytes: [UInt8]
    let receivedAt: Date

    init(bytes: [UInt8], receivedAt: Date = Date()) {
        self.version = 1
        self.bytes = bytes.count == 19 ? [1] + bytes : bytes
        self.receivedAt = receivedAt
    }

    var report: BatteryReport? { version == 1 ? BatteryReport(bytes) : nil }

    func freshReport(at date: Date = Date()) -> BatteryReport? {
        let elapsed = date.timeIntervalSince(receivedAt)
        guard elapsed >= -5, elapsed <= 10, report != nil else { return nil }
        var aged = bytes
        for side in 0..<2 {
            let start = 2 + side * 9
            for offset in [4, 7] {
                let old = Int(aged[start + offset]) | Int(aged[start + offset + 1]) << 8
                let age = min(65535, old + max(0, Int(elapsed)))
                aged[start + offset] = UInt8(age & 255)
                aged[start + offset + 1] = UInt8(age >> 8)
            }
        }
        return BatteryReport(aged)
    }

    static var demo: WidgetSnapshot { WidgetSnapshot(bytes: BatteryReport.demoBytes) }
    static var disconnected: WidgetSnapshot {
        WidgetSnapshot(bytes: [1, 1, 0, 255, 0, 0, 255, 255, 127, 255, 255,
                              0, 255, 0, 0, 255, 255, 127, 255, 255])
    }
}

enum SnapshotStore {
    static func url(forExtension: Bool) -> URL {
        // Local ad-hoc build: the nonsandboxed USB collector writes only this
        // extension's telemetry file. The widget reads its own sandbox container.
        let support: URL
        if forExtension {
            support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        } else {
            support = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Containers/\(WidgetConstants.extensionID)/Data/Library/Application Support")
        }
        return support.appendingPathComponent("ErgoDashUSB/snapshot.json")
    }

    static func save(_ snapshot: WidgetSnapshot) throws {
        let path = url(forExtension: false)
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: path, options: .atomic)
    }

    static func load(forExtension: Bool) -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: url(forExtension: forExtension)), data.count < 4096,
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data),
              snapshot.report != nil else { return nil }
        return snapshot
    }
}

func runSnapshotTests() {
    let time = Date(timeIntervalSince1970: 1000)
    let snapshot = WidgetSnapshot(bytes: BatteryReport.demoBytes, receivedAt: time)
    precondition(snapshot.freshReport(at: time.addingTimeInterval(5))?.halves[0].age == 17)
    precondition(snapshot.freshReport(at: time.addingTimeInterval(11)) == nil)
    precondition(snapshot.freshReport(at: time.addingTimeInterval(-6)) == nil)
    let decoded = try! JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(snapshot))
    precondition(decoded.bytes == snapshot.bytes && decoded.receivedAt == time)
    let malformed = WidgetSnapshot(bytes: [1, 2], receivedAt: time)
    precondition(malformed.report == nil && malformed.freshReport(at: time) == nil)
    precondition(WidgetSnapshot.disconnected.report?.halves[0].compact == "—")
    print("Widget snapshot tests passed")
}
