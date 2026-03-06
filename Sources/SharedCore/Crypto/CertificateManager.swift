// CertificateManager.swift
// MacPilot — SharedCore / Crypto
//
// Manages self-signed TLS certificates for the WebSocket server.
// Uses TOFU (Trust On First Use) model — certificate fingerprint
// is exchanged during pairing and pinned on the client.

import Foundation
import CryptoKit
#if os(macOS)
import Security
#endif

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
    #if os(macOS)
    private static var runtimeServerIdentity: SecIdentity?
    private static let serverIdentityDirectory: URL = {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return appSupport.appendingPathComponent("MacPilot", isDirectory: true)
    }()
    private static let serverIdentityPKCS12URL = serverIdentityDirectory
        .appendingPathComponent("server-identity.p12", isDirectory: false)
    private static let serverIdentityPasswordURL = serverIdentityDirectory
        .appendingPathComponent("server-identity.pass", isDirectory: false)
    #endif

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

    #if os(macOS)
    /// Load or generate the server TLS identity used by Network.framework.
    public func getOrCreateServerIdentity() throws -> SecIdentity {
        if let identity = Self.runtimeServerIdentity {
            return identity
        }

        if let persisted = try loadPersistedServerIdentity() {
            Self.runtimeServerIdentity = persisted
            return persisted
        }

        let password = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let p12Data = try generateServerIdentityPKCS12(password: password)
        try persistServerIdentity(pkcs12Data: p12Data, password: password)
        guard let identity = try importIdentity(pkcs12Data: p12Data, password: password) else {
            throw CertificateError.certificateGenerationFailed
        }
        Self.runtimeServerIdentity = identity
        return identity
    }
    #endif

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
        try storeSecretData(data, tag: tag)
    }

    private func loadFingerprint(tag: String) throws -> String? {
        guard let data = try loadSecretData(tag: tag) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func storeSecretData(_ data: Data, tag: String) throws {
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

    private func loadSecretData(tag: String) throws -> Data? {
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
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw CertificateError.keychainError(status)
        }
    }

    #if os(macOS)
    private func importIdentity(pkcs12Data: Data, password: String) throws -> SecIdentity? {
        var importedItems: CFArray?
        let options: [String: Any] = [
            kSecImportExportPassphrase as String: password
        ]

        let status = SecPKCS12Import(pkcs12Data as CFData, options as CFDictionary, &importedItems)
        guard status == errSecSuccess else {
            throw CertificateError.keychainError(status)
        }

        guard
            let items = importedItems as? [[String: Any]],
            let first = items.first,
            let identityRef = first[kSecImportItemIdentity as String] as AnyObject?
        else {
            return nil
        }

        let cfValue = identityRef as CFTypeRef
        guard CFGetTypeID(cfValue) == SecIdentityGetTypeID() else {
            return nil
        }
        return unsafeBitCast(cfValue, to: SecIdentity.self)
    }

    private func loadPersistedServerIdentity() throws -> SecIdentity? {
        let fm = FileManager.default
        let p12URL = Self.serverIdentityPKCS12URL
        let passURL = Self.serverIdentityPasswordURL

        guard fm.fileExists(atPath: p12URL.path),
              fm.fileExists(atPath: passURL.path) else {
            return nil
        }

        do {
            let p12Data = try Data(contentsOf: p12URL)
            let passwordData = try Data(contentsOf: passURL)
            guard let password = String(data: passwordData, encoding: .utf8),
                  !password.isEmpty else {
                return nil
            }
            return try importIdentity(pkcs12Data: p12Data, password: password)
        } catch {
            try? fm.removeItem(at: p12URL)
            try? fm.removeItem(at: passURL)
            return nil
        }
    }

    private func persistServerIdentity(pkcs12Data: Data, password: String) throws {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: Self.serverIdentityDirectory, withIntermediateDirectories: true)
            try pkcs12Data.write(to: Self.serverIdentityPKCS12URL, options: .atomic)
            try Data(password.utf8).write(to: Self.serverIdentityPasswordURL, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.serverIdentityPKCS12URL.path)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.serverIdentityPasswordURL.path)
        } catch {
            throw CertificateError.certificateGenerationFailed
        }
    }

    private func generateServerIdentityPKCS12(password: String) throws -> Data {
        let fm = FileManager.default
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("macpilot-tls-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let keyPath = tempDir.appendingPathComponent("tls.key").path
        let certPath = tempDir.appendingPathComponent("tls.crt").path
        let p12Path = tempDir.appendingPathComponent("tls.p12").path

        try runProcess(
            executable: "/usr/bin/openssl",
            arguments: [
                "req", "-x509", "-newkey", "rsa:2048", "-sha256", "-nodes",
                "-keyout", keyPath,
                "-out", certPath,
                "-days", "3650",
                "-subj", "/CN=MacPilot Agent"
            ]
        )
        try runProcess(
            executable: "/usr/bin/openssl",
            arguments: [
                "pkcs12", "-export",
                "-inkey", keyPath,
                "-in", certPath,
                "-out", p12Path,
                "-passout", "pass:\(password)"
            ]
        )

        return try Data(contentsOf: URL(fileURLWithPath: p12Path))
    }

    private func runProcess(executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw CertificateError.certificateGenerationFailed
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CertificateError.certificateGenerationFailed
        }
    }

    #endif

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
        #if os(macOS)
        Self.runtimeServerIdentity = nil
        try? FileManager.default.removeItem(at: Self.serverIdentityPKCS12URL)
        try? FileManager.default.removeItem(at: Self.serverIdentityPasswordURL)
        #endif
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
