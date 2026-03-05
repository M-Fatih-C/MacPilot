// MessageType.swift
// MacPilot — SharedCore
//
// Defines all WebSocket message types used in MacPilot protocol.

import Foundation

/// All message types exchanged between iPhone and Mac.
public enum MessageType: String, Codable, Sendable {

    // MARK: - Auth & Pairing

    case pairRequest
    case pairResponse
    case authChallenge
    case authResponse
    case ephemeralKeyExchange

    // MARK: - Input Control

    case mouseMove
    case mouseClick
    case mouseScroll
    case keyPress
    case keyRelease

    // MARK: - System Metrics

    case metricsRequest
    case metricsResponse
    case processListRequest
    case processListResponse

    // MARK: - Commands

    case commandRequest
    case commandResponse

    // MARK: - File Transfer

    case fileBrowseRequest
    case fileBrowseResponse
    case fileDownloadRequest
    case fileDownloadChunk
    case fileUploadStart
    case fileUploadChunk
    case fileUploadAck

    // MARK: - Control

    case ping
    case pong
    case error
}
