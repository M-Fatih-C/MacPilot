// MessageEnvelope.swift
// MacPilot — SharedCore
//
// Top-level wire format for all WebSocket messages.
// Payload is AES-256-GCM encrypted JSON.

import Foundation

/// Encrypted message envelope sent over the WebSocket connection.
///
/// Structure:
/// ```
/// {
///   "id": "uuid",
///   "type": "mouseMove",
///   "timestamp": "2026-03-05T20:00:00Z",
///   "payload": "<base64 encrypted data>",
///   "nonce": "<base64 GCM nonce>",
///   "tag": "<base64 GCM auth tag>"
/// }
/// ```
public struct MessageEnvelope: Codable, Sendable {
    /// Unique message identifier.
    public let id: UUID

    /// Type of the enclosed message.
    public let type: MessageType

    /// When the message was created (ISO 8601).
    public let timestamp: Date

    /// AES-256-GCM encrypted JSON payload.
    public let payload: Data

    /// GCM nonce used for encryption.
    public let nonce: Data

    /// GCM authentication tag.
    public let tag: Data

    public init(
        id: UUID = UUID(),
        type: MessageType,
        timestamp: Date = Date(),
        payload: Data,
        nonce: Data,
        tag: Data
    ) {
        self.id = id
        self.type = type
        self.timestamp = timestamp
        self.payload = payload
        self.nonce = nonce
        self.tag = tag
    }
}
