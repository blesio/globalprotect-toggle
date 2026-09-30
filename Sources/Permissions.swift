import AppKit
import ApplicationServices

enum PermissionAccess {
    static let onboardingKey = "permissionSetupPresented.v2"
    static var settingsName: String {
        settingsName(majorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
    }
    static func settingsName(majorVersion: Int) -> String {
        majorVersion >= 27 ? "Device Control and Data Access" : "Accessibility"
    }
    static var isGranted: Bool { AXIsProcessTrusted() }
    static func needsFirstRunSetup(granted: Bool, presented: Bool, preview: Bool, appManagementReview: Bool = false) -> Bool {
        !preview && (!granted || appManagementReview) && !presented
    }
    static func requestAndOpenSettings() {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        // macOS 27 retains the Accessibility settings route for the renamed pane.
        openSettings(appManagement: false)
    }
    static func settingsURL(appManagement: Bool) -> URL {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?" + (appManagement ? "Privacy_AppBundles" : "Privacy_Accessibility"))!
    }
    static func isPermissionDenial(_ message: String) -> Bool {
        let text = message.lowercased()
        return ["operation not permitted", "permission denied", "not authorized", "not authorised"].contains { text.contains($0) }
    }
    static func openSettings(appManagement: Bool) {
        if !NSWorkspace.shared.open(settingsURL(appManagement: appManagement)) {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security")!)
        }
    }
}
