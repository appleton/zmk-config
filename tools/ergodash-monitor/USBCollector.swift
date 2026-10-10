import AppKit
import IOKit.hid
import WidgetKit

// launchd owns this process. It has no window, Dock icon or menu bar item.
final class USBCollector: NSObject, NSApplicationDelegate {
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    private var device: IOHIDDevice?
    private var snapshot: WidgetSnapshot?
    private var timer: Timer?
    private var lastReload = Date.distantPast
    private var publishedSignature = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.prohibited)
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(openSetup(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
        let match: [String: Any] = [
            kIOHIDVendorIDKey: 0x1d50, kIOHIDProductIDKey: 0x615e,
            kIOHIDDeviceUsagePageKey: 0xff60, kIOHIDDeviceUsageKey: 0x61,
        ]
        IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, result, sender, device in
            guard let context = context, result == kIOReturnSuccess else { return }
            Unmanaged<USBCollector>.fromOpaque(context).takeUnretainedValue().connected(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, result, sender, device in
            guard let context = context else { return }
            Unmanaged<USBCollector>.fromOpaque(context).takeUnretainedValue().removed(device)
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess {
            NSLog("USB access failed: %d", result)
        }
        publish(forceReload: true)
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.readSnapshot()
            self?.publish()
        }
    }

    // Opening the app/widget while collection is running opens setup separately.
    // The launchd-owned collector must keep running when that window closes.
    private func showSetup() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
    }

    @objc private func openSetup(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) { showSetup() }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSetup()
        return false
    }

    private func connected(_ found: IOHIDDevice) {
        guard device == nil else { return }
        device = found
        IOHIDDeviceRegisterInputReportCallback(found, buffer, 64, { context, result, sender, type, id, bytes, count in
            guard let context = context, result == kIOReturnSuccess else { return }
            Unmanaged<USBCollector>.fromOpaque(context).takeUnretainedValue()
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
    }

    private func publish(forceReload: Bool = false) {
        do { try SnapshotStore.save(snapshot ?? .disconnected) }
        catch { NSLog("Could not share widget readings: %@", error.localizedDescription); return }
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

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        // Publish offline when the collector is intentionally stopped.
        try? SnapshotStore.save(.disconnected)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetConstants.kind)
        if let device = device { IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, nil, nil) }
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        buffer.deallocate()
    }
}
