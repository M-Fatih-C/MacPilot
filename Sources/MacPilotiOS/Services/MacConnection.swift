// MacConnection.swift
// MacPilot — MacPilot-iOS / Services
//
// WebSocket client that connects to MacPilotAgent.
// Uses Network.framework NWConnection with TLS 1.3.
// Implements automatic reconnection with exponential backoff.

import Foundation
import Network
import Combine
import CryptoKit
import Security
import SharedCore

// MARK: - Service Protocol

@MainActor
public protocol MacConnectionService: ObservableObject
where ObjectWillChangePublisher == ObservableObjectPublisher {
    var connectionState: ConnectionState { get }
    var isConnected: Bool { get }
    var onMessageReceived: ((Data) -> Void)? { get set }

    func connect(to endpoint: NWEndpoint)
    func connect(host: String, port: UInt16)
    func disconnect()
    func send(_ data: Data)
}

@MainActor
public final class AnyMacConnectionService: MacConnectionService {
    private var base: any MacConnectionService
    private var changeCancellable: AnyCancellable?

    public init(_ base: any MacConnectionService) {
        self.base = base
        self.changeCancellable = base.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
    }

    public var connectionState: ConnectionState { base.connectionState }
    public var isConnected: Bool { base.isConnected }

    public var onMessageReceived: ((Data) -> Void)? {
        get { base.onMessageReceived }
        set { base.onMessageReceived = newValue }
    }

    public func connect(to endpoint: NWEndpoint) {
        base.connect(to: endpoint)
    }

    public func connect(host: String, port: UInt16 = NetworkConstants.port) {
        base.connect(host: host, port: port)
    }

    public func disconnect() {
        base.disconnect()
    }

    public func send(_ data: Data) {
        base.send(data)
    }
}

public enum AppRuntimeMode {
    case demo
    case live
}

@MainActor
public enum AppEnvironment {
    public static var mode: AppRuntimeMode = .live

    public static func makeConnectionService() -> AnyMacConnectionService {
        switch mode {
        case .demo:
            return AnyMacConnectionService(MockMacConnection())
        case .live:
            return AnyMacConnectionService(RealMacConnection())
        }
    }
}

public extension Notification.Name {
    static let macPilotMessageReceived = Notification.Name("com.macpilot.message.received")
}

// MARK: - Real Connection

/// Manages the persistent WebSocket connection from iPhone to Mac.
///
/// Features:
/// - TLS 1.3 with certificate pinning
/// - Automatic reconnection with exponential backoff
/// - Connection state machine integration
/// - Message send/receive with callbacks
@MainActor
public final class MacConnection: ObservableObject {

    // MARK: - Published State

    @Published public private(set) var connectionState: ConnectionState = .idle
    @Published public private(set) var isConnected: Bool = false

    // MARK: - Properties

    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.macpilot.ios.connection", qos: .userInteractive)
    private var stateMachine = ConnectionStateMachine()
    private var reconnectTimer: DispatchSourceTimer?
    private var pendingClientChallenge: Data?
    private var pendingServerDeviceId: UUID?
    private var pendingServerPublicKey: Data?

    /// The Mac endpoint to connect to (set after Bonjour discovery or pairing).
    private var macEndpoint: NWEndpoint?

    /// Callback when a WebSocket message is received.
    public var onMessageReceived: ((Data) -> Void)?

    /// Callback for connection state changes.
    public var onStateChanged: ((ConnectionState) -> Void)?

    // MARK: - Init

    public init() {}

    // MARK: - Connect

    /// Connect to a discovered Mac endpoint.
    ///
    /// - Parameter endpoint: The NWEndpoint from Bonjour discovery.
    public func connect(to endpoint: NWEndpoint) {
        macEndpoint = endpoint
        startConnection(to: endpoint)
    }

