// TrustedDeviceStore.swift
// MacPilot — SharedCore / DeviceIdentity
//
// Manages the trusted device registry in Keychain.
// Replaces the insecure trusted_devices.json approach.
//
// Each trusted device is stored as a separate Keychain item:
//   service: macpilot.trusted.devices
//   account: <device_id>
//   data:    JSON-encoded DeviceInfo

import Foundation

// MARK: - TrustedDeviceStore

/// Keychain-backed storage for paired/trusted devices.
///
/// Each device is stored as a separate Keychain entry under
/// `service: macpilot.trusted.devices` with the device_id as the account.
public final class TrustedDeviceStore: Sendable {

    /// Keychain service identifier.
    private static let keychainService = "macpilot.trusted.devices"

    public static let shared = TrustedDeviceStore()

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - CRUD

    /// Store a trusted device in Keychain.
    ///
    /// - Parameter device: The device to store.
    /// - Throws: `TrustedDeviceStoreError` on Keychain failure.
    public func addTrustedDevice(_ device: DeviceInfo) throws {
        let data = try encoder.encode(device)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: device.id.uuidString,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        // Remove existing entry if present (update)
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw TrustedDeviceStoreError.keychainWriteFailed(status)
        }
    }

    /// Retrieve a trusted device by its ID.
    ///
    /// - Parameter deviceId: The UUID of the device.
    /// - Returns: The `DeviceInfo` if found, `nil` otherwise.
    public func getTrustedDevice(id deviceId: UUID) throws -> DeviceInfo? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: deviceId.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw TrustedDeviceStoreError.corruptedData
            }
            return try decoder.decode(DeviceInfo.self, from: data)
        case errSecItemNotFound:
            return nil
        default:
            throw TrustedDeviceStoreError.keychainReadFailed(status)
        }
    }

    /// Check if a device is in the trusted list.
    ///
    /// - Parameter deviceId: The UUID of the device to check.
    /// - Returns: `true` if the device is trusted.
    public func isTrusted(deviceId: UUID) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: deviceId.uuidString,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    /// Update the `lastSeen` timestamp for a trusted device.
    ///
    /// - Parameter deviceId: The UUID of the device.
    public func updateLastSeen(deviceId: UUID) throws {
        guard var device = try getTrustedDevice(id: deviceId) else {
            throw TrustedDeviceStoreError.deviceNotFound
        }

        device.lastSeen = Date()
        try addTrustedDevice(device) // re-store with updated timestamp
    }

    /// Remove a trusted device from the registry.
    ///
    /// - Parameter deviceId: The UUID of the device to remove.
    public func removeTrustedDevice(id deviceId: UUID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: deviceId.uuidString
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TrustedDeviceStoreError.keychainWriteFailed(status)
        }
    }

    /// Get all trusted devices.
    ///
    /// - Returns: Array of all stored `DeviceInfo` entries.
    public func getAllTrustedDevices() throws -> [DeviceInfo] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let items = result as? [Data] else {
                return []
            }
            return items.compactMap { try? decoder.decode(DeviceInfo.self, from: $0) }
        case errSecItemNotFound:
            return []
        default:
            throw TrustedDeviceStoreError.keychainReadFailed(status)
        }
    }

    // MARK: - Reset

    /// Remove all trusted devices. Used for testing or factory reset.
    public func removeAllTrustedDevices() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Errors

/// Errors for the trusted device store.
public enum TrustedDeviceStoreError: Error, LocalizedError {
    case keychainWriteFailed(OSStatus)
    case keychainReadFailed(OSStatus)
    case corruptedData
    case deviceNotFound

    public var errorDescription: String? {
        switch self {
        case .keychainWriteFailed(let status):
            return "[MacPilot][TrustedDevices] Keychain write failed: \(status)"
        case .keychainReadFailed(let status):
            return "[MacPilot][TrustedDevices] Keychain read failed: \(status)"
        case .corruptedData:
            return "[MacPilot][TrustedDevices] Stored device data is corrupted"
        case .deviceNotFound:
            return "[MacPilot][TrustedDevices] Device not found in trusted list"
        }
    }
}
