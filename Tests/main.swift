import Foundation

func check(_ value: @autoclosure () -> Bool, _ message: String) {
    guard value() else { fatalError(message) }
}
final class FakeLaunchctl {
    var loaded: [Bool]
    var enabled = [false, false]
    var mutations: [[String]] = []
    var silentlyFail = false
    var domainMissing = false
    var disconnectCalled = false
    var disconnectFails = false
    var failSettingOnce: Int?
    var throwOnLoad = false
    init(_ loaded: [Bool]) { self.loaded = loaded }
    func run(_ args: [String]) throws -> CommandResult {
        if args == ["print", "gui/501"] { return CommandResult(status: domainMissing ? 1 : 0, output: "") }
        if args[0] == "print-disabled" {
            return CommandResult(status: 0, output: ServiceController.agents.enumerated().map { index, agent in
                "\t\"\(agent.label)\" => \(enabled[index] ? "enabled" : "disabled")"
            }.joined(separator: "\n"))
        }
        let index = args.last!.contains("pangpa") ? 0 : 1
        if args[0] == "print" { return CommandResult(status: loaded[index] ? 0 : 113, output: "") }
        if args[0] == "unload" { check(disconnectCalled, "unloaded before disconnect") }
        mutations.append(args)
        if args[0] == "enable" || args[0] == "disable" {
            if failSettingOnce == index { failSettingOnce = nil; return CommandResult(status: 1, output: "Failed") }
            enabled[index] = args[0] == "enable"
        } else {
            if throwOnLoad { throw NSError(domain: "process", code: 1) }
            enabled[index] = args[0] == "load" // Model -w's persistent side effect.
            if !silentlyFail { loaded[index] = args[0] == "load" }
        }
        return CommandResult(status: 0, output: silentlyFail ? "Operation not permitted" : "")
    }
    func controller(missing: Bool = false) -> ServiceController {
        ServiceController(disconnect: {
            self.disconnectCalled = true
            if self.disconnectFails { throw NSError(domain: "test", code: 1) }
            return "VPN disconnected"
        }, domain: "gui/501", run: run, exists: { _ in !missing }, pause: { _ in }, configuration: { _ in [:] })
    }
}
let a = ServiceController.agents
for initial in [[false, false], [true, true], [true, false], [false, true]] {
    for startup in [[false, false], [true, true], [true, false], [false, true]] {
        let fake = FakeLaunchctl(initial); fake.enabled = startup
        let (state, _) = try fake.controller().toggle()
        let start = !initial.contains(true)
        check(fake.disconnectCalled == !start, "disconnect invoked for start or skipped for stop")
        check(start ? state.fullyActive : !state.active, "wrong final state")
        let commands = (start ? a : Array(a.reversed())).map { [start ? "load" : "unload", "-w", $0.plist] }
        check(Array(fake.mutations.prefix(2)) == commands, "wrong order or arguments")
        check(fake.enabled == startup, "manual toggle changed startup preference")
    }
}
let failure = FakeLaunchctl([false, false]); failure.silentlyFail = true
check((try? failure.controller().toggle()) == nil, "silent launchctl failure accepted")
check(failure.enabled == [false, false], "silent failure lost startup preference")
let processFailure = FakeLaunchctl([false, false]); processFailure.throwOnLoad = true
check((try? processFailure.controller().toggle()) == nil, "process failure accepted")
check(processFailure.enabled == [false, false], "process failure lost startup preference")
let unavailable = FakeLaunchctl([false, false]); unavailable.domainMissing = true
check((try? unavailable.controller().toggle()) == nil, "missing session accepted")
check(unavailable.mutations.isEmpty, "mutated services with unavailable session")
let missing = FakeLaunchctl([false, false])
check((try? missing.controller(missing: true).toggle()) == nil, "missing files accepted")
check(missing.mutations.isEmpty, "mutated with missing files")
let blockedDisconnect = FakeLaunchctl([true, true]); blockedDisconnect.disconnectFails = true
check((try? blockedDisconnect.controller().toggle()) == nil, "disconnect failure accepted")
check(blockedDisconnect.mutations.isEmpty, "agents unloaded after failed disconnect")
check(VPNPanelState.isDisconnected(["Not Connected"]), "not connected status missed")
check(VPNPanelState.isDisconnected(["Disconnected"]), "disconnected status missed")
check(!VPNPanelState.isDisconnected(["Connected", "Disconnect"]), "connected mistaken for off")
check(!VPNPanelState.isDisconnected(["Connect", "Enter the passcode to disconnect"]), "challenge mistaken for off")
print("PASS: manual start/stop, partial states, disconnect ordering, failures and startup preservation")

for initial in [[false, false], [true, true]] {
    let fake = FakeLaunchctl(initial)
    _ = try fake.controller().setStartupEnabled(true)
    check(fake.enabled == [true, true], "startup not enabled for both")
    check(fake.loaded == initial, "startup enable changed current session")
    _ = try fake.controller().setStartupEnabled(false)
    check(fake.enabled == [false, false], "startup not disabled for both")
    check(fake.loaded == initial, "startup disable changed current session")
    check(!fake.disconnectCalled, "startup setting disconnected VPN")
}
let rollback = FakeLaunchctl([true, true]); rollback.failSettingOnce = 1
check((try? rollback.controller().setStartupEnabled(true)) == nil, "partial setting failure accepted")
check(rollback.enabled == [false, false], "startup failure not rolled back")
for word in ["disabled", "true"] {
    let parsed = try ServiceController.disabledOverride("\"\(a[0].label)\" => \(word)", label: a[0].label)
    check(parsed == true, "disabled parse failed")
}
for word in ["enabled", "false"] {
    let parsed = try ServiceController.disabledOverride("\"\(a[0].label)\" => \(word)", label: a[0].label)
    check(parsed == false, "enabled parse failed")
}
let absent = try ServiceController.disabledOverride("\"\(a[0].label).other\" => true", label: a[0].label)
check(absent == nil, "label substring matched")
check((try? ServiceController.disabledOverride("\"\(a[0].label)\" => unknown", label: a[0].label)) == nil, "unknown output accepted")
print("PASS: startup enable/disable, session unchanged, rollback and launchctl output formats")
