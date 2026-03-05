// ClientConnection.swift
// MacPilot — MacPilotAgent / Server
//
// Manages a single WebSocket client connection.
// Handles message framing, ping/pong keepalive, and graceful disconnect.

import Foundation
import Network
import SharedCore

// MARK: - ClientConnection

/// Represents a single connected iPhone client.
public final class ClientConnection {

    // MARK: - Properties

    /// The underlying Network.framework connection.
    private let connection: NWConnection

    /// Dispatch queue for connection operations.
    private let queue: DispatchQueue

    /// Unique identifier for this connection.
    public let id = UUID()

    /// Whether this connection is currently active.
    public private(set) var isConnected = false

    /// Callback when a complete WebSocket message is received.
    public var onMessageReceived: ((Data) -> Void)?

    /// Callback when the connection is lost or closed.
    public var onDisconnected: (() -> Void)?

    /// Keepalive ping timer.
    private var pingTimer: DispatchSourceTimer?

    // MARK: - Init

    init(connection: NWConnection, queue: DispatchQueue) {
        self.connection = connection
        self.queue = queue
    }

    // MARK: - Lifecycle

    /// Start the connection and begin receiving messages.
    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            self?.handleStateChange(state)
        }

        connection.start(queue: queue)
    }

    /// Gracefully disconnect the client.
    public func disconnect() {
        stopPingTimer()
        isConnected = false
        connection.cancel()
    }

    // MARK: - Send

    /// Send a WebSocket message to the client.
    ///
    /// - Parameter data: The message data to send.
    public func send(_ data: Data) {
        guard isConnected else { return }

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
                    log("Connection", "Send error: \(error.localizedDescription)")
                    self?.handleDisconnect()
                }
            }
        )
    }

    /// Send a text WebSocket message.
    public func sendText(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }

        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(
            identifier: "MacPilotText",
            metadata: [metadata]
        )

        connection.send(
            content: data,
            contentContext: context,
            isComplete: true,
            completion: .contentProcessed { [weak self] error in
                if let error = error {
                    log("Connection", "Send error: \(error.localizedDescription)")
                    self?.handleDisconnect()
                }
            }
        )
    }

    // MARK: - Receive

    /// Begin receiving WebSocket messages recursively.
    private func receiveMessage() {
        connection.receiveMessage { [weak self] content, context, isComplete, error in
            guard let self = self else { return }

            if let error = error {
                log("Connection", "Receive error: \(error.localizedDescription)")
                self.handleDisconnect()
                return
            }

            // Check if this is a WebSocket message
            if let context = context,
               let metadata = context.protocolMetadata(definition: NWProtocolWebSocket.definition)
                   as? NWProtocolWebSocket.Metadata {

                switch metadata.opcode {
                case .binary, .text:
                    if let data = content {
                        self.onMessageReceived?(data)
                    }
                case .close:
                    log("Connection", "Client sent close frame")
                    self.handleDisconnect()
                    return
                case .ping:
                    // Auto-reply is handled by NWProtocolWebSocket
                    break
                case .pong:
                    // Keepalive confirmed
                    break
                default:
                    break
                }
            }

            // Continue receiving
            if self.isConnected {
                self.receiveMessage()
            }
        }
    }

    // MARK: - State Handling

    private func handleStateChange(_ state: NWConnection.State) {
        switch state {
        case .ready:
            isConnected = true
            log("Connection", "Client \(id) connected")
            receiveMessage()
            startPingTimer()

        case .failed(let error):
            log("Connection", "Client \(id) failed: \(error.localizedDescription)")
            handleDisconnect()

        case .cancelled:
            log("Connection", "Client \(id) cancelled")
            handleDisconnect()

        case .waiting(let error):
            log("Connection", "Client \(id) waiting: \(error.localizedDescription)")

        default:
            break
        }
    }

    private func handleDisconnect() {
        guard isConnected else { return }
        isConnected = false
        stopPingTimer()
        connection.cancel()
        log("Connection", "Client \(id) disconnected")
        onDisconnected?()
    }

    // MARK: - Keepalive

    private func startPingTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now() + NetworkConstants.pingInterval,
            repeating: NetworkConstants.pingInterval
        )
        timer.setEventHandler { [weak self] in
            self?.sendPing()
        }
        timer.resume()
        pingTimer = timer
    }

    private func stopPingTimer() {
        pingTimer?.cancel()
        pingTimer = nil
    }

    private func sendPing() {
        guard isConnected else { return }

        let metadata = NWProtocolWebSocket.Metadata(opcode: .ping)
        metadata.setPongHandler(queue) { [weak self] error in
            if let error = error {
                log("Connection", "Pong error: \(error.localizedDescription)")
                self?.handleDisconnect()
            }
        }

        let context = NWConnection.ContentContext(
            identifier: "MacPilotPing",
            metadata: [metadata]
        )

        connection.send(
            content: nil,
            contentContext: context,
            isComplete: true,
            completion: .contentProcessed { _ in }
        )
    }
}
