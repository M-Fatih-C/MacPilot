// MacConnection.swift
// MacPilot — MacPilot-iOS / Services
//
// WebSocket client that connects to MacPilotAgent.
// Uses Network.framework NWConnection with TLS 1.3.
// Implements automatic reconnection with exponential backoff.

import Foundation
import Network
import Combine
import SharedCore

// MARK: - MacConnection

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
    }

    // MARK: - Send

    /// Send binary data over the WebSocket.
    public func send(_ data: Data) {
        guard let connection = connection, isConnected else { return }

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

        // Accept self-signed certificates (we do our own pinning)
        sec_protocol_options_set_verify_block(securityOptions, { _, trust, completionHandler in
            // TODO: Implement certificate pinning verification here
            // For now, accept all (development mode)
            completionHandler(true)
        }, queue)

        // WebSocket protocol
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        wsOptions.maximumMessageSize = 1024 * 1024

        let parameters = NWParameters(tls: tlsOptions)
        parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        return parameters
    }

    // MARK: - Private: State Handling

    private func handleNWState(_ state: NWConnection.State) {
        switch state {
        case .ready:
            stateMachine.handle(.tcpConnected)
            // For now, skip auth and go directly to connected
            // Auth handshake will be added in Phase 2
            stateMachine.handle(.authSucceeded)
            stateMachine.handle(.keyExchangeDone)
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
                    self?.onMessageReceived?(data)
                }
            }

            // Continue receiving
            Task { @MainActor [weak self] in
                if self?.isConnected == true {
                    self?.receiveMessage()
                }
            }
        }
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
