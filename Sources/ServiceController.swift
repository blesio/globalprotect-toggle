import Foundation

struct CommandResult {
    let status: Int32
    let output: String
}

struct Agent {
    let label: String
    var plist: String { "/Library/LaunchAgents/\(label).plist" }
}

struct ServiceState {
    let loaded: [Bool]
    var active: Bool { loaded.contains(true) }
    var fullyActive: Bool { loaded.allSatisfy { $0 } }
    var title: String { fullyActive ? "GlobalProtect is on" : active ? "GlobalProtect is partially on" : "GlobalProtect is off" }
}

struct StartupState {
    let enabled: [Bool]
    var checkboxOn: Bool { enabled.allSatisfy { $0 } }
    var mixed: Bool { Set(enabled).count > 1 }
}

final class ServiceController {
    static let agents = [Agent(label: "com.paloaltonetworks.gp.pangpa"), Agent(label: "com.paloaltonetworks.gp.pangps")]
    let run: ([String]) throws -> CommandResult
    let exists: (String) -> Bool
    let pause: (TimeInterval) -> Void
    let domain: String
    let disconnect: () throws -> String
    let configuration: (String) throws -> [String: Any]

    init(disconnect: @escaping () throws -> String, domain: String = "gui/\(getuid())",
         run: @escaping ([String]) throws -> CommandResult = ServiceController.execute,
         exists: @escaping (String) -> Bool = FileManager.default.fileExists(atPath:),
         pause: @escaping (TimeInterval) -> Void = Thread.sleep(forTimeInterval:),
         configuration: @escaping (String) throws -> [String: Any] = ServiceController.readConfiguration) {
        self.configuration = configuration
        self.disconnect = disconnect
        self.domain = domain; self.run = run; self.exists = exists; self.pause = pause
    }

    static func execute(_ arguments: [String]) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe; process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return CommandResult(status: process.terminationStatus,
                             output: String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func state() throws -> ServiceState {
        let domainResult = try run(["print", domain])
        guard domainResult.status == 0 else {
            throw NSError(domain: "GlobalProtectToggle", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot inspect your macOS login session.\n\(domainResult.output)"])
        }
        return try ServiceState(loaded: Self.agents.map { try run(["print", "\(domain)/\($0.label)"]).status == 0 })
    }

    static func readConfiguration(_ file: String) throws -> [String: Any] {
        let data = try Data(contentsOf: URL(fileURLWithPath: file))
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw error("Could not read LaunchAgent configuration: \(file)")
        }
        return plist
    }

    static func error(_ message: String) -> NSError {
        NSError(domain: "GlobalProtectToggle", code: 5, userInfo: [NSLocalizedDescriptionKey: message])
    }

    // macOS currently prints enabled/disabled; earlier versions print false/true.
    // Match only a complete line for the exact label, never a substring of another service.
    static func disabledOverride(_ output: String, label: String) throws -> Bool? {
        let pattern = "(?m)^\\s*\"" + NSRegularExpression.escapedPattern(for: label) + "\"\\s*=>\\s*(enabled|disabled|true|false)\\s*;?\\s*$"
        let regex = try NSRegularExpression(pattern: pattern)
        let text = output as NSString
        if let match = regex.firstMatch(in: output, range: NSRange(location: 0, length: text.length)) {
            let value = text.substring(with: match.range(at: 1))
            return value == "disabled" || value == "true"
        }
        if output.contains("\"" + label + "\"") { throw error("macOS returned an unrecognized startup setting for \(label).") }
        return nil
    }

    func startupState() throws -> StartupState {
        let result = try run(["print-disabled", domain])
        guard result.status == 0 else { throw Self.error("Cannot read startup preferences.\n\(result.output)") }
        return try StartupState(enabled: Self.agents.map { agent in
            let disabled = try Self.disabledOverride(result.output, label: agent.label)
                ?? (configuration(agent.plist)["Disabled"] as? Bool ?? false)
            return !disabled
        })
    }

    private func applyStartup(_ enabled: [Bool]) throws {
        var failures: [String] = []
        for (agent, on) in zip(Self.agents, enabled) {
            do {
                let result = try run([on ? "enable" : "disable", "\(domain)/\(agent.label)"])
                if result.status != 0 { failures.append("Cannot save startup preference for \(agent.label).\n\(result.output)") }
            } catch { failures.append(error.localizedDescription) }
        }
        if !failures.isEmpty { throw Self.error(failures.joined(separator: "\n")) }
        guard try startupState().enabled == enabled else { throw Self.error("macOS did not confirm the requested startup preferences.") }
    }

    func setStartupEnabled(_ enabled: Bool) throws -> StartupState {
        let previous = try startupState()
        do {
            try applyStartup(Self.agents.map { _ in enabled })
        } catch {
            let original = error.localizedDescription
            do { try applyStartup(previous.enabled) }
            catch { throw Self.error(original + "\nRestoring the previous startup preference also failed: " + error.localizedDescription) }
            throw Self.error(original + "\nThe previous startup preference has been restored.")
        }
        return try startupState()
    }

    func toggle() throws -> (ServiceState, String) {
        let missing = Self.agents.filter { !exists($0.plist) }
        guard missing.isEmpty else {
            throw NSError(domain: "GlobalProtectToggle", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing GlobalProtect files:\n" + missing.map(\.plist).joined(separator: "\n")])
        }
        let before = try state()
        let starting = !before.active
        let ordered = starting ? Self.agents : Array(Self.agents.reversed())
        var log = [starting ? "Starting GlobalProtect…" : "Stopping GlobalProtect…"]
        let startup = try startupState()
        if !starting { log.append(try disconnect()) }
        var operationError: Error?
        do {
        for agent in ordered {
            // Match the original script's commands and order, in this user's GUI session.
            let arguments = [starting ? "load" : "unload", "-w", agent.plist]
            let result = try run(arguments)
            log.append("launchctl " + arguments.joined(separator: " "))
            if !result.output.isEmpty { log.append(result.output) }
            if result.status != 0 { log.append("Exit status: \(result.status)") }
        }
        } catch { operationError = error }
        // load/unload -w changes launchd's persistent flag. Restore the login
        // preference even if one of the manual commands failed.
        do { try applyStartup(startup.enabled) }
        catch { throw Self.error("Could not restore the startup preference after toggling.\n" + error.localizedDescription + "\n" + log.joined(separator: "\n")) }
        if let operationError { throw operationError }
        var after = try state()
        for _ in 0..<20 {
            if starting ? after.fullyActive : !after.active { break }
            pause(0.25)
            after = try state()
        }
        guard starting ? after.fullyActive : !after.active else {
            throw NSError(domain: "GlobalProtectToggle", code: 3, userInfo: [NSLocalizedDescriptionKey: "GlobalProtect did not reach the requested state.\n\(after.title)\n\n\(log.joined(separator: "\n"))"])
        }
        log.append("Startup preference preserved.")
        log.append(starting ? "Both LaunchAgents are loaded." : "Both LaunchAgents are unloaded.")
        return (after, log.joined(separator: "\n"))
    }
}
