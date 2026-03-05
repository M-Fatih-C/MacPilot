// HandshakeTests.swift
// MacPilot — Tests
//
// Validates handshake flow and device identity:
//   - DeviceInfo model
//   - MessageEnvelope wire format
//   - Pairing message flow
//   - Certificate manager

import XCTest
import CryptoKit
@testable import SharedCore

final class HandshakeTests: XCTestCase {

    // MARK: - DeviceInfo

    func testDeviceInfoCodableRoundTrip() throws {
        let device = DeviceInfo(
            deviceName: "Mac mini",
            platform: .macOS,
            publicKey: Data(repeating: 0xAB, count: 32)
        )

        let data = try JSONEncoder().encode(device)
        let decoded = try JSONDecoder().decode(DeviceInfo.self, from: data)

        XCTAssertEqual(decoded.deviceName, device.deviceName)
        XCTAssertEqual(decoded.platform, device.platform)
    }

    func testPlatformValues() {
        XCTAssertEqual(Platform.macOS.rawValue, "macOS")
        XCTAssertEqual(Platform.iOS.rawValue, "iOS")
    }

    // MARK: - MessageEnvelope

    func testMessageEnvelopeCreation() {
        let envelope = MessageEnvelope(
            type: .pairRequest,
            payload: "test".data(using: .utf8)!,
            nonce: Data(),
            tag: Data()
        )

        XCTAssertEqual(envelope.type, .pairRequest)
        XCTAssertFalse(envelope.payload.isEmpty)
        XCTAssertNotNil(envelope.id)
        XCTAssertNotNil(envelope.timestamp)
    }

    func testMessageEnvelopeCodable() throws {
        let envelope = MessageEnvelope(
            type: .authResponse,
            payload: Data([0x01, 0x02, 0x03]),
            nonce: Data([0xAA, 0xBB]),
            tag: Data([0xCC, 0xDD])
        )

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        let data = try enc.encode(envelope)

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let decoded = try dec.decode(MessageEnvelope.self, from: data)

        XCTAssertEqual(decoded.type, .authResponse)
        XCTAssertEqual(decoded.payload, envelope.payload)
        XCTAssertEqual(decoded.nonce, envelope.nonce)
        XCTAssertEqual(decoded.tag, envelope.tag)
    }

    // MARK: - Pairing Flow Simulation

    func testPairRequestResponseFlow() throws {
        // Step 1: iPhone sends pair request
        let pairReqPayload = DeviceInfo(deviceName: "iPhone 13", platform: .iOS, publicKey: Data(repeating: 0x01, count: 32))
        let pairReqData = try MessageProtocol.encodePlaintext(pairReqPayload, type: .pairRequest)

        // Step 2: Mac receives and decodes
        let decodedReq = try MessageProtocol.decodePlaintext(pairReqData, as: DeviceInfo.self)
        XCTAssertEqual(decodedReq.type, .pairRequest)
        XCTAssertEqual(decodedReq.payload.platform, .iOS)

        // Step 3: Mac responds
        let pairResPayload = DeviceInfo(deviceName: "Mac mini", platform: .macOS, publicKey: Data(repeating: 0x02, count: 32))
        let pairResData = try MessageProtocol.encodePlaintext(pairResPayload, type: .pairResponse)

        // Step 4: iPhone receives
        let decodedRes = try MessageProtocol.decodePlaintext(pairResData, as: DeviceInfo.self)
        XCTAssertEqual(decodedRes.type, .pairResponse)
        XCTAssertEqual(decodedRes.payload.platform, .macOS)
    }

    // MARK: - Key Exchange Flow

    func testEphemeralKeyExchangeFlow() throws {
        // Simulate full key exchange
        let macSession = SessionCrypto()
        let iphoneSession = SessionCrypto()

        // Step 1: Mac sends its ephemeral public key
        let macPubKeyData = macSession.publicKeyData
        XCTAssertEqual(macPubKeyData.count, 32, "X25519 public key is 32 bytes")

        // Step 2: iPhone sends its ephemeral public key
        let iphonePubKeyData = iphoneSession.publicKeyData

        // Step 3: Both sides derive session key
        try macSession.deriveSessionKey(peerPublicKey: iphonePubKeyData)
        try iphoneSession.deriveSessionKey(peerPublicKey: macPubKeyData)

        XCTAssertTrue(macSession.isEstablished)
        XCTAssertTrue(iphoneSession.isEstablished)

        // Step 4: Verify bidirectional encryption
        let testMessage = "Handshake complete!".data(using: .utf8)!

        let mac2iphone = try macSession.encrypt(testMessage)
        let decryptedByIphone = try iphoneSession.decrypt(mac2iphone)
        XCTAssertEqual(decryptedByIphone, testMessage)

        let iphone2mac = try iphoneSession.encrypt(testMessage)
        let decryptedByMac = try macSession.decrypt(iphone2mac)
        XCTAssertEqual(decryptedByMac, testMessage)
    }

    // MARK: - Certificate Manager

    func testCertificateManagerExists() {
        let certManager = CertificateManager.shared
        XCTAssertNotNil(certManager)
    }
}
