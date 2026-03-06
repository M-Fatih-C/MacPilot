// MouseController.swift
// MacPilot — MacPilotAgent / Input
//
// Generates macOS mouse events using Quartz CGEvent API.
// Requires Accessibility permission (AXIsProcessTrusted).

import Foundation
import CoreGraphics
import SharedCore

// MARK: - MouseController

/// Controls the macOS mouse cursor via CGEvent.
///
/// Gesture mapping:
/// - 1 finger move → `kCGEventMouseMoved`
/// - Single tap → left click (`kCGEventLeftMouseDown/Up`)
/// - Two finger tap → right click (`kCGEventRightMouseDown/Up`)
/// - Two finger drag → scroll (`kCGEventScrollWheel`)
/// - Pinch → zoom (scroll with magnify flag)
public final class MouseController {

    // MARK: - Properties

    /// Current mouse position (tracked for relative movement).
    private var currentPosition: CGPoint

    /// Event source for generating events.
    private let eventSource: CGEventSource?

    // MARK: - Init

    public init() {
        // Get current mouse position
        self.currentPosition = CGEvent(source: nil)?.location ?? .zero

        // Create event source with combined session state
        self.eventSource = CGEventSource(stateID: .combinedSessionState)
    }

    // MARK: - Mouse Movement

    /// Move the mouse cursor by a relative delta.
    ///
    /// - Parameters:
    ///   - deltaX: Horizontal movement in points.
    ///   - deltaY: Vertical movement in points.
    public func moveMouse(deltaX: Double, deltaY: Double) {
        // Calculate new position
        let newX = currentPosition.x + deltaX
        let newY = currentPosition.y + deltaY

        // Clamp to screen bounds
        let screenBounds = CGDisplayBounds(CGMainDisplayID())
        let clampedX = max(0, min(newX, screenBounds.width - 1))
        let clampedY = max(0, min(newY, screenBounds.height - 1))

        let newPoint = CGPoint(x: clampedX, y: clampedY)

        guard let event = CGEvent(
            mouseEventSource: eventSource,
            mouseType: .mouseMoved,
            mouseCursorPosition: newPoint,
            mouseButton: .left
        ) else { return }

        event.post(tap: .cghidEventTap)
        currentPosition = newPoint
    }

    /// Move the mouse cursor to an absolute position.
    ///
    /// - Parameter point: The target position in screen coordinates.
    public func moveMouseAbsolute(to point: CGPoint) {
        guard let event = CGEvent(
            mouseEventSource: eventSource,
            mouseType: .mouseMoved,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else { return }

        event.post(tap: .cghidEventTap)
        currentPosition = point
    }

    // MARK: - Clicks

    /// Perform a left mouse click at the current position.
    public func leftClick() {
        mouseDown(.left)
        mouseUp(.left)
    }

    /// Press and hold the left mouse button.
    public func leftDown() {
        mouseDown(.left)
    }

    /// Release the left mouse button.
    public func leftUp() {
        mouseUp(.left)
    }

    /// Perform a right mouse click at the current position.
    public func rightClick() {
        mouseDown(.right)
        mouseUp(.right)
    }

    /// Perform a double left click at the current position.
    public func doubleClick() {
        guard let downEvent = CGEvent(
            mouseEventSource: eventSource,
            mouseType: .leftMouseDown,
            mouseCursorPosition: currentPosition,
            mouseButton: .left
        ) else { return }

        downEvent.setIntegerValueField(.mouseEventClickState, value: 2)
        downEvent.post(tap: .cghidEventTap)

        guard let upEvent = CGEvent(
            mouseEventSource: eventSource,
            mouseType: .leftMouseUp,
            mouseCursorPosition: currentPosition,
            mouseButton: .left
        ) else { return }

        upEvent.setIntegerValueField(.mouseEventClickState, value: 2)
        upEvent.post(tap: .cghidEventTap)
    }

    /// Press a mouse button down.
    private func mouseDown(_ button: CGMouseButton) {
        let eventType: CGEventType = button == .left ? .leftMouseDown : .rightMouseDown

        guard let event = CGEvent(
            mouseEventSource: eventSource,
            mouseType: eventType,
            mouseCursorPosition: currentPosition,
            mouseButton: button
        ) else { return }

        event.post(tap: .cghidEventTap)
    }

    /// Release a mouse button.
    private func mouseUp(_ button: CGMouseButton) {
        let eventType: CGEventType = button == .left ? .leftMouseUp : .rightMouseUp

        guard let event = CGEvent(
            mouseEventSource: eventSource,
            mouseType: eventType,
            mouseCursorPosition: currentPosition,
            mouseButton: button
        ) else { return }

        event.post(tap: .cghidEventTap)
    }

    // MARK: - Scroll

    /// Scroll the mouse wheel.
    ///
    /// - Parameters:
    ///   - deltaX: Horizontal scroll delta.
    ///   - deltaY: Vertical scroll delta (positive = up, negative = down).
    public func scroll(deltaX: Double, deltaY: Double) {
        guard let event = CGEvent(
            scrollWheelEvent2Source: eventSource,
            units: .pixel,
            wheelCount: 2,
            wheel1: Int32(deltaY),
            wheel2: Int32(deltaX),
            wheel3: 0
        ) else { return }

        event.post(tap: .cghidEventTap)
    }

    // MARK: - Zoom

    /// Simulate pinch-to-zoom using scroll events with magnification.
    ///
    /// - Parameter scale: Scale factor (> 1.0 = zoom in, < 1.0 = zoom out).
    public func zoom(scale: Double) {
        // Convert pinch scale to scroll delta
        let delta = Int32((scale - 1.0) * 10.0)

        guard let event = CGEvent(
            scrollWheelEvent2Source: eventSource,
            units: .pixel,
            wheelCount: 1,
            wheel1: delta,
            wheel2: 0,
            wheel3: 0
        ) else { return }

        // Set the event to use gesture-style scroll (for zoom)
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.post(tap: .cghidEventTap)
    }

    // MARK: - Process InputEvent

    /// Process a single InputEvent from the iPhone.
    ///
    /// - Parameter event: The input event to execute.
    public func processEvent(_ inputEvent: InputEvent) {
        switch inputEvent.type {
        case .mouseMove:
            if let dx = inputEvent.data.deltaX, let dy = inputEvent.data.deltaY {
                moveMouse(deltaX: dx, deltaY: dy)
            }
        case .leftClick:
            leftClick()
        case .leftDown:
            leftDown()
        case .leftUp:
            leftUp()
        case .rightClick:
            rightClick()
        case .scroll:
            let dx = inputEvent.data.scrollDeltaX ?? 0
            let dy = inputEvent.data.scrollDeltaY ?? 0
            scroll(deltaX: dx, deltaY: dy)
        case .pinchZoom:
            if let scale = inputEvent.data.pinchScale {
                zoom(scale: scale)
            }
        default:
            break // keyboard events handled by KeyboardController
        }
    }
}
