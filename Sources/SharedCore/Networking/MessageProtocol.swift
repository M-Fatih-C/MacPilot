// MessageProtocol.swift
// MacPilot — SharedCore / Networking
//
// Encode/decode pipeline for MacPilot WebSocket messages.
// Handles: JSON serialization → AES-256-GCM encryption → MessageEnvelope.

import Foundation

// MARK: - MessageProtocol

/// Encodes and decodes MacPilot messages with encryption.
///
/// Pipeline:
/// ```
/// Send: Model → JSON → AES-256-GCM encrypt → MessageEnvelope → JSON (wire)
/// Recv: JSON (wire) → MessageEnvelope → AES-256-GCM decrypt → JSON → Model
/// ```
public enum MessageProtocol {

    private static let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        return enc
    }()

    private static let decoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }()

    // MARK: - Encode (Send)

    /// Encode a Codable model into an encrypted MessageEnvelope.
    ///
    /// - Parameters:
    ///   - message: The message payload to send.
    ///   - type: The message type identifier.
    ///   - session: The active session crypto for encryption.
    /// - Returns: JSON-encoded `Data` ready for WebSocket transmission.
    public static func encode<T: Codable>(
        _ message: T,
        type: MessageType,
        using session: SessionCrypto
    ) throws -> Data {
        // Step 1: Serialize the payload to JSON
        let payloadJSON = try encoder.encode(message)

        // Step 2: Encrypt with AES-256-GCM
        let sealed = try session.encrypt(payloadJSON)

        // Step 3: Wrap in MessageEnvelope
        let envelope = MessageEnvelope(
            type: type,
            payload: sealed.ciphertext,
            nonce: sealed.nonce,
            tag: sealed.tag
        )

        // Step 4: Serialize the envelope to JSON (wire format)
        return try encoder.encode(envelope)
    }

    /// Encode a message without encryption (for pre-auth messages like pairing).
    ///
    /// - Parameters:
    ///   - message: The message payload.
    ///   - type: The message type.
    /// - Returns: JSON-encoded `Data` ready for WebSocket transmission.
    public static func encodePlaintext<T: Codable>(
        _ message: T,
        type: MessageType
    ) throws -> Data {
        let payloadJSON = try encoder.encode(message)

        let envelope = MessageEnvelope(
            type: type,
            payload: payloadJSON,
            nonce: Data(),  // empty for plaintext
            tag: Data()     // empty for plaintext
        )

        return try encoder.encode(envelope)
    }

    // MARK: - Decode (Receive)

    /// Decode an incoming WebSocket message into a typed model.
    ///
    /// - Parameters:
    ///   - data: The raw WebSocket message data.
    ///   - as: The expected payload type.
    ///   - session: The active session crypto for decryption.
    /// - Returns: A tuple of `(MessageType, decoded model)`.
    public static func decode<T: Codable>(
        _ data: Data,
        as payloadType: T.Type,
        using session: SessionCrypto
    ) throws -> (type: MessageType, payload: T) {
        // Step 1: Deserialize the envelope
        let envelope = try decoder.decode(MessageEnvelope.self, from: data)

        // Step 2: Decrypt the payload
        let sealed = SealedPayload(
            ciphertext: envelope.payload,
            nonce: envelope.nonce,
            tag: envelope.tag
        )
        let decryptedJSON = try session.decrypt(sealed)

        // Step 3: Deserialize the payload into the target type
        let payload = try decoder.decode(T.self, from: decryptedJSON)

        return (type: envelope.type, payload: payload)
    }

    /// Decode an incoming plaintext message (pre-auth).
    ///
    /// - Parameters:
    ///   - data: The raw WebSocket message data.
    ///   - as: The expected payload type.
    /// - Returns: A tuple of `(MessageType, decoded model)`.
    public static func decodePlaintext<T: Codable>(
        _ data: Data,
        as payloadType: T.Type
    ) throws -> (type: MessageType, payload: T) {
        let envelope = try decoder.decode(MessageEnvelope.self, from: data)
        let payload = try decoder.decode(T.self, from: envelope.payload)
        return (type: envelope.type, payload: payload)
    }

    // MARK: - Envelope Only

    /// Peek at the message type without decrypting the payload.
    ///
    /// - Parameter data: The raw WebSocket message data.
    /// - Returns: The `MessageType` of the envelope.
    public static func peekType(_ data: Data) throws -> MessageType {
        let envelope = try decoder.decode(MessageEnvelope.self, from: data)
        return envelope.type
    }

    /// Decode only the envelope (without decrypting payload).
    public static func decodeEnvelope(_ data: Data) throws -> MessageEnvelope {
        return try decoder.decode(MessageEnvelope.self, from: data)
    }
}
