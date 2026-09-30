import Foundation

// Exercise the real launchd with two disposable sleep agents. No GlobalProtect
// command is executed: its labels and paths are translated before launchctl runs.
let manager = FileManager.default
let folder = manager.temporaryDirectory.appendingPathComponent("gp-toggle-test-\(getpid())")
try manager.createDirectory(at: folder, withIntermediateDirectories: true)
let domain = "gui/\(getuid())"
let originals = ServiceController.agents
let labels = originals.map { "local.radek.gptoggle.integration.\(getpid())." + $0.label.components(separatedBy: ".").last! }
let files = labels.map { folder.appendingPathComponent($0 + ".plist").path }
for (index, label) in labels.enumerated() {
    let config: [String: Any] = ["Label": label, "ProgramArguments": ["/bin/sleep", "120"], "RunAtLoad": true]
    try PropertyListSerialization.data(fromPropertyList: config, format: .xml, options: 0).write(to: URL(fileURLWithPath: files[index]))
}
defer {
    for label in labels {
        _ = try? ServiceController.execute(["bootout", "\(domain)/\(label)"])
        _ = try? ServiceController.execute(["enable", "\(domain)/\(label)"])
    }
    try? manager.removeItem(at: folder)
}
let controller = ServiceController(disconnect: { "Test agents have no VPN." }, domain: domain, run: { arguments in
    let translated = arguments.map { argument -> String in
        for (index, agent) in originals.enumerated() {
            if argument == agent.plist { return files[index] }
            if argument == "\(domain)/\(agent.label)" { return "\(domain)/\(labels[index])" }
        }
        return argument
    }
    guard !translated.contains(where: { $0.contains("com.paloaltonetworks") }) else { throw ServiceController.error("Untranslated GlobalProtect command refused") }
    let result = try ServiceController.execute(translated)
    var output = result.output
    if arguments[0] == "print-disabled" {
        output = output.components(separatedBy: "\n").filter { !$0.contains("com.paloaltonetworks.gp.") }.joined(separator: "\n")
        for (index, agent) in originals.enumerated() { output = output.replacingOccurrences(of: labels[index], with: agent.label) }
    }
    return CommandResult(status: result.status, output: output)
}, exists: { _ in true }, configuration: { _ in [:] })
func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw ServiceController.error(message) }
}
_ = try controller.setStartupEnabled(false)
let (started, _) = try controller.toggle()
try require(started.fullyActive, "Test agents failed to load")
try require(try controller.startupState().enabled == [false, false], "Manual start did not preserve disabled startup")
_ = try controller.setStartupEnabled(true)
try require(try controller.state().fullyActive, "Enabling startup stopped running agents")
let (stopped, _) = try controller.toggle()
try require(!stopped.active, "Test agents failed to unload")
try require(try controller.startupState().enabled == [true, true], "Manual stop did not preserve enabled startup")
_ = try controller.setStartupEnabled(false)
try require(try !controller.state().active, "Changing startup loaded stopped agents")
print("PASS: real launchd start/stop preserves startup flags; changing startup leaves current state unchanged")