    /// Connect to a specific host and port.
    ///
    /// - Parameters:
    ///   - host: The hostname or IP address.
    ///   - port: The port number (default: 8443).
    public func connect(host: String, port: UInt16 = NetworkConstants.port) {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!
        )
        macEndpoint = endpoint
        startConnection(to: endpoint)
    }

    /// Disconnect and stop reconnection.
    public func disconnect() {
        cancelReconnectTimer()
        stateMachine.handle(.userDisconnect)
        updateState()
        connection?.cancel()
        connection = nil
        resetHandshakeState()
    }

    // MARK: - Send

    /// Send binary data over the WebSocket.
    public func send(_ data: Data) {
        guard isConnected else { return }
        sendRaw(data)
    }

    /// Send data regardless of `isConnected` (used by auth handshake).
    private func sendRaw(_ data: Data) {
        guard let connection = connection else { return }

        let metadata = NWProtocolWebSocket.Metadata(opcode: .binary)
        let context = NWConnection.ContentContext(
            identifier: "MacPilotMessage",
            metadata: [metadata]
        )

        connection.send(
            content: data,
            contentContext: context,
            isComplete: true,
            completion: .contentProcessed { [weak self] error in
                if let error = error {
                    print("[MacPilot][Connection] Send error: \(error.localizedDescription)")
                    Task { @MainActor [weak self] in
                        self?.handleConnectionLost()
                    }
                }
            }
        )
    }

    // MARK: - Private: Connection Setup

    private func startConnection(to endpoint: NWEndpoint) {
        // Cancel existing connection
        connection?.cancel()
        resetHandshakeState()

        let parameters = createClientParameters()

        let nwConnection = NWConnection(to: endpoint, using: parameters)
        self.connection = nwConnection

        stateMachine.handle(.discovered)
        updateState()

        nwConnection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                self?.handleNWState(state)
            }
        }

        nwConnection.start(queue: queue)
    }

    /// Create NWParameters with TLS 1.3 and WebSocket protocol.
    private func createClientParameters() -> NWParameters {
        let tlsOptions = NWProtocolTLS.Options()

        // TLS 1.3 minimum
        let securityOptions = tlsOptions.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(securityOptions, .TLSv13)

        // Certificate pinning with TOFU fallback.
        // If a certificate is pinned, only that fingerprint is accepted.
        // On first connection, pin the presented server certificate fingerprint.
        sec_protocol_options_set_verify_block(securityOptions, { _, trust, completionHandler in
            let trustRef = sec_trust_copy_ref(trust).takeRetainedValue()
            guard let serverPublicKeyData = Self.serverPublicKeyData(from: trustRef) else {
                completionHandler(false)
                return
            }

            do {
                let manager = CertificateManager.shared
                let fingerprint = CertificateManager.fingerprint(of: serverPublicKeyData)

                if let pinned = try manager.getPinnedFingerprint() {
                    completionHandler(fingerprint == pinned)
                } else {
                    try manager.pinCertificateFingerprint(fingerprint)
                    completionHandler(true)
                }
            } catch {
                completionHandler(false)
            }
        }, queue)

        // WebSocket protocol
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        wsOptions.maximumMessageSize = 1024 * 1024

        let parameters = NWParameters(tls: tlsOptions)
        parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        return parameters
    }

    private static func serverPublicKeyData(from trust: SecTrust) -> Data? {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let certificate = chain.first,
              let key = SecCertificateCopyKey(certificate),
              let raw = SecKeyCopyExternalRepresentation(key, nil) else {
            return nil
        }
        return raw as Data
    }

    // MARK: - Private: State Handling

    private func handleNWState(_ state: NWConnection.State) {
        switch state {
        case .ready:
            stateMachine.handle(.tcpConnected)
            updateState()
            receiveMessage()

        case .failed(let error):
            print("[MacPilot][Connection] Failed: \(error.localizedDescription)")
            handleConnectionLost()

        case .cancelled:
            stateMachine.handle(.disconnected)
            updateState()

        case .waiting(let error):
            print("[MacPilot][Connection] Waiting: \(error.localizedDescription)")
            handleConnectionLost()

        default:
            break
        }
    }

    private func handleConnectionLost() {
        stateMachine.handle(.disconnected)
        updateState()
        connection?.cancel()
        connection = nil
        resetHandshakeState()
        scheduleReconnect()
    }

    private func updateState() {
        connectionState = stateMachine.state
        isConnected = stateMachine.state == .connected
        onStateChanged?(stateMachine.state)
    }

    // MARK: - Private: Receive

    private func receiveMessage() {
        guard let connection = connection else { return }

        connection.receiveMessage { [weak self] data, context, isComplete, error in
            guard let self = self else { return }

            if let error = error {
                print("[MacPilot][Connection] Receive error: \(error.localizedDescription)")
                Task { @MainActor [weak self] in
                    self?.handleConnectionLost()
                }
                return
            }

            if let data = data, !data.isEmpty {
                Task { @MainActor [weak self] in
                    self?.handleIncomingMessage(data)
                }
            }

            // Continue receiving
            Task { @MainActor [weak self] in
                if self?.connection != nil {
                    self?.receiveMessage()
                }
            }
        }
    }

    private func handleIncomingMessage(_ data: Data) {
        guard let messageType = try? MessageProtocol.peekType(data) else {
            print("[MacPilot][Connection] Failed to parse incoming message envelope")
            return
        }

        switch messageType {
        case .authChallenge:
            handleAuthChallenge(data)
        case .authResponse where connectionState == .authenticating || connectionState == .keyExchange:
            handleAuthResponse(data)
        default:
            // Only forward app-level messages after secure auth finishes.
            guard isConnected else {
                print("[MacPilot][Connection] Ignored \(messageType.rawValue) before auth completion")
                return
            }
            onMessageReceived?(data)
        }
    }

    private func handleAuthChallenge(_ data: Data) {
        do {
            let (_, hello) = try MessageProtocol.decodePlaintext(data, as: ServerHello.self)
            pendingServerDeviceId = hello.deviceId
            pendingServerPublicKey = hello.publicKey

            let identity = DeviceIdentity.shared
            let myDeviceId = try identity.getDeviceId()
            let myPublicKey = try identity.getPublicKeyData()
            let signature = try identity.sign(hello.challenge)
            let clientChallenge = ServerHello.generateChallenge()

            pendingClientChallenge = clientChallenge

            let request = AuthRequest(
                deviceId: myDeviceId,
                signature: signature.derRepresentation,
                challenge: clientChallenge,
                publicKey: myPublicKey
            )
            let encoded = try MessageProtocol.encodePlaintext(request, type: .authResponse)
            sendRaw(encoded)
        } catch {
            print("[MacPilot][Connection] Auth challenge handling failed: \(error.localizedDescription)")
            failAuthentication()
        }
    }

    private func handleAuthResponse(_ data: Data) {
        do {
            let (_, response) = try MessageProtocol.decodePlaintext(data, as: AuthResponse.self)
            guard response.status == .authenticated else {
                print("[MacPilot][Connection] Auth rejected with status: \(response.status.rawValue)")
                failAuthentication()
                return
            }

            guard let serverDeviceId = pendingServerDeviceId,
                  let clientChallenge = pendingClientChallenge else {
                failAuthentication()
                return
            }

            let trustedDevice = try TrustedDeviceStore.shared.getTrustedDevice(id: serverDeviceId)
            let trustedPublicKeyData = trustedDevice?.publicKey
            let verificationKeyData = trustedPublicKeyData ?? pendingServerPublicKey

            guard let keyData = verificationKeyData else {
                print("[MacPilot][Connection] Missing server public key for auth verification")
                failAuthentication()
                return
            }

            if let trustedPublicKeyData, let advertisedPublicKey = pendingServerPublicKey, trustedPublicKeyData != advertisedPublicKey {
                print("[MacPilot][Connection] Server public key mismatch for trusted device")
                failAuthentication()
                return
            }

            let serverPublicKey = try DeviceIdentity.publicKey(from: keyData)
            let serverSignature = try P256.Signing.ECDSASignature(derRepresentation: response.signature)
            guard DeviceIdentity.verify(signature: serverSignature, for: clientChallenge, using: serverPublicKey) else {
                print("[MacPilot][Connection] Server signature verification failed")
                failAuthentication()
                return
            }

            if trustedDevice == nil {
                let newTrustedDevice = DeviceInfo(
                    id: serverDeviceId,
                    deviceName: "MacPilot Agent",
                    platform: .macOS,
                    publicKey: keyData
                )
                try TrustedDeviceStore.shared.addTrustedDevice(newTrustedDevice)
            } else {
                try? TrustedDeviceStore.shared.updateLastSeen(deviceId: serverDeviceId)
            }

            stateMachine.handle(.authSucceeded)
            stateMachine.handle(.keyExchangeDone)
            updateState()
            resetHandshakeState()
        } catch {
            print("[MacPilot][Connection] Auth response handling failed: \(error.localizedDescription)")
            failAuthentication()
        }
    }

    private func failAuthentication() {
        stateMachine.handle(.authFailed)
        updateState()
        connection?.cancel()
        connection = nil
        resetHandshakeState()
    }

    private func resetHandshakeState() {
        pendingClientChallenge = nil
        pendingServerDeviceId = nil
        pendingServerPublicKey = nil
    }

    // MARK: - Private: Reconnection

    private func scheduleReconnect() {
        guard stateMachine.state == .reconnecting else { return }

        let interval = stateMachine.reconnectInterval
        print("[MacPilot][Connection] Reconnecting in \(interval)s (attempt \(stateMachine.reconnectAttempts + 1))...")

        cancelReconnectTimer()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval)
        timer.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self, let endpoint = self.macEndpoint else { return }
                self.stateMachine.handle(.retryScheduled)
                self.updateState()
                if self.stateMachine.state == .connecting {
                    self.startConnection(to: endpoint)
                }
            }
        }
        timer.resume()
        reconnectTimer = timer
    }

    private func cancelReconnectTimer() {
        reconnectTimer?.cancel()
        reconnectTimer = nil
    }
}

