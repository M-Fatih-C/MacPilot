// main.swift
// MacPilot — MacPilotAgent (macOS Daemon)
//
// Runtime bootstrap for the real WSS backend:
// - secure WebSocket server
// - device-auth handshake
// - message routing (input/metrics/command/file)

import Foundation
import CryptoKit
import SharedCore

// MARK: - AgentRuntime

private final class AgentRuntime {
    private let server = WebSocketServer()
    private let inputProcessor = InputEventProcessor()
    private let metricsCollector = SystemMetricsCollector()
    private let fileTransferManager = FileTransferManager()
    private let identity: AgentIdentity

    private struct AuthSession: Sendable {
        let serverChallenge: Data
        var authenticated: Bool
        var deviceId: UUID?
    }

    private var authSessions: [UUID: AuthSession] = [:]

    init() throws {
        self.identity = try AgentIdentity()
        bindCallbacks()
    }

    func start() throws {
        log("Main", "MacPilotAgent v\(SharedCore.version) starting...")
        try server.start()
        log("Main", "WebSocket server running on port \(NetworkConstants.port)")
    }

    private func bindCallbacks() {
        server.onClientConnected = { [weak self] client in
            self?.handleClientConnected(client)
        }

        server.onClientDisconnected = { [weak self] in
            self?.handleClientDisconnected()
        }

        server.onMessageReceived = { [weak self] data, client in
            self?.handleIncomingMessage(data, from: client)
        }
    }

    private func handleClientConnected(_ client: ClientConnection) {
        do {
            let hello = ServerHello(
                deviceId: identity.deviceId,
                challenge: ServerHello.generateChallenge(),
                publicKey: identity.publicKeyData
            )

            authSessions[client.id] = AuthSession(
                serverChallenge: hello.challenge,
                authenticated: false,
                deviceId: nil
            )

            try send(hello, type: .authChallenge, to: client)
            log("Main", "Client connected \(client.id), sent auth challenge")
        } catch {
            log("Main", "Failed to initialize auth challenge: \(error.localizedDescription)")
            client.disconnect()
        }
    }

    private func handleClientDisconnected() {
        authSessions.removeAll()
        log("Main", "Client disconnected")
    }

    private func handleIncomingMessage(_ data: Data, from client: ClientConnection) {
        do {
            let messageType = try MessageProtocol.peekType(data)
            let isAuthenticated = authSessions[client.id]?.authenticated == true

            if !isAuthenticated {
                guard messageType == .authResponse else {
                    sendError("Authentication required before \(messageType.rawValue)", to: client)
                    client.disconnect()
                    return
                }
                try handleAuthRequest(data, from: client)
                return
            }

            switch messageType {
            case .mouseMove, .mouseClick, .mouseScroll, .keyPress, .keyRelease:
                try routeInput(data, from: client)
            case .metricsRequest:
                try routeMetrics(from: client)
            case .commandRequest:
                try routeCommand(data, from: client)
            case .fileBrowseRequest:
                try routeFileBrowse(data, from: client)
            case .fileDownloadRequest:
                try routeFileDownload(data, from: client)
            case .fileUploadStart:
                try routeFileUploadStart(data, from: client)
            case .fileUploadChunk:
                try routeFileUploadChunk(data, from: client)
            case .ping:
                try send(EmptyPayload(), type: .pong, to: client)
            default:
                sendError("Unsupported message type: \(messageType.rawValue)", to: client)
            }
        } catch {
            log("Router", "Message handling failed: \(error.localizedDescription)")
            sendError(error.localizedDescription, to: client)
        }
    }

    // MARK: - Handshake

    private func handleAuthRequest(_ data: Data, from client: ClientConnection) throws {
        guard var session = authSessions[client.id] else {
            throw AgentError.invalidSession
        }

        let (_, request) = try MessageProtocol.decodePlaintext(data, as: AuthRequest.self)

        let trustedDevice = try TrustedDeviceStore.shared.getTrustedDevice(id: request.deviceId)
        let trustedPublicKeyData = trustedDevice?.publicKey
        let verificationKeyData = trustedPublicKeyData ?? request.publicKey

        guard let keyData = verificationKeyData else {
            try send(
                AuthResponse(signature: Data(), status: .untrustedDevice),
                type: .authResponse,
                to: client
            )
            throw AgentError.untrustedDevice
        }

        if let trustedPublicKeyData, let presentedKey = request.publicKey, trustedPublicKeyData != presentedKey {
            try send(
                AuthResponse(signature: Data(), status: .signatureInvalid),
                type: .authResponse,
                to: client
            )
            throw AgentError.publicKeyMismatch
        }

        let publicKey = try DeviceIdentity.publicKey(from: keyData)
        let signature = try P256.Signing.ECDSASignature(derRepresentation: request.signature)

        guard DeviceIdentity.verify(signature: signature, for: session.serverChallenge, using: publicKey) else {
            try send(
                AuthResponse(signature: Data(), status: .signatureInvalid),
                type: .authResponse,
                to: client
            )
            throw AgentError.invalidSignature
        }

        if trustedDevice == nil {
            let bootstrapDevice = DeviceInfo(
                id: request.deviceId,
                deviceName: "iOS Device",
                platform: .iOS,
                publicKey: keyData
            )
            try TrustedDeviceStore.shared.addTrustedDevice(bootstrapDevice)
        } else {
            try? TrustedDeviceStore.shared.updateLastSeen(deviceId: request.deviceId)
        }

        let macSignature = try identity.sign(request.challenge).derRepresentation
        let response = AuthResponse(signature: macSignature, status: .authenticated)
        try send(response, type: .authResponse, to: client)

        session.authenticated = true
        session.deviceId = request.deviceId
        authSessions[client.id] = session
        log("Auth", "Client authenticated: \(request.deviceId)")
    }

