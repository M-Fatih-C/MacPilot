// DashboardViewModel.swift
// MacPilot — MacPilot-iOS / ViewModels
//
// Manages system metrics state for the dashboard view.
// Requests metrics from Mac every 3 seconds.

import Foundation
import Combine
import SharedCore

// MARK: - DashboardViewModel

/// ViewModel for the system metrics dashboard.
@MainActor
public final class DashboardViewModel: ObservableObject {

    // MARK: - Published State

    @Published public var metrics: SystemMetrics?
    @Published public var isLoading: Bool = true
    @Published public var lastUpdated: Date?

    // MARK: - Computed Properties

    /// CPU usage as a formatted percentage string.
    public var cpuUsageText: String {
        guard let cpu = metrics?.cpu else { return "--%" }
        return String(format: "%.1f%%", cpu.usagePercent)
    }

    /// RAM usage as a formatted string.
    public var ramUsageText: String {
        guard let mem = metrics?.memory else { return "--" }
        let usedGB = Double(mem.usedBytes) / 1_073_741_824
        let totalGB = Double(mem.totalBytes) / 1_073_741_824
        return String(format: "%.1f / %.1f GB", usedGB, totalGB)
    }

    /// RAM usage as a fraction (0.0 – 1.0).
    public var ramUsageFraction: Double {
        guard let mem = metrics?.memory, mem.totalBytes > 0 else { return 0 }
        return Double(mem.usedBytes) / Double(mem.totalBytes)
    }

    /// Disk usage as a formatted string.
    public var diskUsageText: String {
        guard let disk = metrics?.disk else { return "--" }
        let usedGB = Double(disk.usedBytes) / 1_073_741_824
        let totalGB = Double(disk.totalBytes) / 1_073_741_824
        return String(format: "%.0f / %.0f GB", usedGB, totalGB)
    }

    /// Disk usage as a fraction (0.0 – 1.0).
    public var diskUsageFraction: Double {
        guard let disk = metrics?.disk, disk.totalBytes > 0 else { return 0 }
        return Double(disk.usedBytes) / Double(disk.totalBytes)
    }

    /// Network speed as formatted string.
    public var networkText: String {
        guard let net = metrics?.network else { return "-- / --" }
        return "↑ \(formatBytes(net.bytesSent))/s  ↓ \(formatBytes(net.bytesReceived))/s"
    }

    /// Top processes.
    public var topProcesses: [MacProcessInfo] {
        metrics?.topProcesses ?? []
    }

    // MARK: - Properties

    private let connection: AnyMacConnectionService
    private var refreshTimer: Timer?
    private var messageCancellable: AnyCancellable?

    // MARK: - Init

    public init(connection: AnyMacConnectionService) {
        self.connection = connection
        self.messageCancellable = NotificationCenter.default
            .publisher(for: .macPilotMessageReceived)
            .compactMap { $0.object as? Data }
            .receive(on: RunLoop.main)
            .sink { [weak self] data in
                guard let type = try? MessageProtocol.peekType(data), type == .metricsResponse else {
                    return
                }
                self?.handleMetricsResponse(data)
            }
    }

    // MARK: - Start / Stop

    /// Start requesting metrics periodically.
    public func startMonitoring() {
        isLoading = true
        requestMetrics()

        refreshTimer = Timer.scheduledTimer(
            withTimeInterval: NetworkConstants.metricsRefreshInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.requestMetrics()
            }
        }
    }

    /// Stop requesting metrics.
    public func stopMonitoring() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - Request

    /// Send a metrics request to the Mac.
    private func requestMetrics() {
        do {
            let request = MetricsRequest()
            let data = try MessageProtocol.encodePlaintext(request, type: .metricsRequest)
            connection.send(data)
        } catch {
            print("[MacPilot][Dashboard] Failed to request metrics: \(error.localizedDescription)")
        }
    }

    /// Handle incoming metrics response from the Mac.
    public func handleMetricsResponse(_ data: Data) {
        do {
            let result = try MessageProtocol.decodePlaintext(data, as: SystemMetrics.self)
            self.metrics = result.payload
            self.lastUpdated = Date()
            self.isLoading = false
        } catch {
            print("[MacPilot][Dashboard] Failed to decode metrics: \(error.localizedDescription)")
        }
    }

    // MARK: - Formatting

    private func formatBytes(_ bytes: UInt64) -> String {
        let kb = Double(bytes) / 1024
        let mb = kb / 1024
        if mb >= 1 {
            return String(format: "%.1f MB", mb)
        } else if kb >= 1 {
            return String(format: "%.0f KB", kb)
        } else {
            return "\(bytes) B"
        }
    }
}

// MARK: - MetricsRequest

/// Empty request model to trigger metrics collection on the Mac.
public struct MetricsRequest: Codable, Sendable {
    public let requestId: UUID

    public init(requestId: UUID = UUID()) {
        self.requestId = requestId
    }
}