extension MacConnection: MacConnectionService {}
public typealias RealMacConnection = MacConnection

// MARK: - Mock Connection

@MainActor
public final class MockMacConnection: MacConnectionService {
    @Published public private(set) var connectionState: ConnectionState = .idle
    @Published public private(set) var isConnected: Bool = false

    public var onMessageReceived: ((Data) -> Void)?

    public init() {
        connectToDemo()
    }

    public func connect(to endpoint: NWEndpoint) {
        _ = endpoint
        connectToDemo()
    }

    public func connect(host: String, port: UInt16 = NetworkConstants.port) {
        _ = host
        _ = port
        connectToDemo()
    }

    public func disconnect() {
        connectionState = .disconnected
        isConnected = false
    }

    public func send(_ data: Data) {
        guard isConnected else { return }

        guard let type = try? MessageProtocol.peekType(data) else {
            print("[MacPilot][Demo] Failed to parse outgoing message")
            return
        }

        switch type {
        case .metricsRequest:
            respondWithMetrics()
        case .commandRequest:
            respondToCommand(data)
        case .fileBrowseRequest:
            respondToBrowse(data)
        case .fileDownloadRequest:
            respondToDownload(data)
        case .fileUploadStart:
            respondToUploadStart(data)
        case .fileUploadChunk:
            respondToUploadChunk(data)
        case .mouseMove, .mouseClick, .mouseScroll, .keyPress, .keyRelease:
            logInputEvent(data)
        default:
            break
        }
    }

