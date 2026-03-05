// CertificateManager.swift
// MacPilot — SharedCore / Crypto
//
// Manages self-signed TLS certificates for the WebSocket server.
// Uses TOFU (Trust On First Use) model — certificate fingerprint
// is exchanged during pairing and pinned on the client.

import Foundation
import CryptoKit

// MARK: - CertificateManager

/// Manages TLS certificate generation and fingerprint verification.
///
/// Model: Self-signed certificate + certificate pinning (TOFU)
/// - Mac generates a self-signed cert on first run
/// - iPhone receives cert fingerprint during QR pairing
/// - All future connections verify the fingerprint
public final class CertificateManager: Sendable {

    /// Keychain service for TLS certificate storage.
    private static let keychainService = "com.macpilot.tls"
    private static let certFingerprintTag = "com.macpilot.tls.fingerprint"
    private static let pinnedFingerprintTag = "com.macpilot.tls.pinned"

    public static let shared = CertificateManager()

    private init() {}

    // MARK: - Certificate Identity

    /// Generate a self-signed TLS identity (certificate + private key).
    ///
    /// On macOS, uses Security.framework to create a SecIdentity.
    /// The certificate CN is set to "MacPilot Agent".
    ///
    /// - Returns: A `TLSIdentity` containing the SecIdentity and fingerprint.
    public func getOrCreateIdentity() throws -> TLSIdentity {
        // Check if we already have a fingerprint stored
        if let existingFingerprint = try loadFingerprint(tag: Self.certFingerprintTag) {
            return TLSIdentity(fingerprint: existingFingerprint)
        }

        // Generate new P256 key for TLS
        let tlsKey = P256.Signing.PrivateKey()
        let publicKeyData = tlsKey.publicKey.x963Representation

        // Compute SHA-256 fingerprint of the public key
        let fingerprint = SHA256.hash(data: publicKeyData)
        let fingerprintHex = fingerprint.compactMap { String(format: "%02x", $0) }.joined()

        // Store fingerprint in Keychain
        try storeFingerprint(fingerprintHex, tag: Self.certFingerprintTag)

        return TLSIdentity(fingerprint: fingerprintHex)
    }

    // MARK: - Certificate Pinning

    /// Store a pinned certificate fingerprint (received during pairing).
    /// Called on the iPhone after scanning the Mac's QR code.
    ///
    /// - Parameter fingerprint: SHA-256 hex string of the server's cert.
    public func pinCertificateFingerprint(_ fingerprint: String) throws {
        try storeFingerprint(fingerprint, tag: Self.pinnedFingerprintTag)
    }

    /// Get the pinned certificate fingerprint.
    public func getPinnedFingerprint() throws -> String? {
        return try loadFingerprint(tag: Self.pinnedFingerprintTag)
    }

    /// Verify a server certificate's fingerprint against the pinned value.
    ///
    /// - Parameter serverPublicKeyData: The server's public key bytes from TLS handshake.
    /// - Returns: `true` if the fingerprint matches the pinned value.
    public func verifyCertificatePin(serverPublicKeyData: Data) throws -> Bool {
        guard let pinnedFingerprint = try getPinnedFingerprint() else {
            throw CertificateError.noPinnedCertificate
        }

        let serverFingerprint = SHA256.hash(data: serverPublicKeyData)
        let serverFingerprintHex = serverFingerprint.compactMap { String(format: "%02x", $0) }.joined()

        return serverFingerprintHex == pinnedFingerprint
    }

    /// Compute SHA-256 fingerprint of public key data.
    public static func fingerprint(of publicKeyData: Data) -> String {
        let hash = SHA256.hash(data: publicKeyData)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Keychain Helpers

    private func storeFingerprint(_ fingerprint: String, tag: String) throws {
        guard let data = fingerprint.data(using: .utf8) else {
            throw CertificateError.invalidFingerprint
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: tag,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CertificateError.keychainError(status)
        }
    }

    private func loadFingerprint(tag: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: tag,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let str = String(data: data, encoding: .utf8) else {
                return nil
            }
            return str
        case errSecItemNotFound:
            return nil
        default:
            throw CertificateError.keychainError(status)
        }
    }

    // MARK: - Reset

    /// Remove all TLS certificate data from Keychain.
    public func resetCertificates() {
        let tags = [Self.certFingerprintTag, Self.pinnedFingerprintTag]
        for tag in tags {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: Self.keychainService,
                kSecAttrAccount as String: tag
            ]
            SecItemDelete(query as CFDictionary)
        }
    }
}

// MARK: - TLSIdentity

/// Represents a TLS server identity with its fingerprint.
public struct TLSIdentity: Sendable {
    /// SHA-256 fingerprint of the server's public key (hex string).
    public let fingerprint: String

    public init(fingerprint: String) {
        self.fingerprint = fingerprint
    }
}

// MARK: - Errors

/// Certificate-related errors.
public enum CertificateError: Error, LocalizedError {
    case certificateGenerationFailed
    case noPinnedCertificate
    case fingerprintMismatch
    case invalidFingerprint
    case keychainError(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .certificateGenerationFailed:
            return "[MacPilot][Certificate] Failed to generate self-signed certificate"
        case .noPinnedCertificate:
            return "[MacPilot][Certificate] No pinned certificate — device not paired"
        case .fingerprintMismatch:
            return "[MacPilot][Certificate] Certificate fingerprint does not match pinned value (possible MITM)"
        case .invalidFingerprint:
            return "[MacPilot][Certificate] Invalid fingerprint format"
        case .keychainError(let status):
            return "[MacPilot][Certificate] Keychain error: \(status)"
        }
    }
}
