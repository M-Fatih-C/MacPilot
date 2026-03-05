// NetworkRestriction.swift
// MacPilot — MacPilotAgent / Server
//
// Enforces IP allowlist — only local private network connections accepted.
// Rejects any connection from public internet or non-local addresses.

import Foundation
import Network
import SharedCore

// MARK: - NetworkRestriction

/// Enforces local-network-only access policy.
///
/// Allowed ranges:
/// - `192.168.0.0/16` — Home networks
/// - `10.0.0.0/8` — Private class A
/// - `172.16.0.0/12` — Private class B
/// - `127.0.0.0/8` — Loopback (for testing)
public enum NetworkRestriction {

    /// Check if an incoming NWConnection originates from a local network.
    ///
    /// - Parameter connection: The incoming connection to validate.
    /// - Returns: `true` if the connection is from an allowed IP range.
    public static func isAllowed(connection: NWConnection) -> Bool {
        let endpoint = connection.endpoint

        switch endpoint {
        case .hostPort(let host, _):
            return isLocalAddress(host)
        default:
            // Bonjour-resolved or other endpoints — allow
            return true
        }
    }

    /// Check if a host address is within local network ranges.
    ///
    /// - Parameter host: The NWEndpoint.Host to check.
    /// - Returns: `true` if the address is local/private.
    public static func isLocalAddress(_ host: NWEndpoint.Host) -> Bool {
        switch host {
        case .ipv4(let addr):
            return isLocalIPv4(addr)
        case .ipv6(let addr):
            return isLocalIPv6(addr)
        case .name(let hostname, _):
            // Allow .local domains (Bonjour)
            return hostname.hasSuffix(".local")
        @unknown default:
            return false
        }
    }

    /// Check if an IPv4 address is in a private range.
    private static func isLocalIPv4(_ address: IPv4Address) -> Bool {
        let bytes = address.rawValue

        guard bytes.count >= 4 else { return false }

        let b0 = bytes[bytes.startIndex]
        let b1 = bytes[bytes.index(after: bytes.startIndex)]

        // 10.0.0.0/8
        if b0 == 10 {
            return true
        }

        // 172.16.0.0/12 (172.16.x.x – 172.31.x.x)
        if b0 == 172 && (b1 >= 16 && b1 <= 31) {
            return true
        }

        // 192.168.0.0/16
        if b0 == 192 && b1 == 168 {
            return true
        }

        // 127.0.0.0/8 (loopback)
        if b0 == 127 {
            return true
        }

        return false
    }

    /// Check if an IPv6 address is local (link-local or loopback).
    private static func isLocalIPv6(_ address: IPv6Address) -> Bool {
        let bytes = address.rawValue

        guard bytes.count >= 2 else { return false }

        let b0 = bytes[bytes.startIndex]
        let b1 = bytes[bytes.index(after: bytes.startIndex)]

        // fe80::/10 — link-local
        if b0 == 0xfe && (b1 & 0xc0) == 0x80 {
            return true
        }

        // ::1 — loopback
        let allZeroExceptLast = bytes.dropLast().allSatisfy { $0 == 0 }
        if allZeroExceptLast && bytes.last == 1 {
            return true
        }

        return false
    }
}