    // MARK: - Input Router

    private func routeInput(_ data: Data, from client: ClientConnection) throws {
        _ = client
        let (_, event) = try MessageProtocol.decodePlaintext(data, as: InputEvent.self)
        _ = inputProcessor.process(event)
    }

    // MARK: - Metrics Router

    private func routeMetrics(from client: ClientConnection) throws {
        let metrics = metricsCollector.collect()
        try send(metrics, type: .metricsResponse, to: client)
    }

    // MARK: - Command Router

    private func routeCommand(_ data: Data, from client: ClientConnection) throws {
        let (_, request) = try MessageProtocol.decodePlaintext(data, as: AgentCommandRequest.self)
        let result = executeCommand(request.command)
        let response = AgentCommandResponse(
            commandId: request.commandId,
            success: result.success,
            output: result.output
        )
        try send(response, type: .commandResponse, to: client)
    }

    private func executeCommand(_ command: String) -> (success: Bool, output: String) {
        let map: [String: [String]] = [
            "shutdown": ["/usr/bin/osascript", "-e", "tell application \"System Events\" to shut down"],
            "restart": ["/usr/bin/osascript", "-e", "tell application \"System Events\" to restart"],
            "sleep": ["/usr/bin/osascript", "-e", "tell application \"System Events\" to sleep"],
            "lock": ["/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession", "-suspend"],
            "emptyTrash": ["/usr/bin/osascript", "-e", "tell application \"Finder\" to empty trash"]
        ]

        if command == "runScript" {
            return executeRunScriptCommand()
        }

        guard let args = map[command], let executable = args.first else {
            return (false, "Command not in allowlist: \(command)")
        }

        do {
            let output = try runProcess(executable: executable, arguments: Array(args.dropFirst()))
            return (true, output.isEmpty ? "OK" : output)
        } catch {
            return (false, error.localizedDescription)
        }
    }

    private func executeRunScriptCommand() -> (success: Bool, output: String) {
        let env = ProcessInfo.processInfo.environment
        let configuredScriptPath = env["MACPILOT_SCRIPT_PATH"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            if let configuredScriptPath, !configuredScriptPath.isEmpty {
                let exists = FileManager.default.fileExists(atPath: configuredScriptPath)
                guard exists else {
                    return (
                        false,
                        "MACPILOT_SCRIPT_PATH not found: \(configuredScriptPath)"
                    )
                }

                let output = try runProcess(
                    executable: "/usr/bin/osascript",
                    arguments: [configuredScriptPath]
                )
                return (true, output.isEmpty ? "runScript executed from MACPILOT_SCRIPT_PATH." : output)
            }

            let output = try runProcess(
                executable: "/usr/bin/osascript",
                arguments: [
                    "-e",
                    "display notification \"MacPilot runScript completed\" with title \"MacPilot\""
                ]
            )
            return (true, output.isEmpty ? "runScript executed default script." : output)
        } catch {
            return (false, error.localizedDescription)
        }
    }

    private func runProcess(executable: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if process.terminationStatus == 0 {
            return output
        }
        throw AgentError.commandFailed(exitCode: process.terminationStatus, output: output)
    }

    // MARK: - File Router

    private func routeFileBrowse(_ data: Data, from client: ClientConnection) throws {
        let (_, request) = try MessageProtocol.decodePlaintext(data, as: AgentFileBrowseRequest.self)
        let files = try fileTransferManager.browseDirectory(path: request.path)
        let response = AgentFileBrowseResponse(path: request.path, files: files)
        try send(response, type: .fileBrowseResponse, to: client)
    }

    private func routeFileDownload(_ data: Data, from client: ClientConnection) throws {
        let (_, request) = try MessageProtocol.decodePlaintext(data, as: AgentFileDownloadRequest.self)
        _ = try fileTransferManager.prepareDownload(path: request.path)

        var chunkIndex = 0
        while true {
            do {
                let chunk = try fileTransferManager.readChunk(
                    path: request.path,
                    transferId: request.transferId,
                    chunkIndex: chunkIndex
                )
                try send(chunk, type: .fileDownloadChunk, to: client)
                chunkIndex += 1
                if chunkIndex >= chunk.totalChunks {
                    break
                }
            } catch FileTransferError.invalidChunkIndex {
                break
            }
        }
    }

