import AppKit
import SwiftUI
import WidgetKit

final class SetupModel: ObservableObject {
    @Published var report: BatteryReport?
    @Published var receivedAt: Date?
    @Published var keyboardName: String?
    @Published var devices: [SystemBatteryReading] = []
    @Published var installed = BackgroundService.installed
    @Published var message = ""
    @Published var error: String?

    func update() {
        let snapshot = SnapshotStore.load(forExtension: false)
        report = snapshot?.freshReport()
        receivedAt = snapshot?.receivedAt
        keyboardName = snapshot?.keyboardName
        devices = snapshot?.systemBatteries?.freshDevices() ?? []
        installed = BackgroundService.installed
        if !installed { message = "Install the background service to collect readings automatically." }
        else if let report = report {
            let missing = report.halves.enumerated().filter { $0.element.connected && !$0.element.current }
                .map { $0.offset == 0 ? "Left" : "Right" }
            message = missing.isEmpty ? "Background service running. You can quit this setup app."
                : "\(missing.joined(separator: " and ")) connected, but battery readings are unavailable. Flash the corrected firmware to these halves."
        } else { message = "Waiting for the background service to publish current USB readings…" }
    }

    func install() {
        do { try BackgroundService.install(); error = nil; update() }
        catch { self.error = error.localizedDescription }
    }

    func uninstall() {
        do { try BackgroundService.uninstall(); error = nil; update() }
        catch { self.error = error.localizedDescription }
    }
}

struct SetupWindow: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ErgoDash Batteries Setup").font(.title2).fontWeight(.semibold)
            Text("Read both keyboard halves in the widgets sidebar in Notification Center.")
                .fixedSize(horizontal: false, vertical: true)
            BatteryWidgetView(report: model.report, sampledAt: model.receivedAt, keyboardName: model.keyboardName)
                .frame(height: 50)
            if !model.devices.isEmpty {
                Text(model.devices.map { "\($0.name): \($0.percent)%\($0.charging ? " (charging)" : "")" }.joined(separator: "\n"))
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
            }
            Text(model.error ?? model.message)
                .font(.callout).foregroundStyle(model.error == nil ? Color.secondary : Color.red)
                .fixedSize(horizontal: false, vertical: true)
            Button(model.installed ? "Reinstall background service" : "Install background service") { model.install() }
                .buttonStyle(.borderedProminent)
            Text("The service starts at login and restarts automatically if it exits. It has no window, Dock icon or menu bar item. You can close this setup app once installed.")
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            Text("Open Notification Center, choose Edit Widgets, search for ErgoDash, and add ErgoDash Batteries. Choose Large for the native Batteries table size. New accessories appear automatically when macOS reports their battery. macOS controls refresh timing.")
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            Text("The keyboard’s bolt means USB powered; those halves cannot report active charging. Other devices use macOS’s charging status. Keyboard percentage is estimated from voltage, and signal strength from RSSI.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Refresh widget") { WidgetCenter.shared.reloadTimelines(ofKind: WidgetConstants.kind) }
                if model.installed { Button("Uninstall service") { model.uninstall() } }
                Spacer()
                Button("Done") { NSApp.terminate(nil) }
            }
        }
        .padding(22).frame(width: 440)
    }
}

final class Setup: NSObject, NSApplicationDelegate {
    private let model = SetupModel()
    private var window: NSWindow!
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let menu = NSMenu()
        let item = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit ErgoDash Setup", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = appMenu
        menu.addItem(item)
        NSApp.mainMenu = menu
        window = NSWindow(contentViewController: NSHostingController(rootView: SetupWindow(model: model)))
        window.title = "ErgoDash Batteries Setup"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        model.update()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.model.update() }
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(openURL(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    @objc private func openURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetConstants.kind)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window.makeKeyAndOrderFront(nil)
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { timer?.invalidate() }
}

@MainActor func renderPreview(to path: String) throws {
    let inventory = ReadSystemBatteries().flatMap { try? JSONDecoder().decode(SystemBatteryInventory.self, from: $0) }
    let renderer = ImageRenderer(content:
        CombinedBatteryWidgetView(report: BatteryReport(BatteryReport.demoBytes), sampledAt: nil,
                                  devices: inventory?.validDevices ?? [.demo],
                                  keyboardName: SnapshotStore.load(forExtension: false)?.keyboardName)
            .frame(width: 344, height: 344)
            .environment(\.colorScheme, .dark)
            .background(Color.gray))
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
    runSystemBatteryTests()
} else if CommandLine.arguments.contains("--system-batteries") {
    guard let data = ReadSystemBatteries(), let inventory = try? JSONDecoder().decode(SystemBatteryInventory.self, from: data) else {
        throw NSError(domain: "SystemBatteries", code: 1)
    }
    print("Apple icon selection: \(inventory.nativeIcons)")
    for device in inventory.validDevices {
        print("\(device.name): \(device.percent)% · charging=\(device.charging) · glyph=\(device.glyph)")
    }
} else if CommandLine.arguments.contains("--install-service") {
    try BackgroundService.install()
    print("Background service installed for login")
} else if CommandLine.arguments.contains("--uninstall-service") {
    try BackgroundService.uninstall()
    print("Background service uninstalled")
} else if let index = CommandLine.arguments.firstIndex(of: "--render-preview"), CommandLine.arguments.count > index + 1 {
    try MainActor.assumeIsolated { try renderPreview(to: CommandLine.arguments[index + 1]) }
} else {
    let app = NSApplication.shared
    let delegate: NSApplicationDelegate = CommandLine.arguments.contains("--background") ? USBCollector() : Setup()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
