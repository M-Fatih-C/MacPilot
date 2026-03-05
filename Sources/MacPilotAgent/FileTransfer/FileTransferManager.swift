// FileTransferManager.swift
// MacPilot — MacPilotAgent / FileTransfer
//
// Handles file system operations on the Mac:
//   - Directory browsing
//   - File download (Mac → iPhone) via chunked transfer
//   - File upload (iPhone → Mac) via chunked transfer

import Foundation
import SharedCore

// MARK: - FileTransferManager

/// Manages file system operations and chunked file transfers.
public final class FileTransferManager {

    // MARK: - Properties

    /// Active upload sessions keyed by transfer ID.
    private var activeUploads: [UUID: UploadSession] = [:]

    /// Download chunk size (256KB).
    private let chunkSize = NetworkConstants.fileChunkSize

    /// Maximum allowed file size for transfer (500MB).
    private let maxFileSize = NetworkConstants.maxFileTransferSize

    /// Queue for file I/O operations.
    private let fileQueue = DispatchQueue(label: "com.macpilot.filetransfer", qos: .utility)

    // MARK: - Init

    public init() {}

    // MARK: - Browse

    /// Browse a directory and return its contents.
    ///
    /// - Parameter path: The directory path (supports `~` for home).
    /// - Returns: Array of `FileItem` representing directory contents.
    public func browseDirectory(path: String) throws -> [FileItem] {
        let resolvedPath = resolvePath(path)
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: resolvedPath) else {
            throw FileTransferError.pathNotFound(resolvedPath)
        }

        let contents = try fileManager.contentsOfDirectory(atPath: resolvedPath)
        var items: [FileItem] = []

        for name in contents.sorted() {
            // Skip hidden files
            if name.hasPrefix(".") { continue }

            let fullPath = (resolvedPath as NSString).appendingPathComponent(name)

            guard let attrs = try? fileManager.attributesOfItem(atPath: fullPath) else {
                continue
            }

            let isDirectory = (attrs[.type] as? FileAttributeType) == .typeDirectory
            let size = (attrs[.size] as? UInt64) ?? 0
            let modifiedAt = (attrs[.modificationDate] as? Date) ?? Date()
            let permissions = posixPermissions(attrs[.posixPermissions] as? UInt16 ?? 0)

            items.append(FileItem(
                path: fullPath,
                name: name,
                isDirectory: isDirectory,
                size: size,
                modifiedAt: modifiedAt,
                permissions: permissions
            ))
        }

