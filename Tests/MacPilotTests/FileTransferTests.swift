// FileTransferTests.swift
// MacPilot — Tests
//
// Validates file transfer operations:
//   - SHA-256 checksums
//   - Chunk calculation
//   - FileChunk model
//   - TransferState model
//   - Size validation

import XCTest
import CryptoKit
@testable import SharedCore

final class FileTransferTests: XCTestCase {

    // MARK: - SHA-256

    func testSHA256Consistency() {
        let data = "MacPilot file transfer test".data(using: .utf8)!
        let hash1 = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
        let hash2 = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()

        XCTAssertEqual(hash1, hash2, "Same data → same checksum")
        XCTAssertEqual(hash1.count, 64, "SHA-256 hex = 64 chars")
    }

    func testSHA256DifferentData() {
        let data1 = "File A".data(using: .utf8)!
        let data2 = "File B".data(using: .utf8)!

        let hash1 = SHA256.hash(data: data1).compactMap { String(format: "%02x", $0) }.joined()
        let hash2 = SHA256.hash(data: data2).compactMap { String(format: "%02x", $0) }.joined()

        XCTAssertNotEqual(hash1, hash2)
    }

    // MARK: - Chunk Calculation

    func testChunkCountExact() {
        let chunkSize = UInt64(NetworkConstants.fileChunkSize)
        let fileSize = chunkSize * 4
        let chunks = Int(ceil(Double(fileSize) / Double(chunkSize)))
        XCTAssertEqual(chunks, 4)
    }

    func testChunkCountPartial() {
        let chunkSize = UInt64(NetworkConstants.fileChunkSize)
        let fileSize = chunkSize * 4 + 1
        let chunks = Int(ceil(Double(fileSize) / Double(chunkSize)))
        XCTAssertEqual(chunks, 5)
    }

    func testChunkCountSingleByte() {
        let chunkSize = UInt64(NetworkConstants.fileChunkSize)
        let chunks = Int(ceil(Double(1) / Double(chunkSize)))
        XCTAssertEqual(chunks, 1)
    }

    func testChunkCountZero() {
        let chunks = Int(ceil(Double(0) / Double(NetworkConstants.fileChunkSize)))
        XCTAssertEqual(chunks, 0)
    }

    // MARK: - FileChunk Model

    func testFileChunkCodable() throws {
        let chunk = FileChunk(
            transferId: UUID(),
            chunkIndex: 5,
            totalChunks: 20,
            offset: UInt64(5 * NetworkConstants.fileChunkSize),
            data: Data(repeating: 0xAA, count: 100),
            checksum: String(repeating: "ab", count: 32)
        )

        let encoded = try JSONEncoder().encode(chunk)
        let decoded = try JSONDecoder().decode(FileChunk.self, from: encoded)

        XCTAssertEqual(decoded.chunkIndex, 5)
        XCTAssertEqual(decoded.totalChunks, 20)
        XCTAssertEqual(decoded.data.count, 100)
        XCTAssertEqual(decoded.checksum, chunk.checksum)
    }

    // MARK: - TransferState Model

    func testTransferStateCodable() throws {
        let state = TransferState(
            fileName: "photo.jpg",
            totalSize: 5_242_880,
            transferredBytes: 2_621_440,
            lastChunkIndex: 9,
            status: .inProgress
        )

        let encoded = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(TransferState.self, from: encoded)

        XCTAssertEqual(decoded.fileName, "photo.jpg")
        XCTAssertEqual(decoded.totalSize, 5_242_880)
        XCTAssertEqual(decoded.transferredBytes, 2_621_440)
        XCTAssertEqual(decoded.status, .inProgress)
    }

    func testTransferProgress50Percent() {
        let state = TransferState(
            fileName: "test.zip",
            totalSize: 1_000_000,
            transferredBytes: 500_000,
            status: .inProgress
        )

        let progress = Double(state.transferredBytes) / Double(state.totalSize)
        XCTAssertEqual(progress, 0.5, accuracy: 0.001)
    }

    func testTransferProgressComplete() {
        let state = TransferState(
            fileName: "test.zip",
            totalSize: 1_000_000,
            transferredBytes: 1_000_000,
            status: .completed
        )

        XCTAssertEqual(state.status, .completed)
        let progress = Double(state.transferredBytes) / Double(state.totalSize)
        XCTAssertEqual(progress, 1.0, accuracy: 0.001)
    }

    // MARK: - Size Limits

    func testFileSizeWithinLimit() {
        let max = NetworkConstants.maxFileTransferSize
        XCTAssertTrue(UInt64(100) <= max)
        XCTAssertTrue(UInt64(1_000_000) <= max)
        XCTAssertTrue(max <= max)
        XCTAssertFalse(max + 1 <= max)
    }

    // MARK: - FileItem Model

    func testFileItemDirectory() throws {
        let dir = FileItem(
            path: "/Users/test/Documents",
            name: "Documents",
            isDirectory: true,
            size: 0,
            modifiedAt: Date(),
            permissions: "rwxr-xr-x"
        )

        XCTAssertTrue(dir.isDirectory)
        XCTAssertEqual(dir.name, "Documents")

        let data = try JSONEncoder().encode(dir)
        let decoded = try JSONDecoder().decode(FileItem.self, from: data)
        XCTAssertTrue(decoded.isDirectory)
    }
}
