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
        let context = LAContext()
        var error: NSError?
        let canEvaluate = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)

        isAvailable = canEvaluate

        if canEvaluate {
            switch context.biometryType {
            case .faceID:
                biometricType = .faceID
            case .touchID:
                biometricType = .touchID
            case .opticID:
                biometricType = .opticID
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
        let context = LAContext()
        context.localizedFallbackTitle = "Use Passcode"
        context.localizedCancelTitle = "Cancel"

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            return success
        } catch let error as LAError {
            print("[MacPilot][BiometricAuth] Failed: \(error.localizedDescription)")
            switch error.code {
            case .biometryNotAvailable:
                print("[MacPilot][BiometricAuth] Biometrics not available")
            case .biometryNotEnrolled:
                print("[MacPilot][BiometricAuth] Biometrics not enrolled")
            case .biometryLockout:
                print("[MacPilot][BiometricAuth] Biometrics locked out — too many failed attempts")
            case .userCancel:
                print("[MacPilot][BiometricAuth] User cancelled")
            case .userFallback:
                // User chose passcode — allow fallback
                return await authenticateWithPasscode(reason: reason)
            default:
                break
            }
            return false
        } catch {
            print("[MacPilot][BiometricAuth] Unexpected error: \(error)")
            return false
        }
    }

    /// Fallback to device passcode authentication.
    private func authenticateWithPasscode(reason: String) async -> Bool {
        let context = LAContext()
        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthentication,  // includes passcode fallback
                localizedReason: reason
            )
        } catch {
            return false
        }
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
        case .opticID: return "opticid"
        case .none: return "lock"
        }
    }
}
