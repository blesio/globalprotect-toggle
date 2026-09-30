import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private let status = NSTextField(labelWithString: "Checking GlobalProtect…")
    private let subtitle = NSTextField(wrappingLabelWithString: "Controls the GlobalProtect background services.")
    private let button = NSButton(title: "Toggle GlobalProtect", target: nil, action: nil)
    private let startupCheckbox = NSButton(checkboxWithTitle: "Run GlobalProtect at login", target: nil, action: nil)
    private let startupHint = NSTextField(wrappingLabelWithString: "Checking startup preference…")
    private let progress = NSProgressIndicator()
    private let controller = ServiceController(disconnect: VPNDisconnector.disconnect)
    private var busy = false
    private var startupCurrent: StartupState?
    private var timer: Timer?
    private let preview = CommandLine.arguments.contains("--preview")

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let item = NSMenuItem(); menu.addItem(item)
        let appMenu = NSMenu(); item.submenu = appMenu
        appMenu.addItem(withTitle: "About GlobalProtect Toggle", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit GlobalProtect Toggle", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        NSApp.mainMenu = menu
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 340), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "GlobalProtect Toggle"
        window.isReleasedWhenClosed = false
        let root = NSView(); window.contentView = root
        let icon = NSImageView()
        icon.image = NSImage(named: NSImage.Name("AppIcon")) ?? NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        status.font = .systemFont(ofSize: 22, weight: .semibold)
        status.alignment = .center
        subtitle.textColor = .secondaryLabelColor; subtitle.alignment = .center
        button.bezelStyle = .rounded; button.controlSize = .large
        button.target = self; button.action = #selector(toggle)
        button.keyEquivalent = "\r"
        startupCheckbox.target = self; startupCheckbox.action = #selector(changeStartup)
        startupCheckbox.allowsMixedState = true; startupCheckbox.isEnabled = false
        startupHint.font = .systemFont(ofSize: 11); startupHint.textColor = .secondaryLabelColor; startupHint.alignment = .center
        progress.style = .spinning; progress.controlSize = .small; progress.isDisplayedWhenStopped = false
        let footer = NSTextField(wrappingLabelWithString: "Turning off disconnects the VPN first, then unloads both LaunchAgents.")
        footer.font = .systemFont(ofSize: 11); footer.textColor = .secondaryLabelColor; footer.alignment = .center
        for view in [icon, status, subtitle, button, progress, startupCheckbox, startupHint, footer] {
            view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.topAnchor.constraint(equalTo: root.topAnchor, constant: 18), icon.centerXAnchor.constraint(equalTo: root.centerXAnchor), icon.widthAnchor.constraint(equalToConstant: 72), icon.heightAnchor.constraint(equalToConstant: 72),
            status.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 10), status.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20), status.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            subtitle.topAnchor.constraint(equalTo: status.bottomAnchor, constant: 8), subtitle.leadingAnchor.constraint(equalTo: status.leadingAnchor), subtitle.trailingAnchor.constraint(equalTo: status.trailingAnchor),
            button.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 16), button.centerXAnchor.constraint(equalTo: root.centerXAnchor), button.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
            progress.centerYAnchor.constraint(equalTo: button.centerYAnchor), progress.leadingAnchor.constraint(equalTo: button.trailingAnchor, constant: 10),
            startupCheckbox.topAnchor.constraint(equalTo: button.bottomAnchor, constant: 16), startupCheckbox.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            startupHint.topAnchor.constraint(equalTo: startupCheckbox.bottomAnchor, constant: 6), startupHint.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20), startupHint.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            footer.topAnchor.constraint(equalTo: startupHint.bottomAnchor, constant: 16), footer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20), footer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20)
        ])
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        if preview { refresh() } else { toggle() }
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window.makeKeyAndOrderFront(nil)
        if !preview { toggle() }
        return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { busy ? .terminateCancel : .terminateNow }

    private func display(_ state: ServiceState) {
        subtitle.toolTip = nil
        status.stringValue = state.title
        button.title = state.active ? "Turn GlobalProtect off" : "Turn GlobalProtect on"
        subtitle.stringValue = state.fullyActive ? "Both LaunchAgents are loaded." : state.active ? "One LaunchAgent is loaded. Toggle to turn both off." : "Both LaunchAgents are unloaded."
    }
    private func displayStartup(_ state: StartupState) {
        startupCurrent = state
        startupCheckbox.state = state.mixed ? .mixed : state.checkboxOn ? .on : .off
        startupHint.stringValue = state.mixed ? "The two agents have different login settings. Click to apply to both." : state.checkboxOn ? "Starts at your next login. Manual toggles preserve this setting." : "Does not start at your next login. You can still turn it on manually."
        startupCheckbox.isEnabled = true
    }
    @objc private func changeStartup() {
        guard !busy, let current = startupCurrent else { return }
        let enabled = !current.checkboxOn
        busy = true; button.isEnabled = false; startupCheckbox.isEnabled = false; progress.startAnimation(nil)
        DispatchQueue.global(qos: .utility).async {
            let result = Result { try self.controller.setStartupEnabled(enabled) }
            DispatchQueue.main.async {
                self.busy = false; self.button.isEnabled = true; self.progress.stopAnimation(nil)
                switch result {
                case .success(let state):
                    self.displayStartup(state)
                case .failure(let error):
                    let alert = NSAlert(); alert.messageText = "Could not save startup preference"; alert.informativeText = error.localizedDescription; alert.alertStyle = .warning
                    alert.beginSheetModal(for: self.window)
                    self.refresh()
                }
            }
        }
    }
    private func refresh() {
        guard !busy else { return }
        busy = true
        DispatchQueue.global(qos: .utility).async {
            let result = Result { (try self.controller.state(), try self.controller.startupState()) }
            DispatchQueue.main.async {
                self.busy = false
                switch result {
                case .success(let (state, startup)): self.display(state); self.displayStartup(startup); self.button.isEnabled = true
                case .failure(let error): self.status.stringValue = "Status unavailable"; self.subtitle.stringValue = "Could not read GlobalProtect settings."; self.subtitle.toolTip = error.localizedDescription; self.button.isEnabled = false; self.startupCheckbox.isEnabled = false
                }
            }
        }
    }
    @objc private func toggle() {
        guard !busy else { return }
        busy = true; button.isEnabled = false; startupCheckbox.isEnabled = false; progress.startAnimation(nil)
        status.stringValue = "Updating GlobalProtect…"
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try self.controller.toggle() }
            DispatchQueue.main.async {
                self.busy = false; self.button.isEnabled = true; self.progress.stopAnimation(nil)
                switch result {
                case .success(let (state, _)): self.display(state)
                    self.refresh()
                case .failure(let error):
                    self.status.stringValue = "Could not toggle GlobalProtect"
                    let alert = NSAlert(); alert.messageText = "Could not toggle GlobalProtect"; alert.informativeText = error.localizedDescription; alert.alertStyle = .warning
                    alert.beginSheetModal(for: self.window)
                    self.refresh()
                }
            }
        }
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.setActivationPolicy(.regular)
application.delegate = delegate
application.run()
