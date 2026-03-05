// NetworkConstants.swift
// MacPilot — SharedCore
//
// Shared networking constants used by both Mac and iPhone targets.

import Foundation

/// Networking constants for the MacPilot protocol.
public enum NetworkConstants {
    /// WebSocket server port.
    public static let port: UInt16 = 8443

    /// Bonjour service type for device discovery.
    public static let bonjourServiceType = "_macpilot._tcp"

    /// Bonjour service domain.
    public static let bonjourDomain = "local."

    /// WebSocket path.
    public static let webSocketPath = "/ws"

    /// Connection timeout in seconds.
    public static let connectionTimeout: TimeInterval = 10.0

    /// Reconnection intervals (exponential backoff).
    public static let reconnectBaseInterval: TimeInterval = 1.0
    public static let reconnectMaxInterval: TimeInterval = 30.0

    /// System metrics refresh interval in seconds.
    public static let metricsRefreshInterval: TimeInterval = 3.0

    /// Maximum input events per second.
    public static let maxInputEventsPerSecond: Int = 200

    /// Ping interval for keepalive.
    public static let pingInterval: TimeInterval = 5.0

    /// Allowed private network ranges.
    public static let allowedNetworkRanges = [
        "192.168.0.0/16",
        "10.0.0.0/8",
        "172.16.0.0/12"
    ]

    /// File transfer chunk size (256KB).
    public static let fileChunkSize: Int = 256 * 1024

    /// Maximum file transfer size (500MB).
    public static let maxFileTransferSize: UInt64 = 500 * 1024 * 1024
}
