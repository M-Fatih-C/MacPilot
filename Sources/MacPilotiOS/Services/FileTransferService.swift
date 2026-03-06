// FileTransferService.swift
// MacPilot — MacPilot-iOS / Services
//
// iOS-side file transfer service.
// Manages download progress, upload chunking, and transfer state.

import Foundation
import Combine
import CryptoKit
import SharedCore

// MARK: - FileTransferService

/// Manages file transfers between iPhone and Mac.
@MainActor
public final class FileTransferService: ObservableObject {

    // MARK: - Published State

    @Published public var activeTransfers: [UUID: TransferProgress] = [:]
    @Published public var isTransferring: Bool = false

    // MARK: - Properties

    private let connection: AnyMacConnectionService
    private let chunkSize = NetworkConstants.fileChunkSize
    private var messageCancellable: AnyCancellable?

    // MARK: - Init

    public init(connection: AnyMacConnectionService) {
        self.connection = connection
        self.messageCancellable = NotificationCenter.default
            .publisher(for: .macPilotMessageReceived)
            .compactMap { $0.object as? Data }
            .receive(on: RunLoop.main)
            .sink { [weak self] data in
                guard let type = try? MessageProtocol.peekType(data), type == .fileDownloadChunk else {
                    return
                }
                guard let (_, chunk) = try? MessageProtocol.decodePlaintext(data, as: FileChunk.self) else {
                    return
                }
                self?.handleDownloadChunk(chunk)
            }
    }

    // MARK: - Download (Mac → iPhone)

    /// Request a file download from the Mac.
    ///
    /// - Parameter path: The file path on the Mac.
    public func requestDownload(path: String) {
        let request = FileDownloadRequest(
            path: path,
            transferId: UUID()
        )

        let progress = TransferProgress(
            transferId: request.transferId,
            fileName: (path as NSString).lastPathComponent,
            direction: .download,
            totalSize: 0,
            transferredBytes: 0
        )

        activeTransfers[request.transferId] = progress
        isTransferring = true

        do {
            let data = try MessageProtocol.encodePlaintext(request, type: .fileDownloadRequest)
            connection.send(data)
        } catch {
            print("[MacPilot][FileTransfer] Download request failed: \(error)")
            activeTransfers.removeValue(forKey: request.transferId)
        }
    }

    /// Handle an incoming download chunk from the Mac.
    public func handleDownloadChunk(_ chunk: FileChunk) {
        guard var progress = activeTransfers[chunk.transferId] else { return }

        progress.transferredBytes += UInt64(chunk.data.count)
        progress.totalSize = UInt64(chunk.totalChunks) * UInt64(chunkSize) // approximate
        progress.lastChunkIndex = chunk.chunkIndex

        // Save chunk to local file
        saveChunkLocally(chunk, fileName: progress.fileName)

        let isComplete = chunk.chunkIndex >= chunk.totalChunks - 1
        if isComplete {
            progress.isComplete = true
            activeTransfers[chunk.transferId] = progress
            isTransferring = activeTransfers.values.contains { !$0.isComplete }
        } else {
            activeTransfers[chunk.transferId] = progress
        }
    }

    // MARK: - Upload (iPhone → Mac)

