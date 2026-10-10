import AppKit
import IOKit.hid

final class Monitor: NSObject, NSApplicationDelegate {
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    private var device: IOHIDDevice?
    private var status: NSStatusItem!
    private var report: BatteryReport?
    private var receivedAt: Date?
    private var timer: Timer?
    private var ticks = 0
    private let demo = CommandLine.arguments.contains("--demo")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if demo {
            report = BatteryReport(BatteryReport.demoBytes)
            receivedAt = Date()
        } else {
            let match: [String: Any] = [
                kIOHIDVendorIDKey: 0x1d50,
                kIOHIDProductIDKey: 0x615e,
                kIOHIDDeviceUsagePageKey: 0xff60,
                kIOHIDDeviceUsageKey: 0x61,
            ]
            IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)
            let context = Unmanaged.passUnretained(self).toOpaque()
            IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, result, sender, device in
                guard let context = context, result == kIOReturnSuccess else { return }
                Unmanaged<Monitor>.fromOpaque(context).takeUnretainedValue().connected(device)
            }, context)
            IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, result, sender, device in
                guard let context = context else { return }
                Unmanaged<Monitor>.fromOpaque(context).takeUnretainedValue().removed(device)
            }, context)
            IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            if result != kIOReturnSuccess {
                status.button?.toolTip = "Could not open USB HID monitor: \(result)"
            }
        }
        redraw()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.ticks += 1
            if self.demo { self.receivedAt = Date() }
            if self.ticks % 5 == 0 { self.readSnapshot() }
            self.redraw()
        }
    }

    private func connected(_ found: IOHIDDevice) {
        guard device == nil else { return }
        device = found
        IOHIDDeviceRegisterInputReportCallback(found, buffer, 64, { context, result, sender, type, id, bytes, count in
            guard let context = context, result == kIOReturnSuccess else { return }
            Unmanaged<Monitor>.fromOpaque(context).takeUnretainedValue()
                .accept(Array(UnsafeBufferPointer(start: bytes, count: count)), id: Int(id))
        }, Unmanaged.passUnretained(self).toOpaque())
        readSnapshot()
        redraw()
    }

    private func removed(_ gone: IOHIDDevice) {
        guard let active = device, CFEqual(active, gone) else { return }
        IOHIDDeviceRegisterInputReportCallback(gone, buffer, 64, nil, nil)
        device = nil
        report = nil
        receivedAt = nil
        redraw()
    }

    private func readSnapshot() {
        guard let device = device else { return }
        var bytes = [UInt8](repeating: 0, count: 20)
        var count = bytes.count
        let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &bytes, &count)
        if result == kIOReturnSuccess && count >= 0 && count <= bytes.count {
            accept(Array(bytes.prefix(count)), id: 1)
        }
    }

    private func accept(_ bytes: [UInt8], id: Int) {
        guard let parsed = BatteryReport(bytes, reportID: id) else { return }
        report = parsed
        receivedAt = Date()
        redraw()
    }

    private func redraw() {
        let fresh = receivedAt.map { Date().timeIntervalSince($0) <= 10 } ?? false
        let readings = fresh ? report?.halves : nil
        status.button?.title = readings.map { "⌨ L \($0[0].compact)  R \($0[1].compact)" } ?? "⌨ ErgoDash —"
        status.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        let menu = NSMenu()
        func line(_ title: String) { menu.addItem(NSMenuItem(title: title, action: nil, keyEquivalent: "")) }
        line(demo ? "ErgoDash USB Monitor · Demo" : "ErgoDash USB Monitor")
        menu.addItem(.separator())
        if let readings = readings {
            for side in 0..<2 {
                let name = side == 0 ? "Left" : "Right"
                line("\(name): \(readings[side].detail)")
                line("\(name) signal at dongle: \(readings[side].signal)")
                if readings[side].connected && readings[side].valid {
                    line("Battery sample: \(readings[side].age) seconds ago")
                }
                menu.addItem(.separator())
            }
        } else {
            line(device == nil ? "Connect the dongle with USB monitor firmware" : "Waiting for USB telemetry…")
            menu.addItem(.separator())
        }
        line("⚡ means USB power detected; charge state is unavailable.")
        line("Battery % is estimated from voltage, including while charging.")
        line("RSSI: values closer to 0 mean a stronger signal.")
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        status.menu = menu
    }

    @objc private func quitApp() { NSApp.terminate(nil) }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        if let device = device { IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, nil, nil) }
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        buffer.deallocate()
    }
}

if CommandLine.arguments.contains("--self-test") {
    runReportTests()
} else {
    let app = NSApplication.shared
    let monitor = Monitor()
    app.delegate = monitor
    app.run()
}
