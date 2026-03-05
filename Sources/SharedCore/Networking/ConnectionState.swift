// ConnectionState.swift
// MacPilot — SharedCore / Networking
//
// Finite state machine for WebSocket connection lifecycle.
// Used by both Mac (server-side) and iPhone (client-side).

import Foundation

// MARK: - ConnectionState

/// Represents the current state of the WebSocket connection.
public enum ConnectionState: String, Sendable {
    /// No connection — waiting for discovery or user action.
    case idle

    /// Bonjour discovered the Mac, connecting via WSS.
    case connecting

    /// WSS connected, performing mutual authentication handshake.
    case authenticating

    /// Handshake complete, performing ephemeral key exchange.
    case keyExchange

    /// Fully authenticated and encrypted — ready for messages.
    case connected

    /// Connection was lost, attempting automatic reconnection.
    case reconnecting

    /// Connection permanently failed (e.g., untrusted device).
    case failed

    /// User-initiated disconnect.
    case disconnected
}

// MARK: - ConnectionEvent

/// Events that drive state transitions.
public enum ConnectionEvent: String, Sendable {
    case discovered         // Bonjour found a MacPilot service
    case tcpConnected       // TCP/TLS handshake succeeded
    case authSucceeded      // Mutual authentication passed
    case keyExchangeDone    // Ephemeral key exchange completed
    case messageReceived    // Generic message received
    case disconnected       // Connection dropped
    case authFailed         // Authentication failed
    case timeout            // Operation timed out
    case userDisconnect     // User requested disconnect
    case retryScheduled     // Reconnection timer fired
}

// MARK: - ConnectionStateMachine

/// State machine managing connection lifecycle transitions.
///
/// ```
/// idle → connecting → authenticating → keyExchange → connected
///                                                         │
///                                      reconnecting ◄─────┘
///                                           │
///                                      connecting (retry)
/// ```
public struct ConnectionStateMachine: Sendable {

    /// Current state.
    public private(set) var state: ConnectionState

    /// Number of consecutive reconnection attempts.
    public private(set) var reconnectAttempts: Int

    /// Maximum reconnection attempts before giving up.
    public let maxReconnectAttempts: Int

    public init(maxReconnectAttempts: Int = 10) {
        self.state = .idle
        self.reconnectAttempts = 0
        self.maxReconnectAttempts = maxReconnectAttempts
    }

    /// Process an event and transition to the next state.
    ///
    /// - Parameter event: The connection event.
    /// - Returns: The new state after the transition.
    @discardableResult
    public mutating func handle(_ event: ConnectionEvent) -> ConnectionState {
        let previousState = state

        switch (state, event) {

        // MARK: Idle
        case (.idle, .discovered),
             (.idle, .retryScheduled):
            state = .connecting

        // MARK: Connecting
        case (.connecting, .tcpConnected):
            state = .authenticating
        case (.connecting, .timeout),
             (.connecting, .disconnected):
            state = .reconnecting

        // MARK: Authenticating
        case (.authenticating, .authSucceeded):
            state = .keyExchange
        case (.authenticating, .authFailed):
            state = .failed
        case (.authenticating, .disconnected),
             (.authenticating, .timeout):
            state = .reconnecting

        // MARK: Key Exchange
        case (.keyExchange, .keyExchangeDone):
            state = .connected
            reconnectAttempts = 0
        case (.keyExchange, .disconnected),
             (.keyExchange, .timeout):
            state = .reconnecting

        // MARK: Connected
        case (.connected, .disconnected):
            state = .reconnecting
        case (.connected, .userDisconnect):
            state = .disconnected

        // MARK: Reconnecting
        case (.reconnecting, .retryScheduled):
            if reconnectAttempts < maxReconnectAttempts {
                reconnectAttempts += 1
                state = .connecting
            } else {
                state = .failed
            }
        case (.reconnecting, .userDisconnect):
            state = .disconnected

        // MARK: Failed / Disconnected — can restart
        case (.failed, .discovered),
             (.disconnected, .discovered):
            state = .connecting
            reconnectAttempts = 0

        default:
            // Ignore invalid transitions
            break
        }

        if state != previousState {
            // Log transition for debugging
            _ = "[MacPilot][Connection] \(previousState.rawValue) → \(state.rawValue) (event: \(event.rawValue))"
        }

        return state
    }

    /// Calculate the backoff interval for the current reconnect attempt.
    ///
    /// Exponential backoff: 1s, 2s, 4s, 8s, ..., capped at 30s.
    public var reconnectInterval: TimeInterval {
        let base = NetworkConstants.reconnectBaseInterval
        let maxInterval = NetworkConstants.reconnectMaxInterval
        let interval = base * pow(2.0, Double(reconnectAttempts))
        return min(interval, maxInterval)
    }

    /// Reset the state machine to idle.
    public mutating func reset() {
        state = .idle
        reconnectAttempts = 0
    }
}
