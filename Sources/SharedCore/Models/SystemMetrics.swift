// SystemMetrics.swift
// MacPilot — SharedCore
//
// Data models for the system dashboard metrics.
// Collected on Mac, displayed on iPhone.

import Foundation

/// Complete system metrics snapshot.
public struct SystemMetrics: Codable, Sendable {
    /// When these metrics were collected.
    public let timestamp: Date

    /// CPU usage information.
    public let cpu: CPUMetrics

    /// Memory usage information.
    public let memory: MemoryMetrics

    /// Disk usage information.
    public let disk: DiskMetrics

    /// Network throughput information.
    public let network: NetworkMetrics

    /// Top processes by resource usage.
    public let topProcesses: [MacProcessInfo]

    public init(
        timestamp: Date = Date(),
        cpu: CPUMetrics,
        memory: MemoryMetrics,
        disk: DiskMetrics,
        network: NetworkMetrics,
        topProcesses: [MacProcessInfo]
    ) {
        self.timestamp = timestamp
        self.cpu = cpu
        self.memory = memory
        self.disk = disk
        self.network = network
        self.topProcesses = topProcesses
    }
}

// MARK: - CPU

/// CPU usage metrics.
public struct CPUMetrics: Codable, Sendable {
    /// Overall CPU usage percentage (0–100).
    public let usagePercent: Double

    /// Number of CPU cores.
    public let coreCount: Int

    /// Per-core usage percentages.
    public let perCoreUsage: [Double]

    public init(usagePercent: Double, coreCount: Int, perCoreUsage: [Double]) {
        self.usagePercent = usagePercent
        self.coreCount = coreCount
        self.perCoreUsage = perCoreUsage
    }
}

// MARK: - Memory

/// Memory usage metrics.
public struct MemoryMetrics: Codable, Sendable {
    /// Total physical memory in bytes.
    public let totalBytes: UInt64

    /// Used memory in bytes.
    public let usedBytes: UInt64

    /// Available memory in bytes.
    public let availableBytes: UInt64

    /// Swap space used in bytes.
    public let swapUsedBytes: UInt64

    public init(totalBytes: UInt64, usedBytes: UInt64, availableBytes: UInt64, swapUsedBytes: UInt64) {
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.availableBytes = availableBytes
        self.swapUsedBytes = swapUsedBytes
    }
}

// MARK: - Disk

/// Disk usage metrics.
public struct DiskMetrics: Codable, Sendable {
    /// Total disk space in bytes.
    public let totalBytes: UInt64

    /// Used disk space in bytes.
    public let usedBytes: UInt64

    /// Available disk space in bytes.
    public let availableBytes: UInt64

    public init(totalBytes: UInt64, usedBytes: UInt64, availableBytes: UInt64) {
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.availableBytes = availableBytes
    }
}

// MARK: - Network

/// Network throughput metrics.
public struct NetworkMetrics: Codable, Sendable {
    /// Total bytes sent since last collection.
    public let bytesSent: UInt64

    /// Total bytes received since last collection.
    public let bytesReceived: UInt64

    /// Number of active network connections.
    public let activeConnections: Int

    public init(bytesSent: UInt64, bytesReceived: UInt64, activeConnections: Int) {
        self.bytesSent = bytesSent
        self.bytesReceived = bytesReceived
        self.activeConnections = activeConnections
    }
}

// MARK: - Process

/// Information about a running process.
public struct MacProcessInfo: Codable, Sendable, Identifiable {
    /// Process ID.
    public let pid: Int32

    /// Process name.
    public let name: String

    /// CPU usage percentage for this process.
    public let cpuPercent: Double

    /// Memory used by this process in bytes.
    public let memoryBytes: UInt64

    public var id: Int32 { pid }

    public init(pid: Int32, name: String, cpuPercent: Double, memoryBytes: UInt64) {
        self.pid = pid
        self.name = name
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
    }
}
