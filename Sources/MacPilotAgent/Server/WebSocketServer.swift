// WebSocketServer.swift
// MacPilot — MacPilotAgent / Server
//
// WebSocket server using Network.framework NWListener.
// Listens on port 8443 with TLS 1.3 and advertises via Bonjour.

import Foundation
import Network
import SharedCore

// MARK: - WebSocketServer

/// Secure WebSocket server that accepts iPhone connections.
///
/// - Listens on port 8443 with TLS 1.3
/// - Advertises `_macpilot._tcp` via Bonjour
/// - Enforces IP allowlist (local network only)
/// - Manages a single active client connection
public final class WebSocketServer {

    // MARK: - Properties

    private var listener: NWListener?
    private var activeConnection: ClientConnection?
    private let queue = DispatchQueue(label: "com.macpilot.server", qos: .userInteractive)

    /// Callback when a client connects and is authenticated.
    public var onClientConnected: ((ClientConnection) -> Void)?

    /// Callback when the active client disconnects.
    public var onClientDisconnected: (() -> Void)?

    /// Callback when a message is received from the client.
    public var onMessageReceived: ((Data, ClientConnection) -> Void)?

    /// Callback for server state changes.
    public var onStateChanged: ((NWListener.State) -> Void)?

    // MARK: - Init

    public init() {}

    // MARK: - Start / Stop

    /// Start the WebSocket server with TLS on port 8443.
    public func start() throws {
        let parameters = try createServerParameters()

        let port = NWEndpoint.Port(rawValue: NetworkConstants.port)!
        listener = try NWListener(using: parameters, on: port)

        // Advertise via Bonjour
        listener?.service = NWListener.Service(
            name: "MacPilot",
            type: NetworkConstants.bonjourServiceType
        )

        listener?.stateUpdateHandler = { [weak self] state in
            self?.handleListenerState(state)
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }

        listener?.start(queue: queue)
        log("Server", "Starting WebSocket server on port \(NetworkConstants.port)...")
    }

    /// Stop the server and disconnect all clients.
    public func stop() {
        log("Server", "Stopping server...")
        activeConnection?.disconnect()
        activeConnection = nil
        listener?.cancel()
        listener = nil
    }

    // MARK: - Send

    /// Send data to the active client.
    public func send(_ data: Data) {
        activeConnection?.send(data)
    }

    // MARK: - TLS Configuration

    /// Create NWParameters with TLS 1.3 and WebSocket protocol.
    private func createServerParameters() throws -> NWParameters {
        let tlsOptions = NWProtocolTLS.Options()

        // Configure TLS 1.3
        let securityOptions = tlsOptions.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(securityOptions, .TLSv13)

        // WebSocket protocol on top of TLS
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        wsOptions.maximumMessageSize = 1024 * 1024 // 1MB max message

        let parameters = NWParameters(tls: tlsOptions)
        parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        // Allow local network only
        parameters.requiredInterfaceType = .wifi

        return parameters
    }

    // MARK: - Connection Handling

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            if let port = listener?.port {
                log("Server", "Server ready on port \(port.rawValue)")
            }
        case .failed(let error):
            log("Server", "Server failed: \(error.localizedDescription)")
            // Attempt restart
            stop()
            try? start()
        case .cancelled:
            log("Server", "Server cancelled")
        default:
            break
        }
        onStateChanged?(state)
    }

    private func handleNewConnection(_ nwConnection: NWConnection) {
        // Enforce IP restriction
        guard NetworkRestriction.isAllowed(connection: nwConnection) else {
            log("Server", "Rejected connection from non-local IP")
            nwConnection.cancel()
            return
        }

        // Only allow one active connection (single iPhone)
        if let existing = activeConnection {
            log("Server", "Replacing existing connection")
            existing.disconnect()
        }

        let client = ClientConnection(connection: nwConnection, queue: queue)

        client.onMessageReceived = { [weak self] data in
            self?.onMessageReceived?(data, client)
        }

        client.onDisconnected = { [weak self] in
            self?.activeConnection = nil
            self?.onClientDisconnected?()
        }

        activeConnection = client
        client.start()

        log("Server", "New client connected from \(nwConnection.endpoint)")
        onClientConnected?(client)
    }
}

// MARK: - Logging

func log(_ module: String, _ message: String) {
    let formatter = ISO8601DateFormatter()
    let timestamp = formatter.string(from: Date())
    print("[\(timestamp)][MacPilot][\(module)] \(message)")
}
