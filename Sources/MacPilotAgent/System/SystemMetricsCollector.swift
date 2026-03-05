// SystemMetricsCollector.swift
// MacPilot — MacPilotAgent / System
//
// Collects system metrics using macOS system APIs:
//   CPU  → host_statistics64 (Mach)
//   RAM  → host_statistics64 (Mach)
//   Disk → statfs
//   Network → getifaddrs + sysctl

import Foundation
import SharedCore
#if canImport(Darwin)
import Darwin
#endif
import IOKit

// MARK: - SystemMetricsCollector

/// Collects macOS system metrics (CPU, RAM, Disk, Network).
///
/// Usage:
/// ```swift
/// let collector = SystemMetricsCollector()
/// let metrics = collector.collect()
/// ```
public final class SystemMetricsCollector {

    // MARK: - Properties

    /// Previous CPU ticks for delta calculation.
    private var previousCPUTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) = (0, 0, 0, 0)

    /// Previous network bytes for speed calculation.
    private var previousNetBytes: (sent: UInt64, received: UInt64) = (0, 0)
    private var previousNetTimestamp: Date = Date()

    /// Dispatch queue for periodic collection.
    private let collectQueue = DispatchQueue(label: "com.macpilot.metrics", qos: .utility)
    private var timer: DispatchSourceTimer?

    /// Callback when new metrics are collected.
    public var onMetricsCollected: ((SystemMetrics) -> Void)?

    // MARK: - Init

    public init() {}

    // MARK: - Periodic Collection

    /// Start collecting metrics at the specified interval.
    ///
    /// - Parameter interval: Collection interval in seconds (default: 3s).
    public func startCollecting(interval: TimeInterval = NetworkConstants.metricsRefreshInterval) {
        let timer = DispatchSource.makeTimerSource(queue: collectQueue)
        timer.schedule(deadline: .now(), repeating: interval)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            let metrics = self.collect()
            self.onMetricsCollected?(metrics)
        }
        timer.resume()
        self.timer = timer
        log("Metrics", "Started collecting every \(interval)s")
    }

    /// Stop periodic collection.
    public func stopCollecting() {
        timer?.cancel()
        timer = nil
        log("Metrics", "Stopped collecting")
    }

    // MARK: - Collect All

    /// Collect a complete metrics snapshot.
    public func collect() -> SystemMetrics {
        let processMonitor = ProcessMonitor()
        return SystemMetrics(
            cpu: collectCPU(),
            memory: collectMemory(),
            disk: collectDisk(),
            network: collectNetwork(),
            topProcesses: processMonitor.getTopProcesses(limit: 10)
        )
    }

    // MARK: - CPU

    /// Collect CPU usage using Mach host_statistics64.
    public func collectCPU() -> CPUMetrics {
        var cpuInfo = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        )

        let result = withUnsafeMutablePointer(to: &cpuInfo) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics(
                    mach_host_self(),
                    HOST_CPU_LOAD_INFO,
                    intPtr,
                    &count
                )
            }
        }

        guard result == KERN_SUCCESS else {
            return CPUMetrics(usagePercent: 0, coreCount: ProcessInfo.processInfo.processorCount, perCoreUsage: [])
        }

        let user = UInt64(cpuInfo.cpu_ticks.0) // CPU_STATE_USER
        let system = UInt64(cpuInfo.cpu_ticks.1) // CPU_STATE_SYSTEM
        let idle = UInt64(cpuInfo.cpu_ticks.2) // CPU_STATE_IDLE
        let nice = UInt64(cpuInfo.cpu_ticks.3) // CPU_STATE_NICE

        // Calculate delta from previous reading
        let userDelta = user - previousCPUTicks.user
        let systemDelta = system - previousCPUTicks.system
        let idleDelta = idle - previousCPUTicks.idle
        let niceDelta = nice - previousCPUTicks.nice

        previousCPUTicks = (user, system, idle, nice)

        let totalDelta = userDelta + systemDelta + idleDelta + niceDelta
        let usagePercent: Double
        if totalDelta > 0 {
            usagePercent = Double(userDelta + systemDelta + niceDelta) / Double(totalDelta) * 100.0
        } else {
            usagePercent = 0
        }

        let coreCount = ProcessInfo.processInfo.processorCount

        return CPUMetrics(
            usagePercent: min(100, max(0, usagePercent)),
            coreCount: coreCount,
            perCoreUsage: [] // Per-core requires processor_info, simplified here
        )
    }

    // MARK: - Memory

    /// Collect memory usage using Mach host_statistics64.
    public func collectMemory() -> MemoryMetrics {
        var vmStats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )

        let result = withUnsafeMutablePointer(to: &vmStats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(
                    mach_host_self(),
                    HOST_VM_INFO64,
                    intPtr,
                    &count
                )
            }
        }

        let totalMemory = UInt64(ProcessInfo.processInfo.physicalMemory)
        let pageSize = UInt64(vm_kernel_page_size)

        guard result == KERN_SUCCESS else {
            return MemoryMetrics(totalBytes: totalMemory, usedBytes: 0, availableBytes: totalMemory, swapUsedBytes: 0)
        }

        let activePages = UInt64(vmStats.active_count)
        let wiredPages = UInt64(vmStats.wire_count)
        let compressedPages = UInt64(vmStats.compressor_page_count)
        let freePages = UInt64(vmStats.free_count)
        let inactivePages = UInt64(vmStats.inactive_count)

        let usedBytes = (activePages + wiredPages + compressedPages) * pageSize
        let availableBytes = (freePages + inactivePages) * pageSize

        // Swap usage
        var swapUsage = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        sysctlbyname("vm.swapusage", &swapUsage, &swapSize, nil, 0)
        let swapUsed = UInt64(swapUsage.xsu_used)

        return MemoryMetrics(
            totalBytes: totalMemory,
            usedBytes: usedBytes,
            availableBytes: availableBytes,
            swapUsedBytes: swapUsed
        )
    }

    // MARK: - Disk

    /// Collect disk usage using statfs.
    public func collectDisk() -> DiskMetrics {
        var stat = statfs()
        guard statfs("/", &stat) == 0 else {
            return DiskMetrics(totalBytes: 0, usedBytes: 0, availableBytes: 0)
        }

        let blockSize = UInt64(stat.f_bsize)
        let totalBytes = UInt64(stat.f_blocks) * blockSize
        let availableBytes = UInt64(stat.f_bavail) * blockSize
        let usedBytes = totalBytes - availableBytes

        return DiskMetrics(
            totalBytes: totalBytes,
            usedBytes: usedBytes,
            availableBytes: availableBytes
        )
    }

    // MARK: - Network

    /// Collect network throughput using getifaddrs.
    public func collectNetwork() -> NetworkMetrics {
        var totalSent: UInt64 = 0
        var totalReceived: UInt64 = 0

        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return NetworkMetrics(bytesSent: 0, bytesReceived: 0, activeConnections: 0)
        }
        defer { freeifaddrs(ifaddr) }

        var ptr = firstAddr
        while true {
            let family = ptr.pointee.ifa_addr.pointee.sa_family
            if family == UInt8(AF_LINK) {
                let name = String(cString: ptr.pointee.ifa_name)
                // Skip loopback
                if name != "lo0" {
                    if let data = ptr.pointee.ifa_data {
                        let networkData = data.assumingMemoryBound(to: if_data.self).pointee
                        totalSent += UInt64(networkData.ifi_obytes)
                        totalReceived += UInt64(networkData.ifi_ibytes)
                    }
                }
            }
            guard let next = ptr.pointee.ifa_next else { break }
            ptr = next
        }

        // Calculate delta (bytes per interval)
        let sentDelta = totalSent >= previousNetBytes.sent ? totalSent - previousNetBytes.sent : 0
        let recvDelta = totalReceived >= previousNetBytes.received ? totalReceived - previousNetBytes.received : 0

        previousNetBytes = (totalSent, totalReceived)
        previousNetTimestamp = Date()

        return NetworkMetrics(
            bytesSent: sentDelta,
            bytesReceived: recvDelta,
            activeConnections: 0 // TODO: Count via netstat approach
        )
    }
}
