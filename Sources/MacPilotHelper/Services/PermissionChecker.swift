// PermissionChecker.swift
// MacPilot — MacPilotHelper
//
// Checks and requests Accessibility permissions needed for CGEvent input control.

import Foundation
import ApplicationServices

final class PermissionChecker {

    /// Check if the application has Accessibility permission.
    static func hasAccessibilityPermission() -> Bool {
        return AXIsProcessTrusted()
    }

    /// Prompt the user to grant Accessibility permission via System Settings.
    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
