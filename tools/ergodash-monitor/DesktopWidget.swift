import AppKit
import SwiftUI

struct CompactBatteryView: View {
    @ObservedObject var model: MonitorModel

    var body: some View {
        BatteryWidgetView(report: model.report, sampledAt: model.receivedAt)
            .padding(.horizontal, 16)
            .frame(width: 344, height: 82)
    }
}

private final class DesktopPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class DraggableBatteryView: NSHostingView<CompactBatteryView> {
    override var mouseDownCanMoveWindow: Bool { true }
}

final class DesktopWidget {
    private let panel: NSPanel

    init(model: MonitorModel) {
        panel = DesktopPanel(contentRect: NSRect(x: 0, y: 0, width: 344, height: 82),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "ErgoDash Compact Widget"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = false
        panel.isMovableByWindowBackground = true
        panel.isExcludedFromWindowsMenu = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)

        // A real backdrop material, rather than an opaque widget fill. AppKit
        // composites the wallpaper underneath and adapts to light/dark mode.
        let backdrop = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 344, height: 82))
        backdrop.material = .popover
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        backdrop.wantsLayer = true
        backdrop.layer?.cornerRadius = 22
        backdrop.layer?.masksToBounds = true
        let content = DraggableBatteryView(rootView: CompactBatteryView(model: model))
        content.frame = backdrop.bounds
        content.autoresizingMask = [.width, .height]
        backdrop.addSubview(content)
        panel.contentView = backdrop

        if !panel.setFrameUsingName("ErgoDashCompactWidget"), let screen = NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: visible.maxX - 364, y: visible.maxY - 102))
        }
        // Restore only position: always preserve the requested half-height size.
        panel.setContentSize(NSSize(width: 344, height: 82))
        panel.setFrameAutosaveName("ErgoDashCompactWidget")
    }

    func setVisible(_ visible: Bool) {
        guard visible != panel.isVisible else { return }
        if visible { panel.orderFront(nil) } else { panel.orderOut(nil) }
    }

    func close() { panel.close() }
}
