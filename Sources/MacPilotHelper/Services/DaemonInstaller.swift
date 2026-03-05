// DaemonInstaller.swift
// MacPilot — MacPilotHelper
//
// Manages installation and lifecycle of the MacPilotAgent launchd daemon.

import Foundation

final class DaemonInstaller {

    static let plistName = "com.macpilot.agent.plist"

    /// Path to the LaunchAgent plist.
    static var plistURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/LaunchAgents/\(plistName)")
    }

    /// Install the launch agent plist to ~/Library/LaunchAgents.
    func install(agentBinaryPath: String) throws {
        // TODO: Write plist, load via launchctl
    }

    /// Uninstall the launch agent.
    func uninstall() throws {
        // TODO: launchctl unload, remove plist
    }

    /// Check if the daemon is currently running.
    func isRunning() -> Bool {
        // TODO: Check via launchctl list
        return false
    }
}
