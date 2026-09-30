import AppKit
import ApplicationServices

// Read the client's own status instead of treating a button press as a completed disconnect.
enum VPNPanelState {
    static func isDisconnected(_ labels: [String]) -> Bool {
        let normalized = labels.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        let off = ["not connected", "disconnected", "rozłączono", "nie połączono", "niepołączony"]
        return normalized.contains { off.contains($0) }
    }
}

final class VPNDisconnector {
    static let bundleID = "com.paloaltonetworks.GlobalProtect.client"

    static func failure(_ message: String) -> NSError {
        NSError(domain: "GlobalProtectToggle", code: 4, userInfo: [NSLocalizedDescriptionKey: message + "\nThe LaunchAgents have not been unloaded."])
    }

    static func onMain<T>(_ body: () throws -> T) throws -> T {
        if Thread.isMainThread { return try body() }
        return try DispatchQueue.main.sync(execute: body)
    }

    static func disconnect() throws -> String {
        let trusted = try onMain {
            AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        }
        guard trusted else {
            throw failure("Allow GlobalProtect Toggle in System Settings → Privacy & Security → \(PermissionAccess.settingsName), then retry. This permission lets the utility click GlobalProtect’s Disconnect control and verify its status.")
        }
        // Opening an already running client shows its panel. A missing UI is opened so
        // a surviving PanGPS connection can still be disconnected normally.
        try onMain {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                throw failure("The GlobalProtect application could not be found.")
            }
            NSWorkspace.shared.open(url)
        }
        var running: NSRunningApplication?
        for _ in 0..<40 {
            running = try onMain { NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first }
            if running != nil { break }
            Thread.sleep(forTimeInterval: 0.25)
        }
        guard let running else { throw failure("Could not open GlobalProtect to disconnect the VPN.") }
        let app = AXUIElementCreateApplication(running.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 2)
        var requested = false
        var openedStatusItem = false
        var openedSettings = false
        let deadline = Date().addingTimeInterval(35)
        while Date() < deadline {
            let nodes = tree(app)
            if VPNPanelState.isDisconnected(nodes.flatMap(labels)) {
                return requested ? "GlobalProtect VPN disconnected." : "GlobalProtect VPN is already disconnected."
            }
            if !requested, let control = nodes.first(where: { node in
                let role = string(node, kAXRoleAttribute)
                return [kAXButtonRole, kAXMenuItemRole].contains(role) && labels(node).contains(where: { ["disconnect", "rozłącz"].contains($0.lowercased()) })
            }) {
                if AXUIElementPerformAction(control, kAXPressAction as CFString) == .success { requested = true }
            } else if !openedStatusItem, let item = extraMenuItems(app).first(where: { string($0, kAXRoleAttribute) == kAXMenuBarItemRole }) {
                // GlobalProtect is a menu-bar app. Its extra menu bar opens the status panel.
                if AXUIElementPerformAction(item, kAXPressAction as CFString) == .success { openedStatusItem = true }
            } else if !openedSettings, let item = nodes.first(where: { node in
                string(node, kAXRoleAttribute) == kAXButtonRole && labels(node).contains(where: { value in
                    let label = value.lowercased()
                    return label == "settings" || label == "menu" || label == "ustawienia" || label.contains("hamburger") || label == "gp.menu"
                })
            }) {
                if AXUIElementPerformAction(item, kAXPressAction as CFString) == .success { openedSettings = true }
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        throw failure(requested
            ? "GlobalProtect has not confirmed disconnection. Complete any reason/passcode prompt in GlobalProtect, then retry turning it off."
            : "Could not find GlobalProtect’s Disconnect control or a disconnected status. Open its status panel and disconnect manually, then retry. Your organization may restrict disconnecting.")
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return "" }
        return value as? String ?? ""
    }
    static func labels(_ element: AXUIElement) -> [String] {
        [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute, kAXHelpAttribute, kAXIdentifierAttribute].map { string(element, $0) }.filter { !$0.isEmpty }
    }
    static func extraMenuItems(_ app: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXExtrasMenuBarAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return [] }
        return tree(unsafeBitCast(value, to: AXUIElement.self))
    }
    static func tree(_ root: AXUIElement) -> [AXUIElement] {
        var result: [AXUIElement] = []
        var seen = Set<CFHashCode>()
        func visit(_ element: AXUIElement, _ depth: Int) {
            guard depth < 18, result.count < 1200, seen.insert(CFHash(element)).inserted else { return }
            result.append(element)
            for attribute in [kAXChildrenAttribute, kAXWindowsAttribute, kAXMenuBarAttribute, kAXExtrasMenuBarAttribute] {
                var value: CFTypeRef?
                guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value else { continue }
                if CFGetTypeID(value) == AXUIElementGetTypeID() {
                    visit(unsafeBitCast(value, to: AXUIElement.self), depth + 1)
                } else if let children = value as? [AXUIElement] {
                    for child in children { visit(child, depth + 1) }
                }
            }
        }
        visit(root, 0)
        return result
    }
}
