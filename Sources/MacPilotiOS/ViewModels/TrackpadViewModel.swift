// TrackpadViewModel.swift
// MacPilot — MacPilot-iOS / ViewModels
//
// Manages gesture state and sends InputEvents to the Mac.

import Foundation
import Combine
import SharedCore

// MARK: - TrackpadViewModel

/// ViewModel for the trackpad view — processes gestures and sends events.
@MainActor
public final class TrackpadViewModel: ObservableObject {

    // MARK: - Published State

    @Published public var isActive: Bool = false
    @Published public var eventsSent: Int = 0

    // MARK: - Properties

    private let connection: MacConnection

    /// Previous pan position for calculating deltas.
    private var lastPanPosition: CGPoint = .zero

    /// Previous two-finger pan position.
    private var lastScrollPosition: CGPoint = .zero

    // MARK: - Init

    public init(connection: MacConnection) {
        self.connection = connection
    }

    // MARK: - Mouse Movement (1 finger drag)

    /// Called when a single-finger pan gesture begins.
    public func panBegan(at position: CGPoint) {
        lastPanPosition = position
        isActive = true
    }

    /// Called when a single-finger pan gesture moves.
    public func panChanged(to position: CGPoint) {
        let deltaX = Double(position.x - lastPanPosition.x)
        let deltaY = Double(position.y - lastPanPosition.y)

        let event = GestureEngine.mouseMove(deltaX: deltaX, deltaY: deltaY)
        sendEvent(event)

        lastPanPosition = position
    }

    /// Called when a single-finger pan gesture ends.
    public func panEnded() {
        isActive = false
    }

    // MARK: - Clicks

    /// Called on single tap (left click).
    public func singleTap() {
        sendEvent(GestureEngine.leftClick())
    }

    /// Called on two-finger tap (right click).
    public func twoFingerTap() {
        sendEvent(GestureEngine.rightClick())
    }

    // MARK: - Scroll (2 finger drag)

    /// Called when a two-finger scroll gesture begins.
    public func scrollBegan(at position: CGPoint) {
        lastScrollPosition = position
    }

    /// Called when a two-finger scroll gesture moves.
    public func scrollChanged(to position: CGPoint) {
        let deltaX = Double(position.x - lastScrollPosition.x)
        let deltaY = Double(position.y - lastScrollPosition.y)

        let event = GestureEngine.scroll(deltaX: deltaX, deltaY: deltaY)
        sendEvent(event)

        lastScrollPosition = position
    }

    // MARK: - Pinch Zoom

    /// Called when a pinch gesture changes.
    public func pinchChanged(scale: Double) {
        let event = GestureEngine.pinchZoom(scale: scale)
        sendEvent(event)
    }

    // MARK: - Keyboard

    /// Send a key press event.
    public func sendKeyPress(keyCode: UInt16, modifiers: UInt = 0) {
        let down = GestureEngine.keyEvent(keyCode: keyCode, modifiers: modifiers, isDown: true)
        let up = GestureEngine.keyEvent(keyCode: keyCode, modifiers: modifiers, isDown: false)
        sendEvent(down)
        sendEvent(up)
    }

    // MARK: - Send

    /// Encode and send an InputEvent over the connection.
    private func sendEvent(_ event: InputEvent) {
        do {
            let data = try MessageProtocol.encodePlaintext(event, type: event.type.messageType)
            connection.send(data)
            eventsSent += 1
        } catch {
            print("[MacPilot][Trackpad] Failed to encode event: \(error.localizedDescription)")
        }
    }
}

// MARK: - InputEventType → MessageType

extension InputEventType {
    /// Map InputEventType to the corresponding MessageType for wire transmission.
    var messageType: MessageType {
        switch self {
        case .mouseMove: return .mouseMove
        case .leftClick, .rightClick: return .mouseClick
        case .scroll: return .mouseScroll
        case .pinchZoom: return .mouseScroll
        case .keyDown: return .keyPress
        case .keyUp: return .keyRelease
        }
    }
}