        // Sort: directories first, then alphabetically
        return items.sorted { item1, item2 in
            if item1.isDirectory != item2.isDirectory {
                return item1.isDirectory
            }
            return item1.name.localizedCaseInsensitiveCompare(item2.name) == .orderedAscending
        }
    }

    // MARK: - Download (Mac → iPhone)

    /// Prepare a file for chunked download.
    ///
    /// - Parameter path: The file path on the Mac.
    /// - Returns: A `TransferState` with initial metadata and total chunk count.
    public func prepareDownload(path: String) throws -> TransferState {
        let resolvedPath = resolvePath(path)
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: resolvedPath) else {
            throw FileTransferError.pathNotFound(resolvedPath)
        }

        let attrs = try fileManager.attributesOfItem(atPath: resolvedPath)
        let fileSize = (attrs[.size] as? UInt64) ?? 0

        guard fileSize <= maxFileSize else {
            throw FileTransferError.fileTooLarge(fileSize, max: maxFileSize)
        }

        let fileName = (resolvedPath as NSString).lastPathComponent

        return TransferState(
            fileName: fileName,
            totalSize: fileSize,
            status: .inProgress
        )
    }

    /// Read a single chunk from a file for download.
    ///
    /// - Parameters:
    ///   - path: The file path on the Mac.
    ///   - transferId: The transfer session ID.
    ///   - chunkIndex: The 0-based chunk index to read.
    /// - Returns: A `FileChunk` containing the chunk data and checksum.
    public func readChunk(path: String, transferId: UUID, chunkIndex: Int) throws -> FileChunk {
        let resolvedPath = resolvePath(path)

        guard let fileHandle = FileHandle(forReadingAtPath: resolvedPath) else {
            throw FileTransferError.readFailed(resolvedPath)
        }
        defer { fileHandle.closeFile() }

        let fileSize = fileHandle.seekToEndOfFile()
        let totalChunks = Int(ceil(Double(fileSize) / Double(chunkSize)))
        let offset = UInt64(chunkIndex) * UInt64(chunkSize)

        guard offset < fileSize else {
            throw FileTransferError.invalidChunkIndex(chunkIndex, total: totalChunks)
        }

        fileHandle.seek(toFileOffset: offset)
        let bytesToRead = min(chunkSize, Int(fileSize - offset))
        let data = fileHandle.readData(ofLength: bytesToRead)

        // Compute SHA-256 checksum
        let checksum = ChunkedTransfer.sha256Checksum(of: data)

        return FileChunk(
            transferId: transferId,
            chunkIndex: chunkIndex,
            totalChunks: totalChunks,
            offset: offset,
            data: data,
            checksum: checksum
        )
    }

    // MARK: - Upload (iPhone → Mac)

    /// Start a new upload session.
    ///
    /// - Parameters:
    ///   - transferId: Unique session ID.
    ///   - fileName: Name of the file being uploaded.
    ///   - totalSize: Total file size in bytes.
    ///   - destinationPath: Directory to save the file in.
    /// - Returns: The initial `TransferState`.
    public func startUpload(
        transferId: UUID,
        fileName: String,
        totalSize: UInt64,
        destinationPath: String
    ) throws -> TransferState {
        guard totalSize <= maxFileSize else {
            throw FileTransferError.fileTooLarge(totalSize, max: maxFileSize)
        }

        let resolvedDest = resolvePath(destinationPath)
        let fullPath = (resolvedDest as NSString).appendingPathComponent(fileName)

        // Create or truncate the file
        FileManager.default.createFile(atPath: fullPath, contents: nil)

        let session = UploadSession(
            transferId: transferId,
            filePath: fullPath,
            totalSize: totalSize
        )
        activeUploads[transferId] = session

        return TransferState(
            transferId: transferId,
            fileName: fileName,
            totalSize: totalSize,
            status: .inProgress
        )
    }

    /// Write a chunk to an active upload session.
    ///
    /// - Parameter chunk: The file chunk to write.
    /// - Returns: Updated `TransferState` reflecting progress.
    public func writeChunk(_ chunk: FileChunk) throws -> TransferState {
        guard let session = activeUploads[chunk.transferId] else {
            throw FileTransferError.noActiveUpload(chunk.transferId)
        }

        // Verify checksum
        let computedChecksum = ChunkedTransfer.sha256Checksum(of: chunk.data)
        guard computedChecksum == chunk.checksum else {
            throw FileTransferError.checksumMismatch(
                expected: chunk.checksum,
                actual: computedChecksum
            )
        }

        // Write chunk to file
        guard let fileHandle = FileHandle(forWritingAtPath: session.filePath) else {
            throw FileTransferError.writeFailed(session.filePath)
        }
        defer { fileHandle.closeFile() }

        fileHandle.seek(toFileOffset: chunk.offset)
        fileHandle.write(chunk.data)

        // Update session state
        var updatedSession = session
        updatedSession.transferredBytes += UInt64(chunk.data.count)
        updatedSession.lastChunkIndex = chunk.chunkIndex

        let isComplete = chunk.chunkIndex >= chunk.totalChunks - 1
        if isComplete {
            activeUploads.removeValue(forKey: chunk.transferId)
        } else {
            activeUploads[chunk.transferId] = updatedSession
        }

        return TransferState(
            transferId: chunk.transferId,
            fileName: (session.filePath as NSString).lastPathComponent,
            totalSize: session.totalSize,
            transferredBytes: updatedSession.transferredBytes,
            lastChunkIndex: chunk.chunkIndex,
            status: isComplete ? .completed : .inProgress
        )
    }

    /// Cancel an active upload.
    public func cancelUpload(transferId: UUID) {
        if let session = activeUploads.removeValue(forKey: transferId) {
            // Clean up partial file
            try? FileManager.default.removeItem(atPath: session.filePath)
            log("FileTransfer", "Cancelled upload \(transferId)")
        }
    }

    /// Get the current state of an upload (for resume).
    public func getUploadState(transferId: UUID) -> TransferState? {
        guard let session = activeUploads[transferId] else { return nil }
        return TransferState(
            transferId: transferId,
            fileName: (session.filePath as NSString).lastPathComponent,
            totalSize: session.totalSize,
            transferredBytes: session.transferredBytes,
            lastChunkIndex: session.lastChunkIndex,
            status: .inProgress
        )
    }

    // MARK: - Helpers

    /// Resolve `~` to the user's home directory.
    private func resolvePath(_ path: String) -> String {
        if path.hasPrefix("~") {
            return (path as NSString).expandingTildeInPath
        }
        return path
    }

    /// Convert POSIX permission bits to rwxrwxrwx string.
    private func posixPermissions(_ mode: UInt16) -> String {
        let chars: [Character] = ["r", "w", "x"]
        var result = ""
        for shift in stride(from: 6, through: 0, by: -3) {
            let bits = (mode >> shift) & 0x7
            for (i, c) in chars.enumerated() {
                result.append(bits & (1 << (2 - i)) != 0 ? c : "-")
            }
        }
        return result
    }
}

// MARK: - Upload Session

/// Internal state for an active upload.
struct UploadSession {
    let transferId: UUID
    let filePath: String
    let totalSize: UInt64
    var transferredBytes: UInt64 = 0
    var lastChunkIndex: Int = -1
}

// MARK: - Errors

/// File transfer errors.
public enum FileTransferError: Error, LocalizedError {
    case pathNotFound(String)
    case fileTooLarge(UInt64, max: UInt64)
    case readFailed(String)
    case writeFailed(String)
    case invalidChunkIndex(Int, total: Int)
    case noActiveUpload(UUID)
    case checksumMismatch(expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .pathNotFound(let path):
            return "[MacPilot][FileTransfer] Path not found: \(path)"
        case .fileTooLarge(let size, let max):
            return "[MacPilot][FileTransfer] File too large: \(size) bytes (max: \(max))"
        case .readFailed(let path):
            return "[MacPilot][FileTransfer] Failed to read file: \(path)"
        case .writeFailed(let path):
            return "[MacPilot][FileTransfer] Failed to write file: \(path)"
        case .invalidChunkIndex(let index, let total):
            return "[MacPilot][FileTransfer] Invalid chunk index \(index) (total: \(total))"
        case .noActiveUpload(let id):
            return "[MacPilot][FileTransfer] No active upload session: \(id)"
        case .checksumMismatch(let expected, let actual):
            return "[MacPilot][FileTransfer] Checksum mismatch: expected \(expected), got \(actual)"
        }
    }
}
