// ShortcutsView.swift
// MacPilot — MacPilot-iOS / Views
//
// System commands and keyboard shortcuts interface.

import SwiftUI
import SharedCore

// MARK: - ShortcutsView

struct ShortcutsView: View {
    @ObservedObject var connection: AnyMacConnectionService
    @StateObject private var biometricAuth = BiometricAuth.shared
    @State private var showingConfirmation = false
    @State private var pendingAction: SystemAction?
    @State private var authFailed = false
    private let shortcutColumns = [GridItem(.adaptive(minimum: 140), spacing: 10)]
    private let mediaColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Keyboard Shortcuts
                    shortcutsSection

                    // System Actions
                    systemActionsSection

                    // Media Controls
                    mediaControlsSection
                }
                .padding()
            }
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.05, blue: 0.12),
                        Color(red: 0.08, green: 0.08, blue: 0.18)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .navigationTitle("Shortcuts")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .onAppear {
                biometricAuth.checkAvailability()
            }
            .alert("Confirm Action", isPresented: $showingConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Execute", role: .destructive) {
                    if let action = pendingAction {
                        Task { await authenticateAndExecute(action) }
                    }
                }
            } message: {
                if let action = pendingAction {
                    Text("\(action.name) requires \(biometricAuth.biometricType.rawValue) authentication.")
                }
            }
            .alert("Authentication Failed", isPresented: $authFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Biometric authentication failed. Action was cancelled for security.")
            }
        }
    }

    // MARK: - Keyboard Shortcuts

    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(icon: "keyboard", title: "Keyboard Shortcuts", color: .purple)

            LazyVGrid(columns: shortcutColumns, spacing: 10) {
                ShortcutButton(label: "Copy", keys: "⌘C", color: .blue) {
                    sendShortcut(.copy)
                }
                ShortcutButton(label: "Paste", keys: "⌘V", color: .blue) {
                    sendShortcut(.paste)
                }
                ShortcutButton(label: "Undo", keys: "⌘Z", color: .blue) {
                    sendShortcut(.undo)
                }
                ShortcutButton(label: "Select All", keys: "⌘A", color: .blue) {
                    sendShortcut(.selectAll)
                }
                ShortcutButton(label: "Spotlight", keys: "⌘Space", color: .purple) {
                    sendShortcut(.spotlight)
                }
                ShortcutButton(label: "Screenshot", keys: "⌘⇧3", color: .purple) {
                    sendShortcut(.screenshot)
                }
                ShortcutButton(label: "Escape", keys: "ESC", color: .gray) {
                    sendShortcut(.escape)
                }
                ShortcutButton(label: "Enter", keys: "↩", color: .gray) {
                    sendShortcut(.enter)
                }
            }
        }
    }

    // MARK: - System Actions

    private var systemActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(icon: "gearshape.2", title: "System", color: .orange)

            VStack(spacing: 8) {
                SystemActionRow(action: .shutdown, requiresConfirm: true) {
                    confirmAction(.shutdown)
                }
                SystemActionRow(action: .restart, requiresConfirm: true) {
                    confirmAction(.restart)
                }
                SystemActionRow(action: .sleep, requiresConfirm: true) {
                    confirmAction(.sleep)
                }
                SystemActionRow(action: .lockScreen, requiresConfirm: false) {
                    executeAction(.lockScreen)
                }
                SystemActionRow(action: .emptyTrash, requiresConfirm: true) {
                    confirmAction(.emptyTrash)
                }
                SystemActionRow(action: .runScript, requiresConfirm: true) {
                    confirmAction(.runScript)
                }
            }
        }
    }

    // MARK: - Media Controls

    private var mediaControlsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(icon: "music.note", title: "Media", color: .pink)

            LazyVGrid(columns: mediaColumns, spacing: 10) {
                MediaButton(icon: "backward.fill", label: "Prev") { sendMediaKey(.previousTrack) }
                MediaButton(icon: "playpause.fill", label: "Play/Pause") { sendMediaKey(.playPause) }
                MediaButton(icon: "forward.fill", label: "Next") { sendMediaKey(.nextTrack) }
                MediaButton(icon: "speaker.minus.fill", label: "Vol -") { sendMediaKey(.volumeDown) }
                MediaButton(icon: "speaker.plus.fill", label: "Vol +") { sendMediaKey(.volumeUp) }
                MediaButton(icon: "speaker.slash.fill", label: "Mute") { sendMediaKey(.mute) }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(.white.opacity(0.06))
            )
        }
    }

    // MARK: - Actions

    private func confirmAction(_ action: SystemAction) {
        pendingAction = action
        showingConfirmation = true
    }

    private func sendShortcut(_ shortcut: KeyboardShortcut) {
        guard connection.isConnected else { return }
        sendKeyPress(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers)
    }

    /// Authenticate via FaceID then execute the action.
    private func authenticateAndExecute(_ action: SystemAction) async {
        let authenticated: Bool
        switch action.command {
        case "shutdown":
            authenticated = await biometricAuth.authenticateForShutdown()
        case "restart":
            authenticated = await biometricAuth.authenticateForRestart()
        case "runScript":
            authenticated = await biometricAuth.authenticateForScriptExecution()
        default:
            authenticated = await biometricAuth.authenticate(reason: "Authorize \(action.name)")
        }

        if authenticated {
            executeAction(action)
        } else {
            authFailed = true
        }
    }

    private func executeAction(_ action: SystemAction) {
        guard connection.isConnected else { return }
        let command = CommandRequest(command: action.command, requiresAuth: action.requiresAuth)
        do {
            let data = try MessageProtocol.encodePlaintext(command, type: .commandRequest)
            connection.send(data)
        } catch {
            print("[MacPilot][Shortcuts] Action failed: \(error)")
        }
    }

    private func sendMediaKey(_ key: MediaKey) {
        guard connection.isConnected else { return }
        sendKeyPress(keyCode: key.keyCode)
    }

    private func sendKeyPress(keyCode: UInt16, modifiers: UInt = 0) {
        do {
            let downEvent = GestureEngine.keyEvent(
                keyCode: keyCode,
                modifiers: modifiers,
                isDown: true
            )
            let upEvent = GestureEngine.keyEvent(
                keyCode: keyCode,
                modifiers: modifiers,
                isDown: false
            )

            let downData = try MessageProtocol.encodePlaintext(downEvent, type: .keyPress)
            let upData = try MessageProtocol.encodePlaintext(upEvent, type: .keyRelease)

            connection.send(downData)
            connection.send(upData)
        } catch {
            print("[MacPilot][Shortcuts] Key send failed: \(error)")
        }
    }
}

