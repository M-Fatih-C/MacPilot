// MainTabView.swift
// MacPilot — MacPilot-iOS / Views
//
// Root tab bar navigation controlling all app screens.

import SwiftUI
import SharedCore

// MARK: - MainTabView

struct MainTabView: View {
    @StateObject private var connection = MacConnection()
    @StateObject private var bonjourBrowser = BonjourBrowser()

    @State private var selectedTab: Tab = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(connection: connection, bonjourBrowser: bonjourBrowser)
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(Tab.home)

            TrackpadView(viewModel: TrackpadViewModel(connection: connection))
                .tabItem {
                    Label("Trackpad", systemImage: "hand.draw.fill")
                }
                .tag(Tab.trackpad)

            DashboardView(viewModel: DashboardViewModel(connection: connection))
                .tabItem {
                    Label("Dashboard", systemImage: "gauge.with.dots.needle.bottom.50percent")
                }
                .tag(Tab.dashboard)

            ShortcutsView(connection: connection)
                .tabItem {
                    Label("Shortcuts", systemImage: "bolt.fill")
                }
                .tag(Tab.shortcuts)

            FileBrowserView(connection: connection)
                .tabItem {
                    Label("Files", systemImage: "folder.fill")
                }
                .tag(Tab.files)

            SettingsView(connection: connection)
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(Tab.settings)
        }
        .tint(.blue)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Tab

enum Tab: String {
    case home
    case trackpad
    case dashboard
    case shortcuts
    case files
    case settings
}
