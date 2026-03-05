// SessionCrypto.swift
// MacPilot — SharedCore / Crypto
//
// Manages per-session encryption using:
//   - X25519 key agreement (ephemeral, per session → PFS)
//   - HKDF-SHA512 key derivation
//   - AES-256-GCM symmetric encryption
//
// Each session generates fresh ephemeral keys.
// Session keys are destroyed on disconnect (Perfect Forward Secrecy).

import Foundation
import CryptoKit

// MARK: - SessionCrypto

/// Manages end-to-end encryption for a single WebSocket session.
///
/// Usage:
/// ```swift
/// let session = try SessionCrypto()
/// let myPublicKey = session.publicKeyData
///
/// // After receiving peer's public key:
/// try session.deriveSessionKey(peerPublicKey: peerKeyData)
///
/// // Encrypt/decrypt messages:
/// let sealed = try session.encrypt(plaintext)
/// let decrypted = try session.decrypt(sealed)
/// ```
public final class SessionCrypto {

    /// The ephemeral private key for this session (destroyed on dealloc).
    private let ephemeralPrivateKey: Curve25519.KeyAgreement.PrivateKey

    /// The derived symmetric session key (set after key exchange).
    private var sessionKey: SymmetricKey?

    /// Salt used for HKDF derivation.
    private static let hkdfSalt = "MacPilot-Session-v1".data(using: .utf8)!

    /// Info string for HKDF context binding.
    private static let hkdfInfo = "MacPilot-AES256GCM".data(using: .utf8)!

    // MARK: - Init

    /// Create a new session with a fresh ephemeral X25519 key pair.
    public init() {
        self.ephemeralPrivateKey = Curve25519.KeyAgreement.PrivateKey()
    }

    // MARK: - Key Exchange

    /// The ephemeral public key to send to the peer.
    public var publicKeyData: Data {
        ephemeralPrivateKey.publicKey.rawRepresentation
    }

    /// Derive the shared session key from the peer's ephemeral public key.
    ///
    /// Uses X25519 Diffie-Hellman followed by HKDF-SHA512 to produce
    /// a 256-bit AES key.
    ///
    /// - Parameter peerPublicKey: The peer's X25519 ephemeral public key bytes.
    /// - Throws: `SessionCryptoError` if key agreement fails.
    public func deriveSessionKey(peerPublicKey: Data) throws {
        let peerKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerPublicKey)

        let sharedSecret = try ephemeralPrivateKey.sharedSecretFromKeyAgreement(with: peerKey)

        // HKDF-SHA512: shared_secret → 256-bit symmetric key
        self.sessionKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA512.self,
            salt: Self.hkdfSalt,
            sharedInfo: Self.hkdfInfo,
            outputByteCount: 32 // 256 bits for AES-256
        )
    }

    /// Check whether the session key has been established.
    public var isEstablished: Bool {
        sessionKey != nil
    }

    // MARK: - Encryption

    /// Encrypt plaintext data using AES-256-GCM.
    ///
    /// - Parameter plaintext: The data to encrypt.
    /// - Returns: A `SealedPayload` containing ciphertext, nonce, and auth tag.
    /// - Throws: `SessionCryptoError.sessionNotEstablished` if key exchange hasn't completed.
    public func encrypt(_ plaintext: Data) throws -> SealedPayload {
        guard let key = sessionKey else {
            throw SessionCryptoError.sessionNotEstablished
        }

        let sealedBox = try AES.GCM.seal(plaintext, using: key)

        guard let combined = sealedBox.combined else {
            throw SessionCryptoError.encryptionFailed
        }

        // AES.GCM.SealedBox.combined = nonce (12) + ciphertext + tag (16)
        let nonce = Data(sealedBox.nonce)
        let ciphertext = Data(sealedBox.ciphertext)
        let tag = Data(sealedBox.tag)

        return SealedPayload(
            ciphertext: ciphertext,
            nonce: nonce,
            tag: tag
        )
    }

    /// Decrypt a sealed payload using AES-256-GCM.
    ///
    /// - Parameter sealed: The sealed payload (ciphertext + nonce + tag).
    /// - Returns: The decrypted plaintext data.
    /// - Throws: `SessionCryptoError` if decryption or authentication fails.
    public func decrypt(_ sealed: SealedPayload) throws -> Data {
        guard let key = sessionKey else {
            throw SessionCryptoError.sessionNotEstablished
        }

        let nonce = try AES.GCM.Nonce(data: sealed.nonce)
        let sealedBox = try AES.GCM.SealedBox(
            nonce: nonce,
            ciphertext: sealed.ciphertext,
            tag: sealed.tag
        )

        return try AES.GCM.open(sealedBox, using: key)
    }

    // MARK: - Destroy

    /// Destroy the session key. Call on disconnect for PFS.
    public func destroySession() {
        sessionKey = nil
    }
}

// MARK: - SealedPayload

/// The output of AES-256-GCM encryption.
public struct SealedPayload: Codable, Sendable {
    /// The encrypted data.
    public let ciphertext: Data

    /// The 12-byte GCM nonce.
    public let nonce: Data

    /// The 16-byte GCM authentication tag.
    public let tag: Data

    public init(ciphertext: Data, nonce: Data, tag: Data) {
        self.ciphertext = ciphertext
        self.nonce = nonce
        self.tag = tag
    }
}

// MARK: - Errors

/// Errors for session crypto operations.
public enum SessionCryptoError: Error, LocalizedError {
    case sessionNotEstablished
    case invalidPeerPublicKey
    case encryptionFailed
    case decryptionFailed
    case authenticationFailed

    public var errorDescription: String? {
        switch self {
        case .sessionNotEstablished:
            return "[MacPilot][SessionCrypto] Session key not established — complete key exchange first"
        case .invalidPeerPublicKey:
            return "[MacPilot][SessionCrypto] Invalid peer public key format"
        case .encryptionFailed:
            return "[MacPilot][SessionCrypto] AES-256-GCM encryption failed"
        case .decryptionFailed:
            return "[MacPilot][SessionCrypto] AES-256-GCM decryption failed"
        case .authenticationFailed:
            return "[MacPilot][SessionCrypto] GCM authentication tag verification failed"
        }
    }
}
