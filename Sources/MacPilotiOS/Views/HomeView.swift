// HomeView.swift
// MacPilot — MacPilot-iOS / Views
//
// Landing screen showing connection status, quick actions, and Mac overview.

import SwiftUI
import SharedCore

// MARK: - HomeView

struct HomeView: View {
    @ObservedObject var connection: AnyMacConnectionService
    @ObservedObject var bonjourBrowser: BonjourBrowser
    @Binding var selectedTab: Tab

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Connection Card
                    connectionCard

                    // Quick Actions
                    if connection.isConnected {
                        quickActionsGrid
                    }

                    // Discovered Devices
                    if !connection.isConnected {
                        discoveredDevices
                    }
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
            .navigationTitle("MacPilot")
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    // MARK: - Connection Card

    private var connectionCard: some View {
        VStack(spacing: 16) {
            Image("BrandLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 132, height: 132)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                )

            // Status icon
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 80, height: 80)

                Image(systemName: statusIcon)
                    .font(.system(size: 32))
                    .foregroundStyle(statusColor)
            }

            VStack(spacing: 6) {
                Text(statusTitle)
                    .font(.title3.bold())
                    .foregroundStyle(.white)

                Text(statusSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Action button
            if !connection.isConnected {
                Button {
                    bonjourBrowser.startBrowsing()
                } label: {
                    HStack {
                        Image(systemName: "magnifyingglass")
                        Text("Scan Network")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.blue.gradient)
                    )
                }
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    // MARK: - Quick Actions

    private var quickActionsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)
                .foregroundStyle(.white)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                QuickActionButton(icon: "cursorarrow.motionlines", label: "Trackpad", color: .blue) {
                    selectedTab = .trackpad
                }
                QuickActionButton(icon: "keyboard", label: "Keyboard", color: .purple) {
                    selectedTab = .shortcuts
                }
                QuickActionButton(icon: "gauge.with.dots.needle.bottom.50percent", label: "Dashboard", color: .green) {
                    selectedTab = .dashboard
                }
                QuickActionButton(icon: "bolt.fill", label: "Shortcuts", color: .orange) {
                    selectedTab = .shortcuts
                }
                QuickActionButton(icon: "folder.fill", label: "Files", color: .cyan) {
                    selectedTab = .files
                }
                QuickActionButton(icon: "gearshape.fill", label: "Settings", color: .gray) {
                    selectedTab = .settings
                }
            }
        }
    }

    // MARK: - Discovered Devices

    private var discoveredDevices: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Devices Found")
                    .font(.headline)
                    .foregroundStyle(.white)

                Spacer()

                if bonjourBrowser.isBrowsing {
                    ProgressView()
                        .tint(.blue)
                }
            }

            if bonjourBrowser.discoveredMacs.isEmpty && bonjourBrowser.isBrowsing {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("Searching for Mac...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 30)
                    Spacer()
                }
            }

            ForEach(bonjourBrowser.discoveredMacs) { mac in
                Button {
                    connection.connect(to: mac.endpoint)
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "desktopcomputer")
                            .font(.title2)
                            .foregroundStyle(.blue)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(mac.name)
                                .font(.body.weight(.medium))
                                .foregroundStyle(.white)
                            Text("Tap to connect")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(.white.opacity(0.06))
                    )
                }
            }
        }
    }

    // MARK: - Status Helpers

    private var statusColor: Color {
        switch connection.connectionState {
        case .connected: return .green
        case .connecting, .authenticating, .keyExchange: return .orange
        case .reconnecting: return .yellow
        case .failed: return .red
        default: return .gray
        }
    }

    private var statusIcon: String {
        switch connection.connectionState {
        case .connected: return "checkmark.circle.fill"
        case .connecting, .authenticating, .keyExchange: return "arrow.triangle.2.circlepath"
        case .reconnecting: return "arrow.clockwise"
        case .failed: return "xmark.circle.fill"
        default: return "wifi.slash"
        }
    }

    private var statusTitle: String {
        switch connection.connectionState {
        case .connected: return "Connected"
        case .connecting: return "Connecting..."
        case .authenticating: return "Authenticating..."
        case .keyExchange: return "Securing..."
        case .reconnecting: return "Reconnecting..."
        case .failed: return "Connection Failed"
        default: return "Not Connected"
        }
    }

    private var statusSubtitle: String {
        switch connection.connectionState {
        case .connected: return "Your Mac is ready for remote control"
        case .reconnecting: return "Attempting to restore connection"
        case .failed: return "Check that Mac is on the same network"
        default: return "Scan the network to find your Mac"
        }
    }
}

// MARK: - Quick Action Button

struct QuickActionButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)

                Text(label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(color.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
