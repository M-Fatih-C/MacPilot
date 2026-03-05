// ProcessMonitor.swift
// MacPilot — MacPilotAgent / System
//
// Collects top running processes sorted by CPU/memory usage.
// Uses sysctl and proc_pidinfo.

import Foundation
import SharedCore
#if canImport(Darwin)
import Darwin
#endif

// MARK: - ProcessMonitor

/// Monitors running processes and returns top consumers.
public final class ProcessMonitor {

    public init() {}

    // MARK: - Get Processes

    /// Get the top N processes sorted by CPU usage.
    ///
    /// - Parameter limit: Maximum number of processes to return (default: 10).
    /// - Returns: Array of `ProcessInfo` sorted by CPU usage (descending).
    public func getTopProcesses(limit: Int = 10) -> [MacProcessInfo] {
        let pids = getAllPIDs()
        var processes: [MacProcessInfo] = []

        for pid in pids {
            if let info = getProcessInfo(pid: pid) {
                processes.append(info)
            }
        }

        // Sort by CPU usage descending, return top N
        return Array(
            processes
                .sorted { $0.cpuPercent > $1.cpuPercent }
                .prefix(limit)
        )
    }

    // MARK: - Get All PIDs

    /// Get all running process IDs using sysctl.
    private func getAllPIDs() -> [pid_t] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size: Int = 0

        // First call to get required buffer size
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0 else {
            return []
        }

        let count = size / MemoryLayout<kinfo_proc>.stride
        var procList = [kinfo_proc](repeating: kinfo_proc(), count: count)

        guard sysctl(&mib, UInt32(mib.count), &procList, &size, nil, 0) == 0 else {
            return []
        }

        let actualCount = size / MemoryLayout<kinfo_proc>.stride
        return procList.prefix(actualCount).map { $0.kp_proc.p_pid }
    }

    // MARK: - Get Process Info

    /// Get info for a single process.
    private func getProcessInfo(pid: pid_t) -> MacProcessInfo? {
        // Skip kernel process
        guard pid > 0 else { return nil }

        // Get process name
        var nameBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let nameLength = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
        guard nameLength > 0 else { return nil }
        let name = String(cString: nameBuffer)

        // Skip system daemons with empty names
        guard !name.isEmpty else { return nil }

        // Get task info for CPU time and memory
        var taskInfo = proc_taskinfo()
        let taskInfoSize = Int32(MemoryLayout<proc_taskinfo>.size)
        let result = proc_pidinfo(
            pid,
            PROC_PIDTASKINFO,
            0,
            &taskInfo,
            taskInfoSize
        )

        guard result == taskInfoSize else { return nil }

        // Calculate approximate CPU % from total time
        let totalTime = Double(taskInfo.pti_total_user + taskInfo.pti_total_system) / 1_000_000_000.0
        // Simple heuristic: recent CPU usage based on thread count and time
        let cpuPercent = min(100.0, totalTime * 0.01)

        let memoryBytes = UInt64(taskInfo.pti_resident_size)

        return MacProcessInfo(
            pid: pid,
            name: name,
            cpuPercent: cpuPercent,
            memoryBytes: memoryBytes
        )
    }
}
