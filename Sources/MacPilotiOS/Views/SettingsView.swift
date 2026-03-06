// SettingsView.swift
// MacPilot — MacPilot-iOS / Views
//
// App settings and device management.

import SwiftUI
import SharedCore

// MARK: - SettingsView

struct SettingsView: View {
    @ObservedObject var connection: AnyMacConnectionService
    @AppStorage("mouseSensitivity") private var mouseSensitivity: Double = 1.5
    @AppStorage("scrollSensitivity") private var scrollSensitivity: Double = 1.0
    @AppStorage("hapticFeedback") private var hapticFeedback: Bool = true
    @State private var showResetAlert = false

    var body: some View {
        NavigationStack {
            Form {
                // Connection Section
                connectionSection

                // Trackpad Section
                trackpadSection

                // Security Section
                securitySection

                // About Section
                aboutSection

                // Danger Zone
                dangerSection
            }
            .scrollContentBackground(.hidden)
            .background(
                Color(red: 0.06, green: 0.06, blue: 0.14)
                    .ignoresSafeArea()
            )
            .navigationTitle("Settings")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .onAppear {
                GestureEngine.mouseSensitivity = mouseSensitivity
                GestureEngine.scrollSensitivity = scrollSensitivity
            }
            .alert("Reset Device Identity", isPresented: $showResetAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    resetIdentity()
                }
            } message: {
                Text("This will unpair your device and delete all stored keys. You will need to pair again.")
            }
        }
    }

    // MARK: - Sections

    private var connectionSection: some View {
        Section {
            HStack {
                Label("Status", systemImage: "wifi")
                Spacer()
                Text(connection.connectionState.rawValue.capitalized)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Label("Port", systemImage: "number")
                Spacer()
                Text("\(NetworkConstants.port)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Connection")
        }
    }

    private var trackpadSection: some View {
        Section {
            VStack(alignment: .leading) {
                HStack {
                    Label("Mouse Speed", systemImage: "cursorarrow.motionlines")
                    Spacer()
                    Text(String(format: "%.1fx", mouseSensitivity))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $mouseSensitivity, in: 0.5...3.0, step: 0.1)
                    .tint(.blue)
            }
            .onChange(of: mouseSensitivity) { _, newValue in
                GestureEngine.mouseSensitivity = newValue
            }

            VStack(alignment: .leading) {
                HStack {
                    Label("Scroll Speed", systemImage: "arrow.up.and.down")
                    Spacer()
                    Text(String(format: "%.1fx", scrollSensitivity))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $scrollSensitivity, in: 0.5...3.0, step: 0.1)
                    .tint(.blue)
            }
            .onChange(of: scrollSensitivity) { _, newValue in
                GestureEngine.scrollSensitivity = newValue
            }

            Toggle(isOn: $hapticFeedback) {
                Label("Haptic Feedback", systemImage: "waveform")
            }
            .tint(.blue)
        } header: {
            Text("Trackpad")
        }
    }

    private var securitySection: some View {
        Section {
            HStack {
                Label("Encryption", systemImage: "lock.shield")
                Spacer()
                Text("AES-256-GCM")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Label("Key Exchange", systemImage: "key")
                Spacer()
                Text("X25519 + HKDF")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Label("TLS", systemImage: "checkmark.shield")
                Spacer()
                Text("1.3 + Cert Pin")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Security")
        }
    }

    private var aboutSection: some View {
        Section {
            HStack {
                Label("Version", systemImage: "info.circle")
                Spacer()
                Text(SharedCore.version)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Label("Protocol", systemImage: "network")
                Spacer()
                Text("WSS")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("About")
        }
    }

    private var dangerSection: some View {
        Section {
            Button(role: .destructive) {
                showResetAlert = true
            } label: {
                Label("Reset Device Identity", systemImage: "exclamationmark.triangle")
            }

            Button(role: .destructive) {
                connection.disconnect()
            } label: {
                Label("Disconnect", systemImage: "wifi.slash")
            }
        } header: {
            Text("Danger Zone")
        }
    }

    // MARK: - Actions

    private func resetIdentity() {
        DeviceIdentity.shared.resetIdentity()
        CertificateManager.shared.resetCertificates()
        TrustedDeviceStore.shared.removeAllTrustedDevices()
        connection.disconnect()
    }
}