// MARK: - Supporting Types

enum KeyboardShortcut {
    case copy, paste, undo, selectAll, spotlight, screenshot, escape, enter

    var keyCode: UInt16 {
        switch self {
        case .copy: return 0x08       // C
        case .paste: return 0x09      // V
        case .undo: return 0x06       // Z
        case .selectAll: return 0x00  // A
        case .spotlight: return 0x31  // Space
        case .screenshot: return 0x14 // 3 (approx)
        case .escape: return 0x35
        case .enter: return 0x24
        }
    }

    var modifiers: UInt {
        // Raw bitmask values (CGEventFlags is macOS-only)
        let maskCommand: UInt = 0x100000  // NX_COMMANDMASK
        let maskShift: UInt = 0x20000     // NX_SHIFTMASK
        switch self {
        case .copy, .paste, .undo, .selectAll, .spotlight:
            return maskCommand
        case .screenshot:
            return maskCommand | maskShift
        case .escape, .enter:
            return 0
        }
    }
}

struct SystemAction: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let color: Color
    let command: String
    let requiresAuth: Bool

    static let shutdown = SystemAction(name: "Shutdown", icon: "power", color: .red, command: "shutdown", requiresAuth: true)
    static let restart = SystemAction(name: "Restart", icon: "arrow.triangle.2.circlepath", color: .orange, command: "restart", requiresAuth: true)
    static let sleep = SystemAction(name: "Sleep", icon: "moon.fill", color: .indigo, command: "sleep", requiresAuth: true)
    static let lockScreen = SystemAction(name: "Lock Screen", icon: "lock.fill", color: .yellow, command: "lock", requiresAuth: false)
    static let emptyTrash = SystemAction(name: "Empty Trash", icon: "trash.fill", color: .red, command: "emptyTrash", requiresAuth: true)
    static let runScript = SystemAction(name: "Run Script", icon: "terminal.fill", color: .green, command: "runScript", requiresAuth: true)
}

enum MediaKey {
    case playPause, nextTrack, previousTrack, volumeUp, volumeDown, mute

    var keyCode: UInt16 {
        switch self {
        // Apple keyboard media keys map to F7/F8/F9 virtual key codes.
        case .playPause: return 0x64   // F8
        case .nextTrack: return 0x65   // F9
        case .previousTrack: return 0x62 // F7
        case .volumeUp: return 0x48
        case .volumeDown: return 0x49
        case .mute: return 0x4A
        }
    }
}

/// Command request sent to the Mac.
public struct CommandRequest: Codable, Sendable {
    public let commandId: UUID
    public let command: String
    public let requiresAuth: Bool

    public init(commandId: UUID = UUID(), command: String, requiresAuth: Bool) {
        self.commandId = commandId
        self.command = command
        self.requiresAuth = requiresAuth
    }
}

// MARK: - Subviews

struct SectionHeader: View {
    let icon: String
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
        }
    }
}

struct ShortcutButton: View {
    let label: String
    let keys: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(keys)
                    .font(.system(.title3, design: .monospaced, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(color)
                Text(label)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(color.opacity(0.15), lineWidth: 1)
                    )
            )
        }
    }
}

struct SystemActionRow: View {
    let action: SystemAction
    let requiresConfirm: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: action.icon)
                    .font(.title3)
                    .foregroundStyle(action.color)
                    .frame(width: 36)

                Text(action.name)
                    .font(.body)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(.white)

                Spacer()

                if requiresConfirm {
                    Image(systemName: "faceid")
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.white.opacity(0.06))
            )
        }
    }
}

struct MediaButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 44, height: 44)

                Text(label)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.white.opacity(0.05))
            )
        }
    }
}
