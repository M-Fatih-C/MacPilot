// CryptoTests.swift
// MacPilot — Tests
//
// Validates cryptographic operations:
//   - Device identity generation
//   - Key pair creation
//   - Session key exchange (X25519)
//   - AES-256-GCM encryption/decryption
//   - Message envelope encoding

import XCTest
import CryptoKit
@testable import SharedCore

final class CryptoTests: XCTestCase {

    // MARK: - Device Identity

    func testDeviceIdentityKeyGenerationReturnsKey() throws {
        let identity = DeviceIdentity.shared
        let key = try identity.getOrCreateSigningKey()
        XCTAssertNotNil(key, "Should generate a P256 signing key")
    }

    func testDeviceIdentityPublicKeyIsConsistent() throws {
        let identity = DeviceIdentity.shared
        let pub1 = try identity.getPublicKey()
        let pub2 = try identity.getPublicKey()
        XCTAssertEqual(
            pub1.x963Representation,
            pub2.x963Representation,
            "Public key should be deterministic"
        )
    }

    func testDeviceIdentityId() throws {
        let identity = DeviceIdentity.shared
        let id1 = try identity.getDeviceId()
        let id2 = try identity.getDeviceId()
        XCTAssertEqual(id1, id2, "Device ID should be deterministic")
    }

    func testSignAndVerify() throws {
        let identity = DeviceIdentity.shared
        let privateKey = try identity.getOrCreateSigningKey()
        let publicKey = privateKey.publicKey
        let testData = "MacPilot test data".data(using: .utf8)!

        let signature = try privateKey.signature(for: testData)
        let isValid = DeviceIdentity.verify(signature: signature, for: testData, using: publicKey)
        XCTAssertTrue(isValid, "Valid signature should verify")
    }

    func testVerifyTamperedDataFails() throws {
        let identity = DeviceIdentity.shared
        let privateKey = try identity.getOrCreateSigningKey()
        let publicKey = privateKey.publicKey
        let originalData = "Original".data(using: .utf8)!
        let tamperedData = "Tampered".data(using: .utf8)!

        let signature = try privateKey.signature(for: originalData)
        let isValid = DeviceIdentity.verify(signature: signature, for: tamperedData, using: publicKey)
        XCTAssertFalse(isValid, "Tampered data should fail verification")
    }

    // MARK: - Session Crypto

    func testSessionCryptoPublicKeyNotEmpty() {
        let session = SessionCrypto()
        XCTAssertFalse(session.publicKeyData.isEmpty, "Public key should not be empty")
        XCTAssertEqual(session.publicKeyData.count, 32, "X25519 public key should be 32 bytes")
    }

    func testSessionKeyExchangeAndEncryptDecrypt() throws {
        let alice = SessionCrypto()
        let bob = SessionCrypto()

        // Exchange public keys
        try alice.deriveSessionKey(peerPublicKey: bob.publicKeyData)
        try bob.deriveSessionKey(peerPublicKey: alice.publicKeyData)

        // Alice encrypts, Bob decrypts
        let plaintext = "Hello secure world!".data(using: .utf8)!
        let sealed = try alice.encrypt(plaintext)
        let decrypted = try bob.decrypt(sealed)

        XCTAssertEqual(decrypted, plaintext, "Decrypted data should match original")
    }

    func testEncryptProducesDifferentCiphertextEachTime() throws {
        let alice = SessionCrypto()
        let bob = SessionCrypto()

        try alice.deriveSessionKey(peerPublicKey: bob.publicKeyData)

        let plaintext = "Same message".data(using: .utf8)!
        let sealed1 = try alice.encrypt(plaintext)
        let sealed2 = try alice.encrypt(plaintext)

        // Each encryption uses a random nonce, so ciphertext should differ
        XCTAssertNotEqual(sealed1.nonce, sealed2.nonce, "Nonces should differ")
    }

