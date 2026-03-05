// ChunkedTransfer.swift
// MacPilot — MacPilotAgent / FileTransfer
//
// Utilities for chunked file transfer with integrity verification.
// Chunk size: 256KB | Max file: 500MB | Checksum: SHA-256

import Foundation
import CryptoKit
import SharedCore

// MARK: - ChunkedTransfer

/// Utilities for chunked file transfer operations.
public enum ChunkedTransfer {

    // MARK: - Checksum

    /// Compute SHA-256 checksum of data.
    ///
    /// - Parameter data: The data to checksum.
    /// - Returns: Hex-encoded SHA-256 hash string.
    public static func sha256Checksum(of data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Verify a chunk's data against its checksum.
    ///
    /// - Parameter chunk: The chunk to verify.
    /// - Returns: `true` if the checksum matches.
    public static func verifyChunk(_ chunk: FileChunk) -> Bool {
        let computed = sha256Checksum(of: chunk.data)
        return computed == chunk.checksum
    }

    // MARK: - Chunk Calculation

    /// Calculate the total number of chunks for a file.
    ///
    /// - Parameter fileSize: Total file size in bytes.
    /// - Returns: Number of chunks needed.
    public static func totalChunks(fileSize: UInt64) -> Int {
        let chunkSize = UInt64(NetworkConstants.fileChunkSize)
        return Int(ceil(Double(fileSize) / Double(chunkSize)))
    }

    /// Calculate the byte range for a specific chunk.
    ///
    /// - Parameters:
    ///   - chunkIndex: The 0-based chunk index.
    ///   - fileSize: The total file size.
    /// - Returns: Tuple of (offset, length) for this chunk.
    public static func chunkRange(index: Int, fileSize: UInt64) -> (offset: UInt64, length: Int) {
        let chunkSize = UInt64(NetworkConstants.fileChunkSize)
        let offset = UInt64(index) * chunkSize
        let remaining = fileSize - offset
        let length = Int(min(chunkSize, remaining))
        return (offset, length)
    }

    // MARK: - Progress

    /// Calculate transfer progress as a fraction (0.0 – 1.0).
    ///
    /// - Parameter state: The current transfer state.
    /// - Returns: Progress fraction.
    public static func progress(of state: TransferState) -> Double {
        guard state.totalSize > 0 else { return 0 }
        return Double(state.transferredBytes) / Double(state.totalSize)
    }

    /// Format transfer progress as a human-readable string.
    ///
    /// - Parameter state: The current transfer state.
    /// - Returns: Formatted string like "12.5 MB / 100.0 MB (12.5%)".
    public static func progressText(of state: TransferState) -> String {
        let transferred = formatBytes(state.transferredBytes)
        let total = formatBytes(state.totalSize)
        let percent = progress(of: state) * 100
        return "\(transferred) / \(total) (\(String(format: "%.1f", percent))%)"
    }

    // MARK: - Validation

    /// Validate that a file is within transfer size limits.
    ///
    /// - Parameter fileSize: File size in bytes.
    /// - Returns: `true` if the file is within the 500MB limit.
    public static func isWithinSizeLimit(_ fileSize: UInt64) -> Bool {
        return fileSize <= NetworkConstants.maxFileTransferSize
    }

    // MARK: - File Splitting

    /// Split a file into chunks for transfer.
    ///
    /// - Parameters:
    ///   - path: The file path to read.
    ///   - transferId: The transfer session ID.
    /// - Returns: Array of `FileChunk` objects.
    public static func splitFile(at path: String, transferId: UUID) throws -> [FileChunk] {
        guard let fileHandle = FileHandle(forReadingAtPath: path) else {
            throw FileTransferError.readFailed(path)
        }
        defer { fileHandle.closeFile() }

        let fileSize = fileHandle.seekToEndOfFile()
        fileHandle.seek(toFileOffset: 0)

        let numChunks = totalChunks(fileSize: fileSize)
        var chunks: [FileChunk] = []

        for i in 0..<numChunks {
            let (offset, length) = chunkRange(index: i, fileSize: fileSize)
            fileHandle.seek(toFileOffset: offset)
            let data = fileHandle.readData(ofLength: length)
            let checksum = sha256Checksum(of: data)

            chunks.append(FileChunk(
                transferId: transferId,
                chunkIndex: i,
                totalChunks: numChunks,
                offset: offset,
                data: data,
                checksum: checksum
            ))
        }

        return chunks
    }

    // MARK: - Helpers

    /// Format bytes into a human-readable string.
    private static func formatBytes(_ bytes: UInt64) -> String {
        let kb = Double(bytes) / 1024
        let mb = kb / 1024
        let gb = mb / 1024
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        if mb >= 1 { return String(format: "%.1f MB", mb) }
        if kb >= 1 { return String(format: "%.0f KB", kb) }
        return "\(bytes) B"
    }
}