    private func connectToDemo() {
        connectionState = .connecting
        isConnected = false
        connectionState = .connected
        isConnected = true
        print("[MacPilot][Demo] Connected to local mock service")
    }

    private func respondWithMetrics() {
        let cpu = Double.random(in: 5...40)
        let memoryTotal: UInt64 = 16 * 1024 * 1024 * 1024
        let memoryUsedRatio = Double.random(in: 0.30...0.70)
        let memoryUsed = UInt64(Double(memoryTotal) * memoryUsedRatio)

        let diskTotal: UInt64 = 512 * 1024 * 1024 * 1024
        let diskUsed: UInt64 = 223 * 1024 * 1024 * 1024

        let metrics = SystemMetrics(
            cpu: CPUMetrics(
                usagePercent: cpu,
                coreCount: 8,
                perCoreUsage: (0..<8).map { _ in Double.random(in: 2...55) }
            ),
            memory: MemoryMetrics(
                totalBytes: memoryTotal,
                usedBytes: memoryUsed,
                availableBytes: memoryTotal - memoryUsed,
                swapUsedBytes: UInt64.random(in: 0...(2 * 1024 * 1024 * 1024))
            ),
            disk: DiskMetrics(
                totalBytes: diskTotal,
                usedBytes: diskUsed,
                availableBytes: diskTotal - diskUsed
            ),
            network: NetworkMetrics(
                bytesSent: UInt64.random(in: 50_000...450_000),
                bytesReceived: UInt64.random(in: 80_000...700_000),
                activeConnections: 3
            ),
            topProcesses: [
                MacProcessInfo(pid: 201, name: "Xcode", cpuPercent: Double.random(in: 4...12), memoryBytes: 1_400_000_000),
                MacProcessInfo(pid: 331, name: "Safari", cpuPercent: Double.random(in: 3...10), memoryBytes: 980_000_000),
                MacProcessInfo(pid: 912, name: "WindowServer", cpuPercent: Double.random(in: 1...7), memoryBytes: 620_000_000)
            ]
        )

        sendMock(metrics, type: .metricsResponse)
    }

