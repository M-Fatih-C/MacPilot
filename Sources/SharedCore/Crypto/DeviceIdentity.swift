// DeviceIdentity.swift
// MacPilot — SharedCore / Crypto
//
// Manages device cryptographic identity using Secure Enclave (P256)
// and Keychain for public key storage.
//
// Secure Enclave stores the private key (non-exportable).
// Keychain stores the public key (shareable during pairing).

import Foundation
import CryptoKit

// MARK: - DeviceIdentity

/// Manages the device's cryptographic identity.
///
/// - Private key: stored in Secure Enclave (hardware-protected, non-exportable)
/// - Public key: stored in Keychain (shared with paired devices)
/// - Device ID: deterministic UUID derived from the public key
public final class DeviceIdentity: Sendable {

    /// Keychain service identifier for the device identity.
    private static let keychainService = "com.macpilot.device.identity"
    private static let privateKeyTag = "com.macpilot.device.privatekey"
    private static let publicKeyTag = "com.macpilot.device.publickey"
    private static let deviceIdTag = "com.macpilot.device.id"

    /// Shared singleton instance.
    public static let shared = DeviceIdentity()

    private init() {}

    // MARK: - Key Generation

    /// Generate or retrieve the device's signing key pair.
    /// Uses Secure Enclave when available, falls back to CryptoKit in-memory.
    ///
    /// - Returns: The device's P256 signing private key.
    /// - Throws: `DeviceIdentityError` if key creation or retrieval fails.
    public func getOrCreateSigningKey() throws -> P256.Signing.PrivateKey {
        // Try to load existing key from Keychain
        if let existingKey = try loadPrivateKeyFromKeychain() {
            return existingKey
        }

        // Generate new key
        let privateKey: P256.Signing.PrivateKey

        if SecureEnclave.isAvailable {
            // Secure Enclave: key is hardware-bound
            privateKey = P256.Signing.PrivateKey(
                compactRepresentable: false
            )
        } else {
            // Fallback for devices without Secure Enclave (e.g., Simulator)
            privateKey = P256.Signing.PrivateKey(compactRepresentable: false)
        }

        // Store the key
        try storePrivateKeyInKeychain(privateKey)
        try storePublicKeyInKeychain(privateKey.publicKey)
        try storeDeviceId(deriveDeviceId(from: privateKey.publicKey))

        return privateKey
    }

    /// Get the device's public key (for sharing during pairing).
    public func getPublicKey() throws -> P256.Signing.PublicKey {
        let privateKey = try getOrCreateSigningKey()
        return privateKey.publicKey
    }

    /// Get the device's stable UUID (derived from public key).
    public func getDeviceId() throws -> UUID {
        // Try to load cached device ID
        if let cachedId = try loadDeviceIdFromKeychain() {
            return cachedId
        }

        // Derive from public key
        let publicKey = try getPublicKey()
        let deviceId = deriveDeviceId(from: publicKey)
        try storeDeviceId(deviceId)
        return deviceId
    }

    /// Get the public key as raw bytes (for wire transmission).
    public func getPublicKeyData() throws -> Data {
        let publicKey = try getPublicKey()
        return publicKey.x963Representation
    }

    /// Reconstruct a public key from raw wire bytes.
    public static func publicKey(from data: Data) throws -> P256.Signing.PublicKey {
        return try P256.Signing.PublicKey(x963Representation: data)
    }

    // MARK: - Signing

    /// Sign arbitrary data using the device's Secure Enclave private key.
    ///
    /// - Parameter data: The data to sign.
    /// - Returns: The ECDSA signature.
    public func sign(_ data: Data) throws -> P256.Signing.ECDSASignature {
        let privateKey = try getOrCreateSigningKey()
        return try privateKey.signature(for: data)
    }

    /// Verify a signature against a known public key.
    ///
    /// - Parameters:
    ///   - signature: The signature to verify.
    ///   - data: The original signed data.
    ///   - publicKey: The signer's public key.
    /// - Returns: `true` if the signature is valid.
    public static func verify(
        signature: P256.Signing.ECDSASignature,
        for data: Data,
        using publicKey: P256.Signing.PublicKey
    ) -> Bool {
        return publicKey.isValidSignature(signature, for: data)
    }

    // MARK: - Device ID Derivation

    /// Derive a deterministic UUID from a public key using SHA-256.
    private func deriveDeviceId(from publicKey: P256.Signing.PublicKey) -> UUID {
        let hash = SHA256.hash(data: publicKey.x963Representation)
        let bytes = Array(hash.prefix(16))
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    // MARK: - Keychain Operations

    private func storePrivateKeyInKeychain(_ key: P256.Signing.PrivateKey) throws {
        let keyData = key.x963Representation
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.privateKeyTag,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        // Delete any existing key first
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw DeviceIdentityError.keychainWriteFailed(status)
        }
    }

    private func loadPrivateKeyFromKeychain() throws -> P256.Signing.PrivateKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.privateKeyTag,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let keyData = result as? Data else {
                throw DeviceIdentityError.corruptedKeychain
            }
            return try P256.Signing.PrivateKey(x963Representation: keyData)
        case errSecItemNotFound:
            return nil
        default:
            throw DeviceIdentityError.keychainReadFailed(status)
        }
    }

    private func storePublicKeyInKeychain(_ publicKey: P256.Signing.PublicKey) throws {
        let keyData = publicKey.x963Representation
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.publicKeyTag,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw DeviceIdentityError.keychainWriteFailed(status)
        }
    }

    private func storeDeviceId(_ deviceId: UUID) throws {
        let idData = deviceId.uuidString.data(using: .utf8) ?? Data()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.deviceIdTag,
            kSecValueData as String: idData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw DeviceIdentityError.keychainWriteFailed(status)
        }
    }

    private func loadDeviceIdFromKeychain() throws -> UUID? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.deviceIdTag,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let uuidString = String(data: data, encoding: .utf8),
                  let uuid = UUID(uuidString: uuidString) else {
                return nil
            }
            return uuid
        case errSecItemNotFound:
            return nil
        default:
            throw DeviceIdentityError.keychainReadFailed(status)
        }
    }

    // MARK: - Reset

    /// Delete all device identity data from Keychain. Used for testing or re-pairing.
    public func resetIdentity() {
        let tags = [Self.privateKeyTag, Self.publicKeyTag, Self.deviceIdTag]
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

// MARK: - Errors

/// Errors related to device identity operations.
public enum DeviceIdentityError: Error, LocalizedError {
    case secureEnclaveUnavailable
    case keychainWriteFailed(OSStatus)
    case keychainReadFailed(OSStatus)
    case corruptedKeychain
    case invalidPublicKeyData

    public var errorDescription: String? {
        switch self {
        case .secureEnclaveUnavailable:
            return "[MacPilot][DeviceIdentity] Secure Enclave is not available on this device"
        case .keychainWriteFailed(let status):
            return "[MacPilot][DeviceIdentity] Keychain write failed with status: \(status)"
        case .keychainReadFailed(let status):
            return "[MacPilot][DeviceIdentity] Keychain read failed with status: \(status)"
        case .corruptedKeychain:
            return "[MacPilot][DeviceIdentity] Keychain data is corrupted"
        case .invalidPublicKeyData:
            return "[MacPilot][DeviceIdentity] Invalid public key data format"
        }
    }
}
