import Foundation

struct HalfReading {
    let flags: UInt8
    let percent: UInt8
    let millivolts: UInt16
    let age: UInt16
    let rssi: Int8
    let rssiAge: UInt16

    var connected: Bool { flags & 4 != 0 }
    var valid: Bool { flags & 1 != 0 && percent <= 100 }
    var usbPowered: Bool { flags & 2 != 0 }
    var current: Bool { connected && valid && age <= 90 }
    var signalCurrent: Bool { connected && flags & 8 != 0 && rssi != 127 && rssiAge <= 90 }

    var compact: String {
        guard connected else { return "—" }
        guard current else { return "?" }
        return "\(percent)%\(usbPowered ? "⚡" : "")"
    }

    var detail: String {
        guard connected else { return "Disconnected" }
        let level = current ? "\(percent)% · \(String(format: "%.2f", Double(millivolts) / 1000)) V"
                            : "Battery reading unavailable or stale"
        return level + " · " + (usbPowered ? "USB powered" : "On battery")
    }

    var signal: String {
        signalCurrent ? "\(rssi) dBm" : "Unavailable or stale"
    }
}

struct BatteryReport {
    let halves: [HalfReading]

    init?(_ bytes: [UInt8], reportID: Int = 1) {
        // macOS HID callbacks can provide the report ID separately.
        let packet = bytes.count == 19 && reportID == 1 ? [UInt8(1)] + bytes : bytes
        guard packet.count == 20, packet[0] == 1, packet[1] == 1 else { return nil }
        func word(_ offset: Int) -> UInt16 {
            UInt16(packet[offset]) | UInt16(packet[offset + 1]) << 8
        }
        var readings: [HalfReading] = []
        for side in 0..<2 {
            let start = 2 + side * 9
            let flags = packet[start]
            let percent = packet[start + 1]
            guard flags & 0xf0 == 0,
                  flags & 1 == 0 ? percent == 255 : percent <= 100 else { return nil }
            readings.append(HalfReading(flags: flags, percent: percent,
                                        millivolts: word(start + 2), age: word(start + 4),
                                        rssi: Int8(bitPattern: packet[start + 6]),
                                        rssiAge: word(start + 7)))
        }
        halves = readings
    }

    static let demoBytes: [UInt8] = [
        1, 1,
        15, 84, 0xca, 0x0f, 12, 0, 0xce, 2, 0,
        13, 62, 0x54, 0x0f, 8, 0, 0xb9, 2, 0,
    ]
}

func runReportTests() {
    func check(_ value: Bool, _ message: String) {
        if !value { fatalError(message) }
    }
    let bytes = BatteryReport.demoBytes
    let report = BatteryReport(bytes)!
    check(report.halves[0].compact == "84%⚡", "USB-powered left percentage")
    check(report.halves[1].compact == "62%", "Battery-powered right percentage")
    check(report.halves[0].rssi == -50 && report.halves[1].rssi == -71, "Signed RSSI")
    check(report.halves[0].millivolts == 4042, "Little-endian voltage")
    check(BatteryReport(Array(bytes.dropFirst())) != nil, "Separately supplied report ID")
    check(BatteryReport(Array(bytes.dropFirst()), reportID: 2) == nil, "Wrong report ID")
    check(BatteryReport(Array(bytes.dropLast())) == nil, "Truncated packet")
    var changed = bytes
    changed[1] = 2
    check(BatteryReport(changed) == nil, "Unknown protocol version")
    changed = bytes; changed[3] = 101
    check(BatteryReport(changed) == nil, "Invalid percentage")
    changed = bytes; changed[2] = 0x80
    check(BatteryReport(changed) == nil, "Unknown flags")
    changed = bytes; changed[3] = 0
    check(BatteryReport(changed)!.halves[0].compact == "0%⚡", "Empty battery is not unknown")
    changed = bytes; changed[2] = 11
    check(BatteryReport(changed)!.halves[0].compact == "—", "Disconnected hides last percentage")
    changed = bytes; changed[6] = 91
    check(BatteryReport(changed)!.halves[0].compact == "?", "Old sample is stale")
    changed = bytes; changed[9] = 91
    check(!BatteryReport(changed)!.halves[0].signalCurrent, "Old RSSI is stale")
    changed = bytes; changed[8] = 127
    check(!BatteryReport(changed)!.halves[0].signalCurrent, "Unavailable controller RSSI")
    changed = bytes; changed[2] = 4; changed[3] = 255
    check(!BatteryReport(changed)!.halves[0].valid, "No sample yet")
    print("Battery report tests passed")
}
