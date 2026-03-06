// DevicePairing.swift
// MacPilot — SharedCore / DeviceIdentity
//
// Implements the one-time device pairing protocol.
// Mac generates a pair_code + QR, iPhone scans and exchanges keys.

import Foundation
import CryptoKit

// MARK: - Pairing Models

/// Data encoded in the QR code during pairing (Mac → iPhone).
public struct PairingQRPayload: Codable, Sendable {
    /// 6-digit pairing code.
    public let pairCode: String

    /// SHA-256 fingerprint of the Mac's TLS certificate.
    public let certFingerprint: String

    /// Mac's P256 public key (x963 representation, base64).
    public let publicKey: Data

    /// Mac's device ID.
    public let deviceId: UUID

    /// Mac's display name.
    public let deviceName: String

    public init(
        pairCode: String,
        certFingerprint: String,
        publicKey: Data,
        deviceId: UUID,
        deviceName: String
    ) {
        self.pairCode = pairCode
        self.certFingerprint = certFingerprint
        self.publicKey = publicKey
        self.deviceId = deviceId
        self.deviceName = deviceName
    }

    /// Encode to JSON Data (for QR code generation).
    public func toJSON() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }

    /// Decode from JSON Data (after QR code scanning).
    public static func fromJSON(_ data: Data) throws -> PairingQRPayload {
        let decoder = JSONDecoder()
        return try decoder.decode(PairingQRPayload.self, from: data)
    }
}

/// Request sent from iPhone → Mac during pairing.
public struct PairRequest: Codable, Sendable {
    /// iPhone's device ID.
    public let deviceId: UUID

    /// iPhone's device name.
    public let deviceName: String

    /// iPhone's P256 public key bytes.
    public let publicKey: Data

    /// The pair_code from the QR code (proof of physical proximity).
    public let pairCode: String

    public init(deviceId: UUID, deviceName: String, publicKey: Data, pairCode: String) {
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.publicKey = publicKey
        self.pairCode = pairCode
    }
}

/// Response sent from Mac → iPhone after successful pairing.
public struct PairResponse: Codable, Sendable {
    /// Mac's P256 public key bytes.
    public let publicKey: Data

    /// Pairing result.
    public let status: PairingStatus

    /// Optional error message if pairing failed.
    public let errorMessage: String?

    public init(publicKey: Data, status: PairingStatus, errorMessage: String? = nil) {
        self.publicKey = publicKey
        self.status = status
        self.errorMessage = errorMessage
    }
}

/// Pairing result status.
public enum PairingStatus: String, Codable, Sendable {
    case paired
    case invalidCode
    case alreadyPaired
    case rejected
}

// MARK: - Auth Handshake Models

/// Server hello message (Mac → iPhone, first message after WSS connect).
public struct ServerHello: Codable, Sendable {
    /// Mac's device ID.
    public let deviceId: UUID

    /// Random challenge for the iPhone to sign.
    public let challenge: Data

    /// Optional Mac public key (used for trust bootstrap/verification).
    public let publicKey: Data?

    public init(
        deviceId: UUID,
        challenge: Data = Self.generateChallenge(),
        publicKey: Data? = nil
    ) {
        self.deviceId = deviceId
        self.challenge = challenge
        self.publicKey = publicKey
    }

    /// Generate a 32-byte random challenge.
    public static func generateChallenge() -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }
}

/// Authentication request (iPhone → Mac).
public struct AuthRequest: Codable, Sendable {
    /// iPhone's device ID.
    public let deviceId: UUID

    /// iPhone's signature of the Mac's challenge (proves identity).
    public let signature: Data

    /// Counter-challenge for the Mac to sign (mutual auth).
    public let challenge: Data

    /// Optional iPhone public key (TOFU bootstrap when device is not yet trusted).
    public let publicKey: Data?

    public init(
        deviceId: UUID,
        signature: Data,
        challenge: Data = ServerHello.generateChallenge(),
        publicKey: Data? = nil
    ) {
        self.deviceId = deviceId
        self.signature = signature
        self.challenge = challenge
        self.publicKey = publicKey
    }
}

/// Authentication response (Mac → iPhone).
public struct AuthResponse: Codable, Sendable {
    /// Mac's signature of the iPhone's counter-challenge.
    public let signature: Data

    /// Authentication result.
    public let status: AuthStatus

    public init(signature: Data, status: AuthStatus) {
        self.signature = signature
        self.status = status
    }
}

/// Authentication result status.
public enum AuthStatus: String, Codable, Sendable {
    case authenticated
    case untrustedDevice
    case signatureInvalid
    case rejected
}

// MARK: - Ephemeral Key Exchange

/// Ephemeral public key message for Perfect Forward Secrecy.
public struct EphemeralKeyMessage: Codable, Sendable {
    /// X25519 ephemeral public key bytes.
    public let ephemeralPublicKey: Data

    public init(ephemeralPublicKey: Data) {
        self.ephemeralPublicKey = ephemeralPublicKey
    }
}

// MARK: - Pair Code Generator

/// Generates a cryptographically random 6-digit pairing code.
public enum PairCodeGenerator {

    /// Generate a random 6-digit numeric code.
    public static func generate() -> String {
        var bytes = [UInt8](repeating: 0, count: 4)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let value = bytes.withUnsafeBytes { $0.load(as: UInt32.self) } % 1_000_000
        return String(format: "%06d", value)
    }

    /// Constant-time comparison to prevent timing attacks.
    public static func verify(code: String, expected: String) -> Bool {
        guard code.count == expected.count else { return false }
        let codeBytes = Array(code.utf8)
        let expectedBytes = Array(expected.utf8)
        var result: UInt8 = 0
        for i in 0..<codeBytes.count {
            result |= codeBytes[i] ^ expectedBytes[i]
        }
        return result == 0
    }
}
