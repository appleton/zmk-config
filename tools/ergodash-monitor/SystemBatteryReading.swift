import Foundation

struct SystemBatteryReading: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let percent: Int
    let charging: Bool
    let lowBattery: Bool
    let lowPowerMode: Bool
    let internalBattery: Bool
    let glyph: String
    var glyphPNG: Data? = nil

    var batterySymbol: String {
        if charging { return "battery.100percent.bolt" }
        switch percent {
        case 0..<13: return "battery.0percent"
        case 13..<38: return "battery.25percent"
        case 38..<63: return "battery.50percent"
        case 63..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
    var help: String { "\(name): \(percent)% · \(charging ? "Charging" : percent == 100 ? "Charged" : "On battery")" }

    static let demo = SystemBatteryReading(id: "demo-mac", name: "MacBook Pro", percent: 100,
        charging: false, lowBattery: false, lowPowerMode: false, internalBattery: true, glyph: "laptopcomputer")
}

struct SystemBatteryInventory: Codable {
    let devices: [SystemBatteryReading]
    let nativeIcons: Bool

    // Validate external OS data once, before it enters the widget archive.
    var validDevices: [SystemBatteryReading] {
        var seen = Set<String>()
        return devices.filter { !$0.id.isEmpty && !$0.name.isEmpty && (0...100).contains($0.percent) && seen.insert($0.id).inserted }
    }
}

struct SystemBatterySnapshot: Codable {
    let devices: [SystemBatteryReading]
    let nativeIcons: Bool
    let receivedAt: Date

    init(inventory: SystemBatteryInventory, receivedAt: Date = Date()) {
        devices = inventory.validDevices
        nativeIcons = inventory.nativeIcons
        self.receivedAt = receivedAt
    }
    func freshDevices(at date: Date = Date()) -> [SystemBatteryReading] {
        let age = date.timeIntervalSince(receivedAt)
        return age >= -5 && age <= 30 ? devices : []
    }
}

func runSystemBatteryTests() {
    let fixture = """
    {"nativeIcons":true,"devices":[
      {"id":"mac","name":"MacBook Pro","percent":100,"charging":false,"lowBattery":false,"lowPowerMode":false,"internalBattery":true,"glyph":"laptopcomputer"},
      {"id":"future","name":"Previously unseen accessory","percent":42,"charging":true,"lowBattery":false,"lowPowerMode":false,"internalBattery":false,"glyph":"future.os.symbol"},
      {"id":"case","name":"Headphones Case","percent":93,"charging":false,"lowBattery":false,"lowPowerMode":false,"internalBattery":false,"glyph":"earbuds.case.fill"}
    ]}
    """
    let inventory = try! JSONDecoder().decode(SystemBatteryInventory.self, from: Data(fixture.utf8))
    let time = Date(timeIntervalSince1970: 1000)
    let snapshot = SystemBatterySnapshot(inventory: inventory, receivedAt: time)
    precondition(snapshot.devices.count == 3 && snapshot.devices[1].glyph == "future.os.symbol")
    precondition(snapshot.devices[1].batterySymbol.contains("bolt"))
    precondition(snapshot.freshDevices(at: time.addingTimeInterval(31)).isEmpty)
    let roundTrip = try! JSONDecoder().decode(SystemBatterySnapshot.self, from: JSONEncoder().encode(snapshot))
    precondition(roundTrip.devices == snapshot.devices)
    let duplicate = SystemBatteryInventory(devices: inventory.devices + inventory.devices, nativeIcons: true)
    precondition(duplicate.validDevices.count == 3)
    let removed = SystemBatterySnapshot(inventory: SystemBatteryInventory(devices: [.demo], nativeIcons: true), receivedAt: time)
    precondition(removed.devices.count == 1) // Replacement removes disconnected accessories.
    let many = (0..<20).map { index in SystemBatteryReading(id: "device-\(index)", name: "Device \(index)", percent: index * 5,
        charging: false, lowBattery: false, lowPowerMode: false, internalBattery: false, glyph: "bluetooth") }
    precondition(SystemBatteryInventory(devices: many, nativeIcons: true).validDevices.count == 20)
    print("System battery inventory tests passed")
}
