import AppKit

enum Shell {
    private static let scriptQueue = DispatchQueue(label: "HomeWidgets.applescript", qos: .userInitiated)

    /// Single-quotes a string for safe use in a shell command.
    static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Starts a program without waiting for it.
    @discardableResult
    static func launch(_ path: String, _ arguments: [String] = []) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }

    /// Runs a program in the background and hands its output back on the main thread.
    static func output(_ path: String, _ arguments: [String], completion: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let text = String(data: data, encoding: .utf8)
            DispatchQueue.main.async { completion(text) }
        }
    }

    /// Runs AppleScript off the main thread. The completion runs on the main thread.
    static func appleScript(_ source: String, completion: ((NSAppleEventDescriptor?, String?) -> Void)? = nil) {
        scriptQueue.async {
            let (result, message) = runAppleScriptNow(source)
            if let completion {
                DispatchQueue.main.async { completion(result, message) }
            }
        }
    }

    /// Runs AppleScript on the current thread. Call only from a background queue.
    static func runAppleScriptNow(_ source: String) -> (NSAppleEventDescriptor?, String?) {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return (nil, "Invalid script") }
        let result = script.executeAndReturnError(&error)
        if let error {
            return (nil, error[NSAppleScript.errorMessage] as? String ?? "AppleScript error")
        }
        return (result, nil)
    }

    static func open(path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    static func openApp(at path: String) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: configuration, completionHandler: nil)
    }

    /// True when running from a proper .app bundle (needed for permission prompts).
    static var isBundled: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app")
    }

    static func hasUsageDescription(_ key: String) -> Bool {
        Bundle.main.object(forInfoDictionaryKey: key) != nil
    }

    static func openPrivacySettings(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