    private func respondToCommand(_ data: Data) {
        guard let (_, request) = try? MessageProtocol.decodePlaintext(data, as: CommandRequest.self) else {
            return
        }

        let response = MockCommandResponse(
            commandId: request.commandId,
            success: true,
            output: "Demo mode: '\(request.command)' handled locally."
        )
        sendMock(response, type: .commandResponse)
    }

    private func respondToBrowse(_ data: Data) {
        guard let (_, request) = try? MessageProtocol.decodePlaintext(data, as: FileBrowseRequest.self) else {
            return
        }

        let normalizedPath = normalizePath(request.path)
        let response = FileBrowseResponse(
            path: normalizedPath,
            files: mockDirectory(for: normalizedPath)
        )
        sendMock(response, type: .fileBrowseResponse)
    }

    private func respondToDownload(_ data: Data) {
        guard let (_, request) = try? MessageProtocol.decodePlaintext(data, as: FileDownloadRequest.self) else {
            return
        }

        let sampleData = Data("Demo file contents from MacPilot mock service.".utf8)
        let checksum = SHA256.hash(data: sampleData).map { String(format: "%02x", $0) }.joined()
        let chunk = FileChunk(
            transferId: request.transferId,
            chunkIndex: 0,
            totalChunks: 1,
            offset: 0,
            data: sampleData,
            checksum: checksum
        )
        sendMock(chunk, type: .fileDownloadChunk)
    }

    private func respondToUploadStart(_ data: Data) {
        guard let (_, request) = try? MessageProtocol.decodePlaintext(data, as: FileUploadStart.self) else {
            return
        }

        let ack = MockFileUploadAck(
            transferId: request.transferId,
            acknowledgedChunk: -1,
            success: true
        )
        sendMock(ack, type: .fileUploadAck)
    }

