import AppKit
import ApplicationServices

enum PermissionAccess {
    static let onboardingKey = "permissionSetupPresented.v1"
    static var settingsName: String {
        settingsName(majorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
    }
    static func settingsName(majorVersion: Int) -> String {
        majorVersion >= 27 ? "Device Control and Data Access" : "Accessibility"
    }
    static var isGranted: Bool { AXIsProcessTrusted() }
    static func needsFirstRunSetup(granted: Bool, presented: Bool, preview: Bool) -> Bool {
        !preview && !granted && !presented
    }
    static func requestAndOpenSettings() {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        // macOS 27 retains the Accessibility settings route for the renamed pane.
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        if !NSWorkspace.shared.open(url) {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security")!)
        }
    }
}
