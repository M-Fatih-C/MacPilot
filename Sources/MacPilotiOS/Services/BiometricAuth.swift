// BiometricAuth.swift
// MacPilot — MacPilot-iOS / Services
//
// FaceID / TouchID authentication wrapper using LocalAuthentication.
// Gates destructive and sensitive operations behind biometric verification.

import Foundation
import LocalAuthentication

// MARK: - BiometricAuth

/// Manages biometric (FaceID/TouchID) authentication for sensitive operations.
///
/// Protected operations:
/// - Shutdown / Restart
/// - Script execution
/// - File upload
/// - Device pairing
@MainActor
public final class BiometricAuth: ObservableObject {

    // MARK: - Published State

    /// Whether biometric authentication is available on this device.
    @Published public private(set) var isAvailable: Bool = false

    /// The type of biometric available.
    @Published public private(set) var biometricType: BiometricType = .none

    // MARK: - Singleton

    public static let shared = BiometricAuth()

    private init() {
        checkAvailability()
    }

    // MARK: - Availability

    /// Check if biometric authentication is available.
    public func checkAvailability() {
        let context = makeContext()

        var biometricError: NSError?
        let canUseBiometrics = context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: &biometricError
        )

        // Availability means user can complete a secure auth flow
        // (biometric and/or passcode fallback).
        var deviceAuthError: NSError?
        let canUseDeviceAuth = context.canEvaluatePolicy(
            .deviceOwnerAuthentication,
            error: &deviceAuthError
        )

        isAvailable = canUseDeviceAuth

        if canUseBiometrics {
            switch context.biometryType {
            case .faceID:
                biometricType = .faceID
            case .touchID:
                biometricType = .touchID
            case .opticID:
                biometricType = .opticID
            case .none:
                biometricType = .none
            @unknown default:
                biometricType = .none
            }
        } else {
            biometricType = .none
        }
    }

    // MARK: - Authenticate

    /// Authenticate the user with FaceID/TouchID before performing a sensitive action.
    ///
    /// - Parameters:
    ///   - reason: The reason string shown to the user (e.g., "Authorize shutdown").
    /// - Returns: `true` if authentication succeeded.
    public func authenticate(reason: String) async -> Bool {
        defer { checkAvailability() }

        let biometricContext = makeContext()
        var biometricError: NSError?
        let canUseBiometrics = biometricContext.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: &biometricError
        )

        if canUseBiometrics {
            do {
                return try await biometricContext.evaluatePolicy(
                    .deviceOwnerAuthenticationWithBiometrics,
                    localizedReason: reason
                )
            } catch let error as LAError {
                print("[MacPilot][BiometricAuth] Biometric auth failed: \(error.localizedDescription)")
                switch error.code {
                case .userCancel, .appCancel, .systemCancel:
                    return false
                case .biometryLockout, .biometryNotAvailable, .biometryNotEnrolled, .userFallback:
                    return await authenticateWithPasscode(reason: reason)
                default:
                    // For other LA errors, still attempt passcode so protected actions remain usable.
                    return await authenticateWithPasscode(reason: reason)
                }
            } catch {
                print("[MacPilot][BiometricAuth] Unexpected biometric error: \(error)")
                return await authenticateWithPasscode(reason: reason)
            }
        }

        // No biometric path available -> try passcode/device auth.
        return await authenticateWithPasscode(reason: reason)
    }

    /// Fallback to device passcode authentication.
    private func authenticateWithPasscode(reason: String) async -> Bool {
        let context = makeContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            if let error {
                print("[MacPilot][BiometricAuth] Passcode auth unavailable: \(error.localizedDescription)")
            }
            return false
        }

        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthentication,  // includes passcode fallback
                localizedReason: reason
            )
        } catch let error as LAError {
            print("[MacPilot][BiometricAuth] Passcode auth failed: \(error.localizedDescription)")
            switch error.code {
            case .userCancel, .appCancel, .systemCancel:
                return false
            default:
                return false
            }
        } catch {
            print("[MacPilot][BiometricAuth] Unexpected passcode auth error: \(error)")
            return false
        }
    }

    private func makeContext() -> LAContext {
        let context = LAContext()
        context.localizedFallbackTitle = "Use Passcode"
        context.localizedCancelTitle = "Cancel"
        return context
    }

    // MARK: - Convenience

    /// Authenticate before shutdown/restart.
    public func authenticateForShutdown() async -> Bool {
        await authenticate(reason: "Authorize system shutdown")
    }

    /// Authenticate before restart.
    public func authenticateForRestart() async -> Bool {
        await authenticate(reason: "Authorize system restart")
    }

    /// Authenticate before executing a script/command.
    public func authenticateForScriptExecution() async -> Bool {
        await authenticate(reason: "Authorize script execution")
    }

    /// Authenticate before file upload.
    public func authenticateForFileUpload() async -> Bool {
        await authenticate(reason: "Authorize file upload to Mac")
    }

    /// Authenticate before device pairing.
    public func authenticateForPairing() async -> Bool {
        await authenticate(reason: "Authorize device pairing")
    }
}

// MARK: - BiometricType

/// The type of biometric authentication available.
public enum BiometricType: String, Sendable {
    case faceID = "Face ID"
    case touchID = "Touch ID"
    case opticID = "Optic ID"
    case none = "None"

    /// SF Symbol for this biometric type.
    public var icon: String {
        switch self {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .opticID: return "eye"
        case .none: return "lock"
        }
    }
}
