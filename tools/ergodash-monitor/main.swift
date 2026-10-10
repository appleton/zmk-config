import AppKit
import SwiftUI
import IOKit.hid
import WidgetKit

final class MonitorModel: ObservableObject {
    @Published var report: BatteryReport?
    @Published var message = "Connect the dongle with USB monitor firmware."
    @Published var receivedAt: Date?
    @Published var error: String?
    @Published var showCompactWidget = true
}

struct MonitorWindow: View {
    @ObservedObject var model: MonitorModel
    let demo: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            BatteryWidgetView(report: model.report, sampledAt: model.receivedAt)
                .padding(16).frame(height: 82)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
            Text(model.error ?? (demo ? "Preview data" : model.message))
                .font(.callout).foregroundStyle(model.error == nil ? Color.secondary : Color.red)
            Text("Add “ErgoDash Batteries” from Edit Widgets on your desktop or in Notification Center. Keep this companion app running to collect USB readings; closing this window keeps collection running.")
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            Text("The bolt means USB powered; active charging cannot be detected. Signal percentage is an estimate from RSSI. macOS controls widget refresh timing.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Toggle("Show compact desktop widget", isOn: $model.showCompactWidget)
            Text("Drag the compact card to place it on your desktop. It updates live and is half the height of the native gallery widget.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Refresh widget") { WidgetCenter.shared.reloadTimelines(ofKind: WidgetConstants.kind) }
                Spacer()
                Button("Quit collector") { NSApp.terminate(nil) }
            }
        }
        .padding(22).frame(width: 410)
    }
}

final class Monitor: NSObject, NSApplicationDelegate {
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    private var device: IOHIDDevice?
    private let model = MonitorModel()
    private var window: NSWindow!
    private var desktopWidget: DesktopWidget?
    private var snapshot: WidgetSnapshot?
    private var timer: Timer?
    private var ticks = 0
    private var lastReload = Date.distantPast
    private var publishedSignature = ""
    private var usbError: String?
    private let demo = CommandLine.arguments.contains("--demo")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit ErgoDash Batteries", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        NSApp.mainMenu = menu
        window = NSWindow(contentViewController: NSHostingController(rootView: MonitorWindow(model: model, demo: demo)))
        window.title = "ErgoDash Batteries"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        model.showCompactWidget = UserDefaults.standard.object(forKey: "showCompactWidget") as? Bool ?? true
        desktopWidget = DesktopWidget(model: model)
        desktopWidget?.setVisible(model.showCompactWidget)
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(openURL(_:reply:)),
                                                     forEventClass: AEEventClass(kInternetEventClass),
                                                     andEventID: AEEventID(kAEGetURL))
        if demo {
            // Preview data is never published to the real widget.
            snapshot = .demo
        } else {
            let match: [String: Any] = [
                kIOHIDVendorIDKey: 0x1d50, kIOHIDProductIDKey: 0x615e,
                kIOHIDDeviceUsagePageKey: 0xff60, kIOHIDDeviceUsageKey: 0x61,
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
                usbError = "USB access failed (\(result))."
                model.error = usbError
            }
        }
        updateDisplay()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.ticks += 1
            if self.demo { self.snapshot = .demo }
            if self.ticks % 5 == 0 { self.readSnapshot(); self.publish() }
            self.updateDisplay()
        }
    }

    @objc private func openURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        readSnapshot()
        publish(forceReload: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window.makeKeyAndOrderFront(nil)
        return true
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
        publish(forceReload: true)
    }

    private func removed(_ gone: IOHIDDevice) {
        guard let active = device, CFEqual(active, gone) else { return }
        IOHIDDeviceRegisterInputReportCallback(gone, buffer, 64, nil, nil)
        device = nil
        snapshot = nil
        publish(forceReload: true)
        updateDisplay()
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
        guard BatteryReport(bytes, reportID: id) != nil else { return }
        snapshot = WidgetSnapshot(bytes: bytes)
        updateDisplay()
    }

    private func publish(forceReload: Bool = false) {
        guard !demo else { return }
        do { try SnapshotStore.save(snapshot ?? .disconnected); model.error = usbError }
        catch { model.error = "Could not share widget readings: \(error.localizedDescription)"; return }
        let report = snapshot?.freshReport()
        let signature = report?.halves.map { "\($0.connected)-\($0.usbPowered)-\($0.current)-\($0.percent)" }
            .joined(separator: "|") ?? "offline"
        // Request reloads on battery/power/connection changes. Steady readings
        // refresh at most every five minutes; macOS applies its own budget.
        if forceReload || signature != publishedSignature || Date().timeIntervalSince(lastReload) >= 300 {
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetConstants.kind)
            publishedSignature = signature
            lastReload = Date()
        }
    }

    private func updateDisplay() {
        desktopWidget?.setVisible(model.showCompactWidget)
        UserDefaults.standard.set(model.showCompactWidget, forKey: "showCompactWidget")
        model.report = snapshot?.freshReport()
        model.receivedAt = snapshot?.receivedAt
        if let report = model.report {
            let missing = report.halves.enumerated().filter { $0.element.connected && !$0.element.current }
                .map { $0.offset == 0 ? "Left" : "Right" }
            model.message = missing.isEmpty
                ? "USB collector running. Hover the signal icons for percentage and dBm."
                : "\(missing.joined(separator: " and ")) connected, but battery readings are unavailable. Install the corrected battery firmware on these halves."
        } else if device == nil {
            model.message = "Connect the dongle with USB monitor firmware."
        } else {
            model.message = "Waiting for current USB readings…"
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        desktopWidget?.close()
        // Publish offline when the collector is intentionally stopped.
        if !demo {
            try? SnapshotStore.save(.disconnected)
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetConstants.kind)
        }
        if let device = device { IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, nil, nil) }
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        buffer.deallocate()
    }
}

@MainActor func renderPreview(to path: String) throws {
    let renderer = ImageRenderer(content:
        BatteryWidgetView(report: BatteryReport(BatteryReport.demoBytes))
            .padding(16).frame(width: 344, height: 82)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
            .environment(\.colorScheme, .light))
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "Preview", code: 1)
    }
    try png.write(to: URL(fileURLWithPath: path))
}

if CommandLine.arguments.contains("--self-test") {
    runReportTests()
    runSnapshotTests()
} else if CommandLine.arguments.contains("--check-symbols") {
    for symbol in ["wifi", "wifi.slash", "battery.0percent", "battery.25percent", "battery.50percent",
                   "battery.75percent", "battery.100percent", "battery.100percent.bolt"] {
        precondition(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil, "Missing SF Symbol: \(symbol)")
    }
    print("SF Symbols available")
} else if let index = CommandLine.arguments.firstIndex(of: "--render-preview"), CommandLine.arguments.count > index + 1 {
    try MainActor.assumeIsolated { try renderPreview(to: CommandLine.arguments[index + 1]) }
} else {
    let app = NSApplication.shared
    let monitor = Monitor()
    app.delegate = monitor
    app.run()
}