    func testTamperedCiphertextFails() throws {
        let alice = SessionCrypto()
        let bob = SessionCrypto()

        try alice.deriveSessionKey(peerPublicKey: bob.publicKeyData)
        try bob.deriveSessionKey(peerPublicKey: alice.publicKeyData)

        let plaintext = "Sensitive data".data(using: .utf8)!
        let sealed = try alice.encrypt(plaintext)

        // Tamper with ciphertext
        var tamperedCiphertext = sealed.ciphertext
        if tamperedCiphertext.count > 0 {
            tamperedCiphertext[0] ^= 0xFF
        }
        let tamperedSealed = SealedPayload(
            ciphertext: tamperedCiphertext,
            nonce: sealed.nonce,
            tag: sealed.tag
        )

        XCTAssertThrowsError(try bob.decrypt(tamperedSealed), "Tampered ciphertext should throw")
    }

    func testEncryptBeforeKeyExchangeFails() {
        let session = SessionCrypto()
        let plaintext = "test".data(using: .utf8)!

        XCTAssertThrowsError(try session.encrypt(plaintext), "Should throw sessionNotEstablished")
    }

    func testDestroySessionPreventsDecryption() throws {
        let alice = SessionCrypto()
        let bob = SessionCrypto()

        try alice.deriveSessionKey(peerPublicKey: bob.publicKeyData)
        try bob.deriveSessionKey(peerPublicKey: alice.publicKeyData)

        let sealed = try alice.encrypt("test".data(using: .utf8)!)
        bob.destroySession()

        XCTAssertThrowsError(try bob.decrypt(sealed), "Destroyed session should fail")
    }

    // MARK: - MessageProtocol Plaintext

    func testEncodePlaintextDecodePlaintext() throws {
        let device = DeviceInfo(
            deviceName: "Test Mac",
            platform: .macOS,
            publicKey: Data(repeating: 0x01, count: 32)
        )

        let encoded = try MessageProtocol.encodePlaintext(device, type: .authResponse)
        XCTAssertFalse(encoded.isEmpty)

        let decoded = try MessageProtocol.decodePlaintext(encoded, as: DeviceInfo.self)
        XCTAssertEqual(decoded.type, .authResponse)
        XCTAssertEqual(decoded.payload.deviceName, "Test Mac")
        XCTAssertEqual(decoded.payload.platform, .macOS)
    }

    func testPeekType() throws {
        let event = InputEvent(type: .mouseMove, data: InputEventData(deltaX: 1, deltaY: 2))
        let encoded = try MessageProtocol.encodePlaintext(event, type: .mouseMove)

        let type = try MessageProtocol.peekType(encoded)
        XCTAssertEqual(type, .mouseMove)
    }

    func testAllMessageTypesRoundTrip() throws {
        let allTypes: [MessageType] = [
            .pairRequest, .pairResponse, .authChallenge, .authResponse,
            .ephemeralKeyExchange,
            .mouseMove, .mouseClick, .mouseScroll,
            .keyPress, .keyRelease,
            .metricsRequest, .metricsResponse,
            .processListRequest, .processListResponse,
            .commandRequest, .commandResponse,
            .fileBrowseRequest, .fileBrowseResponse,
            .fileDownloadRequest, .fileDownloadChunk,
            .fileUploadStart, .fileUploadChunk, .fileUploadAck,
            .ping, .pong, .error
        ]

        for type in allTypes {
            let encoded = try JSONEncoder().encode(type)
            let decoded = try JSONDecoder().decode(MessageType.self, from: encoded)
            XCTAssertEqual(decoded, type, "MessageType \(type) should round-trip")
        }
    }

    // MARK: - Encrypted Message Pipeline

    func testEncryptedMessagePipeline() throws {
        let alice = SessionCrypto()
        let bob = SessionCrypto()

        try alice.deriveSessionKey(peerPublicKey: bob.publicKeyData)
        try bob.deriveSessionKey(peerPublicKey: alice.publicKeyData)

        let metrics = CPUMetrics(usagePercent: 42.5, coreCount: 10, perCoreUsage: [])
        let encoded = try MessageProtocol.encode(metrics, type: .metricsResponse, using: alice)
        let decoded = try MessageProtocol.decode(encoded, as: CPUMetrics.self, using: bob)

        XCTAssertEqual(decoded.type, .metricsResponse)
        XCTAssertEqual(decoded.payload.usagePercent, 42.5, accuracy: 0.01)
        XCTAssertEqual(decoded.payload.coreCount, 10)
    }
}
