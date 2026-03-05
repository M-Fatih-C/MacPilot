// GestureEngine.swift
// MacPilot — MacPilot-iOS / Services
//
// Converts iOS UIGestureRecognizer data into MacPilot InputEvents.
// This is the bridge between iPhone touch input and Mac CGEvent output.

import Foundation
import SharedCore

// MARK: - GestureEngine

/// Converts raw gesture data from iOS into MacPilot InputEvents.
///
/// Gesture Mapping:
/// ```
/// 1 finger drag   → mouseMove (deltaX, deltaY)
/// single tap       → leftClick
/// two finger tap   → rightClick
/// two finger drag  → scroll (deltaX, deltaY)
/// pinch            → pinchZoom (scale)
/// ```
public enum GestureEngine {

    // MARK: - Sensitivity

    /// Mouse movement sensitivity multiplier.
    /// Higher values = faster cursor movement per finger distance.
    public static var mouseSensitivity: Double = 1.5

    /// Scroll sensitivity multiplier.
    public static var scrollSensitivity: Double = 1.0

    // MARK: - Mouse Movement

    /// Create a mouseMove event from a pan gesture translation delta.
    ///
    /// - Parameters:
    ///   - deltaX: Horizontal translation change (in points).
    ///   - deltaY: Vertical translation change (in points).
    /// - Returns: An `InputEvent` of type `.mouseMove`.
    public static func mouseMove(deltaX: Double, deltaY: Double) -> InputEvent {
        InputEvent(
            type: .mouseMove,
            data: InputEventData(
                deltaX: deltaX * mouseSensitivity,
                deltaY: deltaY * mouseSensitivity
            )
        )
    }

    // MARK: - Clicks

    /// Create a left click event.
    public static func leftClick() -> InputEvent {
        InputEvent(
            type: .leftClick,
            data: InputEventData()
        )
    }

    /// Create a right click event.
    public static func rightClick() -> InputEvent {
        InputEvent(
            type: .rightClick,
            data: InputEventData()
        )
    }

    // MARK: - Scroll

    /// Create a scroll event from a two-finger pan gesture.
    ///
    /// - Parameters:
    ///   - deltaX: Horizontal scroll delta.
    ///   - deltaY: Vertical scroll delta.
    /// - Returns: An `InputEvent` of type `.scroll`.
    public static func scroll(deltaX: Double, deltaY: Double) -> InputEvent {
        InputEvent(
            type: .scroll,
            data: InputEventData(
                scrollDeltaX: deltaX * scrollSensitivity,
                scrollDeltaY: deltaY * scrollSensitivity
            )
        )
    }

    // MARK: - Zoom

    /// Create a pinch zoom event.
    ///
    /// - Parameter scale: The pinch scale factor (1.0 = no change).
    /// - Returns: An `InputEvent` of type `.pinchZoom`.
    public static func pinchZoom(scale: Double) -> InputEvent {
        InputEvent(
            type: .pinchZoom,
            data: InputEventData(pinchScale: scale)
        )
    }

    // MARK: - Keyboard

    /// Create a key press event.
    ///
    /// - Parameters:
    ///   - keyCode: The macOS virtual key code.
    ///   - modifiers: Modifier flags.
    ///   - isDown: Whether this is a key-down (`true`) or key-up (`false`) event.
    /// - Returns: An `InputEvent` of type `.keyDown` or `.keyUp`.
    public static func keyEvent(keyCode: UInt16, modifiers: UInt = 0, isDown: Bool) -> InputEvent {
        InputEvent(
            type: isDown ? .keyDown : .keyUp,
            data: InputEventData(
                keyCode: keyCode,
                modifiers: modifiers
            )
        )
    }
}
