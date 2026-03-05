// MacPilotHelperApp.swift
// MacPilot — MacPilotHelper (macOS GUI)
//
// Setup and onboarding application for MacPilotAgent.
// Handles: permission requests, daemon installation, pairing flow.

import SwiftUI
import SharedCore

@main
struct MacPilotHelperApp: App {
    var body: some Scene {
        WindowGroup {
            SetupView()
        }
        .windowResizability(.contentSize)
    }
}
