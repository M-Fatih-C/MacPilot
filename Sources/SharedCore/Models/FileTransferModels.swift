// FileTransferModels.swift
// MacPilot — SharedCore
//
// Data models for file browsing and resumable file transfer.

import Foundation

/// Represents a file or directory entry.
public struct FileItem: Codable, Sendable, Identifiable {
    /// Full path on the Mac.
    public let path: String

    /// File or directory name.
    public let name: String

    /// Whether this is a directory.
    public let isDirectory: Bool

    /// File size in bytes (0 for directories).
    public let size: UInt64

    /// Last modification date.
    public let modifiedAt: Date

    /// POSIX permission string (e.g. "rwxr-xr-x").
    public let permissions: String

    public var id: String { path }

    public init(
        path: String,
        name: String,
        isDirectory: Bool,
        size: UInt64,
        modifiedAt: Date,
        permissions: String
    ) {
        self.path = path
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.modifiedAt = modifiedAt
        self.permissions = permissions
    }
}

/// A single chunk of a file being transferred.
public struct FileChunk: Codable, Sendable {
    /// Unique transfer session identifier.
    public let transferId: UUID

    /// Index of this chunk (0-based).
    public let chunkIndex: Int

    /// Total number of chunks in the transfer.
    public let totalChunks: Int

    /// Byte offset in the file.
    public let offset: UInt64

    /// Chunk data (max 256KB).
    public let data: Data

    /// SHA-256 checksum of this chunk's data.
    public let checksum: String

    public init(
        transferId: UUID,
        chunkIndex: Int,
        totalChunks: Int,
        offset: UInt64,
        data: Data,
        checksum: String
    ) {
        self.transferId = transferId
        self.chunkIndex = chunkIndex
        self.totalChunks = totalChunks
        self.offset = offset
        self.data = data
        self.checksum = checksum
    }
}

/// Tracks the state of an ongoing file transfer (for resume support).
public struct TransferState: Codable, Sendable, Identifiable {
    /// Unique transfer session identifier.
    public let transferId: UUID

    /// Name of the file being transferred.
    public let fileName: String

    /// Total file size in bytes.
    public let totalSize: UInt64

    /// Bytes transferred so far.
    public var transferredBytes: UInt64

    /// Last successfully acknowledged chunk index (resume point).
    public var lastChunkIndex: Int

    /// Current transfer status.
    public var status: TransferStatus

    public var id: UUID { transferId }

    public init(
        transferId: UUID = UUID(),
        fileName: String,
        totalSize: UInt64,
        transferredBytes: UInt64 = 0,
        lastChunkIndex: Int = -1,
        status: TransferStatus = .pending
    ) {
        self.transferId = transferId
        self.fileName = fileName
        self.totalSize = totalSize
        self.transferredBytes = transferredBytes
        self.lastChunkIndex = lastChunkIndex
        self.status = status
    }
}

/// File transfer status.
public enum TransferStatus: String, Codable, Sendable {
    case pending
    case inProgress
    case paused
    case completed
    case failed
}

/// Maximum chunk size: 256KB.
public let fileChunkSize: Int = 256 * 1024

/// Maximum file size for transfer: 500MB.
public let maxFileTransferSize: UInt64 = 500 * 1024 * 1024