    /// Upload a file to the Mac with chunked transfer.
    ///
    /// - Parameters:
    ///   - fileURL: Local file URL on the iPhone.
    ///   - destinationPath: Directory path on the Mac.
    public func uploadFile(fileURL: URL, destinationPath: String) async {
        let transferId = UUID()
        let fileName = fileURL.lastPathComponent

        guard let fileData = try? Data(contentsOf: fileURL) else {
            print("[MacPilot][FileTransfer] Cannot read file: \(fileURL)")
            return
        }

        let totalSize = UInt64(fileData.count)

        guard totalSize <= NetworkConstants.maxFileTransferSize else {
            print("[MacPilot][FileTransfer] File too large: \(totalSize) bytes")
            return
        }

        // Create progress tracking
        var progress = TransferProgress(
            transferId: transferId,
            fileName: fileName,
            direction: .upload,
            totalSize: totalSize,
            transferredBytes: 0
        )
        activeTransfers[transferId] = progress
        isTransferring = true

        // Send upload start message
        let startMsg = FileUploadStart(
            transferId: transferId,
            fileName: fileName,
            totalSize: totalSize,
            destinationPath: destinationPath
        )
        do {
            let data = try MessageProtocol.encodePlaintext(startMsg, type: .fileUploadStart)
            connection.send(data)
        } catch {
            print("[MacPilot][FileTransfer] Upload start failed: \(error)")
            return
        }

        // Send chunks
        let totalChunks = Int(ceil(Double(totalSize) / Double(chunkSize)))

        for i in 0..<totalChunks {
            let offset = i * chunkSize
            let end = min(offset + chunkSize, fileData.count)
            let chunkData = fileData[offset..<end]

            let checksum = sha256(Data(chunkData))

            let chunk = FileChunk(
                transferId: transferId,
                chunkIndex: i,
                totalChunks: totalChunks,
                offset: UInt64(offset),
                data: Data(chunkData),
                checksum: checksum
            )

            do {
                let data = try MessageProtocol.encodePlaintext(chunk, type: .fileUploadChunk)
                connection.send(data)
            } catch {
                print("[MacPilot][FileTransfer] Chunk \(i) send failed: \(error)")
                return
            }

            // Update progress
            progress.transferredBytes = UInt64(end)
            progress.lastChunkIndex = i
            activeTransfers[transferId] = progress

            // Small delay between chunks to avoid overwhelming the connection
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }

        // Mark complete
        progress.isComplete = true
        activeTransfers[transferId] = progress
        isTransferring = activeTransfers.values.contains { !$0.isComplete }
    }

    // MARK: - Cancel

    /// Cancel an active transfer.
    public func cancelTransfer(id: UUID) {
        activeTransfers.removeValue(forKey: id)
        isTransferring = activeTransfers.values.contains { !$0.isComplete }
    }

    /// Clear completed transfers.
    public func clearCompleted() {
        activeTransfers = activeTransfers.filter { !$0.value.isComplete }
    }

    // MARK: - Helpers

    private func saveChunkLocally(_ chunk: FileChunk, fileName: String) {
        let documentsPath = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!

        let filePath = documentsPath.appendingPathComponent(fileName)

        if chunk.chunkIndex == 0 {
            FileManager.default.createFile(atPath: filePath.path, contents: nil)
        }

        guard let fileHandle = try? FileHandle(forWritingTo: filePath) else { return }
        defer { try? fileHandle.close() }

        fileHandle.seek(toFileOffset: chunk.offset)
        fileHandle.write(chunk.data)
    }

    private func sha256(_ data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Models

/// Tracks progress of a single file transfer.
public struct TransferProgress: Identifiable, Sendable {
    public let id: UUID
    public let transferId: UUID
    public let fileName: String
    public let direction: TransferDirection
    public var totalSize: UInt64
    public var transferredBytes: UInt64
    public var lastChunkIndex: Int = -1
    public var isComplete: Bool = false

    public var progressFraction: Double {
        guard totalSize > 0 else { return 0 }
        return Double(transferredBytes) / Double(totalSize)
    }

    public var progressText: String {
        let percent = progressFraction * 100
        return String(format: "%.0f%%", percent)
    }

    public init(
        transferId: UUID,
        fileName: String,
        direction: TransferDirection,
        totalSize: UInt64,
        transferredBytes: UInt64
    ) {
        self.id = transferId
        self.transferId = transferId
        self.fileName = fileName
        self.direction = direction
        self.totalSize = totalSize
        self.transferredBytes = transferredBytes
    }
}

public enum TransferDirection: String, Sendable {
    case upload
    case download
}

/// Request to download a file.
public struct FileDownloadRequest: Codable, Sendable {
    public let path: String
    public let transferId: UUID
    public init(path: String, transferId: UUID) {
        self.path = path
        self.transferId = transferId
    }
}

/// Upload start message.
public struct FileUploadStart: Codable, Sendable {
    public let transferId: UUID
    public let fileName: String
    public let totalSize: UInt64
    public let destinationPath: String
    public init(transferId: UUID, fileName: String, totalSize: UInt64, destinationPath: String) {
        self.transferId = transferId
        self.fileName = fileName
        self.totalSize = totalSize
        self.destinationPath = destinationPath
    }
}
