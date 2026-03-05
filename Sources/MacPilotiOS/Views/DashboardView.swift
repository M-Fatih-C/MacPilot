// DashboardView.swift
// MacPilot — MacPilot-iOS / Views
//
// System metrics dashboard displaying CPU, RAM, Disk, Network, and Processes.

import SwiftUI
import SharedCore

// MARK: - DashboardView

struct DashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header
                headerSection

                // Metrics Grid
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    MetricCard(
                        icon: "cpu",
                        title: "CPU",
                        value: viewModel.cpuUsageText,
                        progress: (viewModel.metrics?.cpu.usagePercent ?? 0) / 100,
                        color: .blue
                    )

                    MetricCard(
                        icon: "memorychip",
                        title: "RAM",
                        value: viewModel.ramUsageText,
                        progress: viewModel.ramUsageFraction,
                        color: .green
                    )

                    MetricCard(
                        icon: "internaldrive",
                        title: "Disk",
                        value: viewModel.diskUsageText,
                        progress: viewModel.diskUsageFraction,
                        color: .orange
                    )

                    MetricCard(
                        icon: "network",
                        title: "Network",
                        value: viewModel.networkText,
                        progress: nil,
                        color: .purple
                    )
                }
                .padding(.horizontal)

                // Processes Section
                processesSection
            }
            .padding(.bottom, 20)
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
        .onAppear { viewModel.startMonitoring() }
        .onDisappear { viewModel.stopMonitoring() }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("System Dashboard")
                    .font(.title2.bold())
                    .foregroundStyle(.white)

                if let lastUpdated = viewModel.lastUpdated {
                    Text("Updated \(lastUpdated, style: .relative) ago")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: "desktopcomputer")
                .font(.title)
                .foregroundStyle(.blue)
        }
        .padding(.horizontal)
        .padding(.top, 12)
    }

    // MARK: - Processes

    private var processesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top Processes")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal)

            ForEach(viewModel.topProcesses) { process in
                ProcessRow(process: process)
            }
        }
    }
}

// MARK: - MetricCard

struct MetricCard: View {
    let icon: String
    let title: String
    let value: String
    let progress: Double?
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)

                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.8))
            }

            Text(value)
                .font(.system(.body, design: .monospaced, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if let progress = progress {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.white.opacity(0.1))
                            .frame(height: 6)

                        RoundedRectangle(cornerRadius: 3)
                            .fill(color.gradient)
                            .frame(width: geo.size.width * min(1, max(0, progress)), height: 6)
                    }
                }
                .frame(height: 6)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

// MARK: - ProcessRow

struct ProcessRow: View {
    let process: MacProcessInfo

    var body: some View {
        HStack {
            Text(process.name)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer()

            Text(String(format: "%.1f%%", process.cpuPercent))
                .font(.system(.caption, design: .monospaced, weight: .medium))
                .foregroundStyle(.blue)
                .frame(width: 55, alignment: .trailing)

            Text(formatMemory(process.memoryBytes))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 65, alignment: .trailing)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    private func formatMemory(_ bytes: UInt64) -> String {
        let mb = Double(bytes) / 1_048_576
        if mb >= 1024 {
            return String(format: "%.1f GB", mb / 1024)
        }
        return String(format: "%.0f MB", mb)
    }
}
