// NetworkingTests.swift
// MacPilot — Tests
//
// Validates networking components:
//   - NetworkConstants configuration
//   - Message encoding/decoding
//   - SystemMetrics models
//   - InputEvent models

import XCTest
@testable import SharedCore

final class NetworkingTests: XCTestCase {

    // MARK: - NetworkConstants

    func testDefaultPort() {
        XCTAssertEqual(NetworkConstants.port, 8443)
    }

    func testBonjourServiceType() {
        XCTAssertEqual(NetworkConstants.bonjourServiceType, "_macpilot._tcp")
    }

    func testTimeoutValues() {
        XCTAssertEqual(NetworkConstants.connectionTimeout, 10.0)
        XCTAssertEqual(NetworkConstants.reconnectBaseInterval, 1.0)
        XCTAssertEqual(NetworkConstants.reconnectMaxInterval, 30.0)
        XCTAssertEqual(NetworkConstants.pingInterval, 5.0)
    }

    func testMetricsRefreshInterval() {
        XCTAssertEqual(NetworkConstants.metricsRefreshInterval, 3.0)
    }

    func testInputEventRate() {
        XCTAssertEqual(NetworkConstants.maxInputEventsPerSecond, 200)
    }

    func testFileTransferConstants() {
        XCTAssertEqual(NetworkConstants.fileChunkSize, 256 * 1024)
        XCTAssertEqual(NetworkConstants.maxFileTransferSize, 500 * 1024 * 1024)
    }

    // MARK: - InputEvent Encoding

    func testMouseMoveEncodeDecode() throws {
        let event = InputEvent(
            type: .mouseMove,
            data: InputEventData(deltaX: 10.5, deltaY: -3.2)
        )

        let encoded = try MessageProtocol.encodePlaintext(event, type: .mouseMove)
        let decoded = try MessageProtocol.decodePlaintext(encoded, as: InputEvent.self)

        XCTAssertEqual(decoded.type, .mouseMove)
        XCTAssertEqual(decoded.payload.type, .mouseMove)
        XCTAssertEqual(decoded.payload.data.deltaX ?? 0, 10.5, accuracy: 0.001)
        XCTAssertEqual(decoded.payload.data.deltaY ?? 0, -3.2, accuracy: 0.001)
    }

    func testKeyEventEncodeDecode() throws {
        let event = InputEvent(
            type: .keyDown,
            data: InputEventData(keyCode: 0x08, modifiers: 0x100000)
        )

        let encoded = try MessageProtocol.encodePlaintext(event, type: .keyPress)
        let decoded = try MessageProtocol.decodePlaintext(encoded, as: InputEvent.self)

        XCTAssertEqual(decoded.payload.data.keyCode, 0x08)
        XCTAssertEqual(decoded.payload.data.modifiers, 0x100000)
    }

    // MARK: - SystemMetrics Models

    func testCPUMetrics() throws {
        let cpu = CPUMetrics(usagePercent: 45.2, coreCount: 10, perCoreUsage: [30, 50])
        let data = try JSONEncoder().encode(cpu)
        let decoded = try JSONDecoder().decode(CPUMetrics.self, from: data)

        XCTAssertEqual(decoded.usagePercent, 45.2, accuracy: 0.01)
        XCTAssertEqual(decoded.coreCount, 10)
        XCTAssertEqual(decoded.perCoreUsage.count, 2)
    }

    func testMemoryMetrics() throws {
        let mem = MemoryMetrics(
            totalBytes: 34_359_738_368,
            usedBytes: 20_000_000_000,
            availableBytes: 14_359_738_368,
            swapUsedBytes: 1_073_741_824
        )
        let data = try JSONEncoder().encode(mem)
        let decoded = try JSONDecoder().decode(MemoryMetrics.self, from: data)

        XCTAssertEqual(decoded.totalBytes, 34_359_738_368)
    }

    func testDiskMetrics() throws {
        let disk = DiskMetrics(
            totalBytes: 500_000_000_000,
            usedBytes: 250_000_000_000,
            availableBytes: 250_000_000_000
        )
        let data = try JSONEncoder().encode(disk)
        let decoded = try JSONDecoder().decode(DiskMetrics.self, from: data)
        XCTAssertEqual(decoded.totalBytes, 500_000_000_000)
    }

    func testNetworkMetrics() throws {
        let net = NetworkMetrics(bytesSent: 1024, bytesReceived: 2048, activeConnections: 5)
        let data = try JSONEncoder().encode(net)
        let decoded = try JSONDecoder().decode(NetworkMetrics.self, from: data)

        XCTAssertEqual(decoded.bytesSent, 1024)
        XCTAssertEqual(decoded.bytesReceived, 2048)
    }

    func testMacProcessInfo() throws {
        let proc = MacProcessInfo(pid: 1, name: "kernel_task", cpuPercent: 5.0, memoryBytes: 1_000)
        let data = try JSONEncoder().encode(proc)
        let decoded = try JSONDecoder().decode(MacProcessInfo.self, from: data)

        XCTAssertEqual(decoded.name, "kernel_task")
        XCTAssertEqual(decoded.pid, 1)
    }

    func testFullSystemMetricsRoundTrip() throws {
        let metrics = SystemMetrics(
            cpu: CPUMetrics(usagePercent: 12.5, coreCount: 10, perCoreUsage: []),
            memory: MemoryMetrics(totalBytes: 32_000_000_000, usedBytes: 16_000_000_000, availableBytes: 16_000_000_000, swapUsedBytes: 0),
            disk: DiskMetrics(totalBytes: 1_000_000_000_000, usedBytes: 500_000_000_000, availableBytes: 500_000_000_000),
            network: NetworkMetrics(bytesSent: 0, bytesReceived: 0, activeConnections: 0),
            topProcesses: [MacProcessInfo(pid: 1, name: "kernel_task", cpuPercent: 5.0, memoryBytes: 1_000_000)]
        )

        let encoded = try MessageProtocol.encodePlaintext(metrics, type: .metricsResponse)
        let decoded = try MessageProtocol.decodePlaintext(encoded, as: SystemMetrics.self)

        XCTAssertEqual(decoded.type, .metricsResponse)
        XCTAssertEqual(decoded.payload.cpu.usagePercent, 12.5, accuracy: 0.01)
        XCTAssertEqual(decoded.payload.topProcesses.count, 1)
        XCTAssertEqual(decoded.payload.topProcesses.first?.name, "kernel_task")
    }

    // MARK: - FileItem

    func testFileItemCodable() throws {
        let item = FileItem(
            path: "/Users/test/file.txt",
            name: "file.txt",
            isDirectory: false,
            size: 1024,
            modifiedAt: Date(),
            permissions: "rw-r--r--"
        )

        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(FileItem.self, from: data)
        XCTAssertEqual(decoded.name, "file.txt")
        XCTAssertEqual(decoded.size, 1024)
        XCTAssertFalse(decoded.isDirectory)
    }
}
