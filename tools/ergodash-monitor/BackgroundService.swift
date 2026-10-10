import Foundation

enum BackgroundService {
    static let label = "dev.andy.ergodash-usb-monitor.collector"
    static var domain: String { "gui/\(getuid())" }
    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }
    static var installed: Bool { FileManager.default.fileExists(atPath: plistURL.path) }

    @discardableResult private static func launchctl(_ arguments: [String], required: Bool = true) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let message = String(decoding: data, as: UTF8.self)
        if required && process.terminationStatus != 0 {
            throw NSError(domain: label, code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "Background service: \(message.trimmingCharacters(in: .whitespacesAndNewlines))"])
        }
        return message
    }

    static func install() throws {
        guard let executable = Bundle.main.executableURL,
              Bundle.main.bundleURL.deletingLastPathComponent().path == "/Applications" else {
            throw NSError(domain: label, code: 1, userInfo: [NSLocalizedDescriptionKey:
                "Move ErgoDash USB Monitor to Applications before installing the background service."])
        }
        let manager = FileManager.default
        try manager.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let logDirectory = manager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/ErgoDashUSB")
        try manager.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "Label": label, "ProgramArguments": [executable.path, "--background"],
            "RunAtLoad": true, "KeepAlive": true, "ThrottleInterval": 10,
            "ProcessType": "Background", "LimitLoadToSessionType": "Aqua",
            "StandardOutPath": logDirectory.appendingPathComponent("collector.log").path,
            "StandardErrorPath": logDirectory.appendingPathComponent("collector.log").path,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let previous = try? Data(contentsOf: plistURL)
        try launchctl(["bootout", "\(domain)/\(label)"], required: false)
        do {
            try data.write(to: plistURL, options: .atomic)
            try launchctl(["enable", "\(domain)/\(label)"])
            try launchctl(["bootstrap", domain, plistURL.path])
        } catch {
            if let previous = previous {
                try? previous.write(to: plistURL, options: .atomic)
                _ = try? launchctl(["bootstrap", domain, plistURL.path])
            } else { try? manager.removeItem(at: plistURL) }
            throw error
        }
    }

    static func uninstall() throws {
        try launchctl(["bootout", "\(domain)/\(label)"], required: false)
        if installed { try FileManager.default.removeItem(at: plistURL) }
    }
}
