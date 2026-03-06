// InputEvent.swift
// MacPilot — SharedCore
//
// Input event models for mouse and keyboard control.
// iPhone captures gestures → sends InputEvent → Mac generates CGEvent.

import Foundation

/// A single input event sent from iPhone to Mac.
public struct InputEvent: Codable, Sendable {
    /// Type of input event.
    public let type: InputEventType

    /// When this event was generated on the iPhone.
    public let timestamp: Date

    /// Event-specific data.
    public let data: InputEventData

    public init(type: InputEventType, timestamp: Date = Date(), data: InputEventData) {
        self.type = type
        self.timestamp = timestamp
        self.data = data
    }
}

/// Type of input event.
public enum InputEventType: String, Codable, Sendable {
    /// Mouse cursor movement (1 finger drag on trackpad).
    case mouseMove

    /// Left mouse click (single tap).
    case leftClick

    /// Left mouse button down (used for drag-and-drop).
    case leftDown

    /// Left mouse button up (used for drag-and-drop).
    case leftUp

    /// Right mouse click (two finger tap).
    case rightClick

    /// Scroll wheel (two finger drag).
    case scroll

    /// Pinch-to-zoom gesture.
    case pinchZoom

    /// Key press down.
    case keyDown

    /// Key release.
    case keyUp
}

/// Data payload for an input event.
/// Optional fields are populated depending on `InputEventType`.
public struct InputEventData: Codable, Sendable {
    // MARK: Mouse Movement
    /// Horizontal mouse delta (points).
    public var deltaX: Double?

    /// Vertical mouse delta (points).
    public var deltaY: Double?

    // MARK: Scroll
    /// Horizontal scroll delta.
    public var scrollDeltaX: Double?

    /// Vertical scroll delta.
    public var scrollDeltaY: Double?

    // MARK: Zoom
    /// Pinch scale factor (1.0 = no change).
    public var pinchScale: Double?

    // MARK: Keyboard
    /// macOS virtual key code.
    public var keyCode: UInt16?

    /// Modifier flags (shift, cmd, alt, ctrl).
    public var modifiers: UInt?

    public init(
        deltaX: Double? = nil,
        deltaY: Double? = nil,
        scrollDeltaX: Double? = nil,
        scrollDeltaY: Double? = nil,
        pinchScale: Double? = nil,
        keyCode: UInt16? = nil,
        modifiers: UInt? = nil
    ) {
        self.deltaX = deltaX
        self.deltaY = deltaY
        self.scrollDeltaX = scrollDeltaX
        self.scrollDeltaY = scrollDeltaY
        self.pinchScale = pinchScale
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}