    private func respondToUploadChunk(_ data: Data) {
        guard let (_, chunk) = try? MessageProtocol.decodePlaintext(data, as: FileChunk.self) else {
            return
        }

        let ack = MockFileUploadAck(
            transferId: chunk.transferId,
            acknowledgedChunk: chunk.chunkIndex,
            success: true
        )
        sendMock(ack, type: .fileUploadAck)
    }

    private func logInputEvent(_ data: Data) {
        guard let (_, event) = try? MessageProtocol.decodePlaintext(data, as: InputEvent.self) else {
            print("[MacPilot][Demo] Input event received")
            return
        }
        print("[MacPilot][Demo][Trackpad] \(event.type.rawValue) \(event.data)")
    }

    private func sendMock<T: Codable>(_ payload: T, type: MessageType) {
        guard let encoded = try? MessageProtocol.encodePlaintext(payload, type: type) else {
            return
        }

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 80_000_000)
            await MainActor.run {
                self?.onMessageReceived?(encoded)
            }
        }
    }

    private func normalizePath(_ path: String) -> String {
        if path.isEmpty || path == "/" { return "~" }
        if path == "/~" { return "~" }
        if path.hasPrefix("/~/") {
            return "~" + String(path.dropFirst(2))
        }
        return path
    }

    private func mockDirectory(for path: String) -> [FileItem] {
        let now = Date()

        switch path {
        case "~":
            return [
                FileItem(path: "~/Documents", name: "Documents", isDirectory: true, size: 0, modifiedAt: now, permissions: "rwxr-xr-x"),
                FileItem(path: "~/Downloads", name: "Downloads", isDirectory: true, size: 0, modifiedAt: now, permissions: "rwxr-xr-x"),
                FileItem(path: "~/Desktop", name: "Desktop", isDirectory: true, size: 0, modifiedAt: now, permissions: "rwxr-xr-x"),
                FileItem(path: "~/README.txt", name: "README.txt", isDirectory: false, size: 2048, modifiedAt: now, permissions: "rw-r--r--")
            ]
        case "~/Documents":
            return [
                FileItem(path: "~/Documents/ProjectPlan.md", name: "ProjectPlan.md", isDirectory: false, size: 12_400, modifiedAt: now, permissions: "rw-r--r--"),
                FileItem(path: "~/Documents/Invoices", name: "Invoices", isDirectory: true, size: 0, modifiedAt: now, permissions: "rwxr-xr-x"),
                FileItem(path: "~/Documents/Notes.txt", name: "Notes.txt", isDirectory: false, size: 5_128, modifiedAt: now, permissions: "rw-r--r--")
            ]
        case "~/Downloads":
            return [
                FileItem(path: "~/Downloads/MacPilot-beta.zip", name: "MacPilot-beta.zip", isDirectory: false, size: 24_200_000, modifiedAt: now, permissions: "rw-r--r--"),
                FileItem(path: "~/Downloads/SampleVideo.mp4", name: "SampleVideo.mp4", isDirectory: false, size: 8_500_000, modifiedAt: now, permissions: "rw-r--r--")
            ]
        case "~/Desktop":
            return [
                FileItem(path: "~/Desktop/Screenshot.png", name: "Screenshot.png", isDirectory: false, size: 1_245_000, modifiedAt: now, permissions: "rw-r--r--"),
                FileItem(path: "~/Desktop/Temp", name: "Temp", isDirectory: true, size: 0, modifiedAt: now, permissions: "rwxr-xr-x")
            ]
        default:
            return []
        }
    }
}

public struct MockCommandResponse: Codable, Sendable {
    public let commandId: UUID
    public let success: Bool
    public let output: String
}

public struct MockFileUploadAck: Codable, Sendable {
    public let transferId: UUID
    public let acknowledgedChunk: Int
    public let success: Bool
}