    private func routeFileUploadStart(_ data: Data, from client: ClientConnection) throws {
        let (_, request) = try MessageProtocol.decodePlaintext(data, as: AgentFileUploadStart.self)
        _ = try fileTransferManager.startUpload(
            transferId: request.transferId,
            fileName: request.fileName,
            totalSize: request.totalSize,
            destinationPath: request.destinationPath
        )
        try send(
            AgentFileUploadAck(transferId: request.transferId, acknowledgedChunk: -1, success: true),
            type: .fileUploadAck,
            to: client
        )
    }

    private func routeFileUploadChunk(_ data: Data, from client: ClientConnection) throws {
        let (_, chunk) = try MessageProtocol.decodePlaintext(data, as: FileChunk.self)
        _ = try fileTransferManager.writeChunk(chunk)
        try send(
            AgentFileUploadAck(
                transferId: chunk.transferId,
                acknowledgedChunk: chunk.chunkIndex,
                success: true
            ),
            type: .fileUploadAck,
            to: client
        )
    }

    // MARK: - Helpers

    private func send<T: Codable>(_ payload: T, type: MessageType, to client: ClientConnection) throws {
        let data = try MessageProtocol.encodePlaintext(payload, type: type)
        client.send(data)
    }

    private func sendError(_ message: String, to client: ClientConnection) {
        let payload = AgentErrorPayload(message: message)
        if let data = try? MessageProtocol.encodePlaintext(payload, type: .error) {
            client.send(data)
        }
    }
}

// MARK: - Local Payloads

private struct EmptyPayload: Codable, Sendable {}

private struct AgentCommandRequest: Codable, Sendable {
    let commandId: UUID
    let command: String
    let requiresAuth: Bool
}

private struct AgentCommandResponse: Codable, Sendable {
    let commandId: UUID
    let success: Bool
    let output: String
}

private struct AgentFileBrowseRequest: Codable, Sendable {
    let path: String
}

private struct AgentFileBrowseResponse: Codable, Sendable {
    let path: String
    let files: [FileItem]
}

private struct AgentFileDownloadRequest: Codable, Sendable {
    let path: String
    let transferId: UUID
}

private struct AgentFileUploadStart: Codable, Sendable {
    let transferId: UUID
    let fileName: String
    let totalSize: UInt64
    let destinationPath: String
}

private struct AgentFileUploadAck: Codable, Sendable {
    let transferId: UUID
    let acknowledgedChunk: Int
    let success: Bool
}

private struct AgentErrorPayload: Codable, Sendable {
    let message: String
}

private struct AgentIdentity {
    let deviceId: UUID
    let publicKeyData: Data
    private let privateKey: P256.Signing.PrivateKey

    init() throws {
        let key = try Self.loadOrCreatePrivateKey()
        self.privateKey = key
        self.publicKeyData = key.publicKey.x963Representation
        self.deviceId = Self.deriveDeviceId(from: publicKeyData)
    }

    func sign(_ data: Data) throws -> P256.Signing.ECDSASignature {
        try privateKey.signature(for: data)
    }

    private static func deriveDeviceId(from publicKeyData: Data) -> UUID {
        let hash = SHA256.hash(data: publicKeyData)
        let bytes = Array(hash.prefix(16))
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private static func loadOrCreatePrivateKey() throws -> P256.Signing.PrivateKey {
        let fm = FileManager.default
        let keyURL = identityKeyURL()

        if fm.fileExists(atPath: keyURL.path) {
            let data = try Data(contentsOf: keyURL)
            return try P256.Signing.PrivateKey(x963Representation: data)
        }

        let key = P256.Signing.PrivateKey()
        try fm.createDirectory(
            at: keyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try key.x963Representation.write(to: keyURL, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path)
        return key
    }

    private static func identityKeyURL() -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        return base
            .appendingPathComponent("MacPilot", isDirectory: true)
            .appendingPathComponent("agent-identity.key", isDirectory: false)
    }
}

private enum AgentError: LocalizedError {
    case invalidSession
    case untrustedDevice
    case publicKeyMismatch
    case invalidSignature
    case commandFailed(exitCode: Int32, output: String)

    var errorDescription: String? {
        switch self {
        case .invalidSession:
            return "Invalid auth session"
        case .untrustedDevice:
            return "Untrusted device"
        case .publicKeyMismatch:
            return "Public key mismatch for trusted device"
        case .invalidSignature:
            return "Signature verification failed"
        case .commandFailed(let exitCode, let output):
            if output.isEmpty {
                return "Command failed with exit code \(exitCode)"
            }
            return "Command failed (\(exitCode)): \(output)"
        }
    }
}

// MARK: - Main

private let runtime: AgentRuntime

do {
    runtime = try AgentRuntime()
    try runtime.start()
} catch {
    log("Main", "Failed to start server: \(error.localizedDescription)")
    exit(1)
}

RunLoop.current.run()
