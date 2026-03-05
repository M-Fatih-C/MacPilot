// DeviceInfo.swift
// MacPilot — SharedCore
//
// Device identity model used for pairing and authentication.

import Foundation

/// Represents a MacPilot device (Mac or iPhone).
public struct DeviceInfo: Codable, Sendable, Identifiable {
    /// Unique device identifier (generated once, stored in Keychain).
    public let id: UUID

    /// Human-readable device name (e.g. "Fatih's Mac mini").
    public let deviceName: String

    /// Platform this device runs on.
    public let platform: Platform

    /// Curve25519 public key bytes (shared during pairing).
    public let publicKey: Data

    /// When this device identity was first created.
    public let createdAt: Date

    /// Last time this device was seen online.
    public var lastSeen: Date

    public init(
        id: UUID = UUID(),
        deviceName: String,
        platform: Platform,
        publicKey: Data,
        createdAt: Date = Date(),
        lastSeen: Date = Date()
    ) {
        self.id = id
        self.deviceName = deviceName
        self.platform = platform
        self.publicKey = publicKey
        self.createdAt = createdAt
        self.lastSeen = lastSeen
    }
}

/// Target platform for a MacPilot device.
public enum Platform: String, Codable, Sendable {
    case macOS
    case iOS
}
