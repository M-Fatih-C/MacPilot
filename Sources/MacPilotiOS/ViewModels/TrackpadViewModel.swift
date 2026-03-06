// TrackpadViewModel.swift
// MacPilot — MacPilot-iOS / ViewModels
//
// Manages gesture state and sends InputEvents to the Mac.

import Foundation
import Combine
import QuartzCore
import CoreGraphics
import UIKit
import SharedCore

// MARK: - TrackpadViewModel

/// ViewModel for the trackpad view — processes gestures and sends events.
@MainActor
public final class TrackpadViewModel: ObservableObject {

    // MARK: - Published State

    @Published public var isActive: Bool = false
    @Published public var eventsSent: Int = 0

    // MARK: - Properties

    private let connection: AnyMacConnectionService
    private let hapticEngine = TrackpadHapticEngine()

    /// Previous pan position for calculating deltas.
    private var lastPanPosition: CGPoint = .zero

    /// Previous two-finger pan position.
    private var lastScrollPosition: CGPoint = .zero
    private var lastPanTimestamp: CFTimeInterval?
    private var lastScrollTimestamp: CFTimeInterval?
    private var smoothedPanDelta: CGPoint = .zero
    private var smoothedScrollDelta: CGPoint = .zero
    private var scrollMomentumTask: Task<Void, Never>?
    private var isDragging: Bool = false

    private enum Tuning {
        static let pointerSpeedForMaxGain: Double = 2200.0
        static let pointerMinGain: Double = 0.9
        static let pointerMaxGain: Double = 2.6
        static let pointerGainExponent: Double = 0.65
        static let pointerSmoothingBlend: Double = 0.55
        static let pointerDeadzone: Double = 0.10

        static let scrollSpeedForMaxGain: Double = 1800.0
        static let scrollMinGain: Double = 0.9
        static let scrollMaxGain: Double = 1.45
        static let scrollSmoothingBlend: Double = 0.45
        static let scrollDeadzone: Double = 0.20
        static let scrollMomentumVelocityFactor: Double = 0.012
        static let scrollMomentumDecay: Double = 0.90
        static let scrollMomentumMinimum: Double = 0.25
        static let scrollMomentumIntervalNanos: UInt64 = 8_000_000
    }

    private enum ModifierMask {
        static let command: UInt = 0x100000
        static let control: UInt = 0x40000
    }

    private enum KeyCode {
        static let d: UInt16 = 0x02
        static let f4: UInt16 = 0x76
        static let f11: UInt16 = 0x67
        static let leftArrow: UInt16 = 0x7B
        static let rightArrow: UInt16 = 0x7C
        static let downArrow: UInt16 = 0x7D
        static let upArrow: UInt16 = 0x7E
    }

    public enum MultiFingerSwipeDirection {
        case left
        case right
        case up
        case down
    }

    // MARK: - Init

    public init(connection: AnyMacConnectionService) {
        self.connection = connection
    }

    deinit {
        scrollMomentumTask?.cancel()
    }

    // MARK: - Mouse Movement (1 finger drag)

    /// Called when a single-finger pan gesture begins.
    public func panBegan(at position: CGPoint) {
        lastPanPosition = position
        lastPanTimestamp = nil
        smoothedPanDelta = .zero
        isActive = true
    }

    /// Called when a single-finger pan gesture moves.
    public func panChanged(to position: CGPoint) {
        let deltaX = Double(position.x - lastPanPosition.x)
        let deltaY = Double(position.y - lastPanPosition.y)

        panChanged(by: CGPoint(x: deltaX, y: deltaY))

        lastPanPosition = position
    }

    /// Called when a single-finger pan gesture moves with incremental delta.
    public func panChanged(by delta: CGPoint) {
        let adjusted = adjustedPointerDelta(rawDelta: delta)
        guard hypot(adjusted.x, adjusted.y) >= Tuning.pointerDeadzone else { return }

        let event = GestureEngine.mouseMove(deltaX: adjusted.x, deltaY: adjusted.y)
        sendEvent(event)
    }

    /// Called when a single-finger pan gesture ends.
    public func panEnded() {
        isActive = false
        lastPanTimestamp = nil
        smoothedPanDelta = .zero
    }

    // MARK: - Clicks

    /// Called on single tap (left click).
    public func singleTap() {
        sendEvent(GestureEngine.leftClick())
        hapticEngine.impact(.light)
    }

    /// Called on double tap (double left click).
    public func doubleTap() {
        sendEvent(GestureEngine.leftClick())
        sendEvent(GestureEngine.leftClick())
        hapticEngine.impact(.medium)
    }

    /// Called on two-finger tap (right click).
    public func twoFingerTap() {
        sendEvent(GestureEngine.rightClick())
        hapticEngine.impact(.medium)
    }

    /// Called on two-finger double tap (smart zoom-like shortcut).
    public func twoFingerDoubleTap() {
        doubleTap()
        hapticEngine.impact(.heavy)
    }

    // MARK: - Drag (3 finger drag)

    /// Start drag-and-drop mode by holding left button.
    public func dragBegan() {
        guard !isDragging else { return }
        isDragging = true
        lastPanTimestamp = nil
        smoothedPanDelta = .zero
        sendEvent(GestureEngine.leftDown())
        hapticEngine.selectionChanged()
        isActive = true
    }

    /// Move cursor while left button is held.
    public func dragChanged(by delta: CGPoint) {
        let adjusted = adjustedPointerDelta(rawDelta: delta)
        guard hypot(adjusted.x, adjusted.y) >= Tuning.pointerDeadzone else { return }
        let event = GestureEngine.mouseMove(deltaX: adjusted.x, deltaY: adjusted.y)
        sendEvent(event)
    }

    /// End drag-and-drop mode.
    public func dragEnded() {
        guard isDragging else { return }
        isDragging = false
        sendEvent(GestureEngine.leftUp())
        hapticEngine.selectionChanged()
        isActive = false
        lastPanTimestamp = nil
        smoothedPanDelta = .zero
    }

    // MARK: - System Gestures (4 finger swipe)

    /// Four-finger swipe mappings for Spaces and Mission Control actions.
    public func fourFingerSwipe(_ direction: MultiFingerSwipeDirection) {
        switch direction {
        case .left:
            // Next space
            sendKeyPress(keyCode: KeyCode.rightArrow, modifiers: ModifierMask.control)
        case .right:
            // Previous space
            sendKeyPress(keyCode: KeyCode.leftArrow, modifiers: ModifierMask.control)
        case .up:
            // Mission Control
            sendKeyPress(keyCode: KeyCode.upArrow, modifiers: ModifierMask.control)
        case .down:
            // App Expose
            sendKeyPress(keyCode: KeyCode.downArrow, modifiers: ModifierMask.control)
        }
        hapticEngine.notification(.success)
    }

    /// Three-finger tap maps to macOS "Look up" shortcut.
    public func threeFingerTapLookup() {
        sendKeyPress(
            keyCode: KeyCode.d,
            modifiers: ModifierMask.control | ModifierMask.command
        )
        hapticEngine.impact(.light)
    }

    /// Four-finger pinch-in maps to Launchpad.
    public func launchpadGesture() {
        sendKeyPress(keyCode: KeyCode.f4)
        hapticEngine.notification(.success)
    }

    /// Four-finger pinch-out maps to Show Desktop.
    public func showDesktopGesture() {
        sendKeyPress(keyCode: KeyCode.f11)
        hapticEngine.notification(.success)
    }

    // MARK: - Scroll (2 finger drag)

    /// Called when a two-finger scroll gesture begins.
    public func scrollBegan(at position: CGPoint) {
        scrollMomentumTask?.cancel()
        lastScrollPosition = position
        lastScrollTimestamp = nil
        smoothedScrollDelta = .zero
    }

    /// Called when a two-finger scroll gesture moves.
    public func scrollChanged(to position: CGPoint) {
        let deltaX = Double(position.x - lastScrollPosition.x)
        let deltaY = Double(position.y - lastScrollPosition.y)

        scrollChanged(by: CGPoint(x: deltaX, y: deltaY))

        lastScrollPosition = position
    }

    /// Called when a two-finger scroll gesture moves with incremental delta.
    public func scrollChanged(by delta: CGPoint) {
        scrollMomentumTask?.cancel()
        let adjusted = adjustedScrollDelta(rawDelta: delta)
        guard hypot(adjusted.x, adjusted.y) >= Tuning.scrollDeadzone else { return }

        let event = GestureEngine.scroll(deltaX: adjusted.x, deltaY: adjusted.y)
        sendEvent(event)
    }

    /// Called when a two-finger scroll gesture ends.
    public func scrollEnded(with velocity: CGPoint) {
        let initialVelocity = CGPoint(
            x: velocity.x * Tuning.scrollMomentumVelocityFactor,
            y: -velocity.y * Tuning.scrollMomentumVelocityFactor
        )
        let initialMagnitude = hypot(initialVelocity.x, initialVelocity.y)
        guard initialMagnitude >= Tuning.scrollMomentumMinimum else {
            lastScrollTimestamp = nil
            smoothedScrollDelta = .zero
            return
        }

        scrollMomentumTask?.cancel()
        scrollMomentumTask = Task { [weak self] in
            var momentum = initialVelocity
            while !Task.isCancelled {
                let magnitude = hypot(momentum.x, momentum.y)
                if magnitude < Tuning.scrollMomentumMinimum {
                    break
                }

                self?.sendMomentumScroll(momentum)
                momentum = CGPoint(
                    x: momentum.x * Tuning.scrollMomentumDecay,
                    y: momentum.y * Tuning.scrollMomentumDecay
                )
                try? await Task.sleep(nanoseconds: Tuning.scrollMomentumIntervalNanos)
            }
        }
    }

    // MARK: - Pinch Zoom

    /// Called when a pinch gesture changes.
    public func pinchChanged(scale: Double) {
        guard abs(scale - 1.0) > 0.01 else { return }
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

    private func adjustedPointerDelta(rawDelta: CGPoint) -> CGPoint {
        let now = CACurrentMediaTime()
        let dt = elapsedTime(now: now, previous: &lastPanTimestamp)

        // iOS has Y-down coordinates; macOS cursor space is Y-up.
        let normalized = CGPoint(x: rawDelta.x, y: -rawDelta.y)
        let speed = hypot(normalized.x, normalized.y) / dt
        let speedRatio = min(1.0, speed / Tuning.pointerSpeedForMaxGain)
        let gain = Tuning.pointerMinGain
            + (Tuning.pointerMaxGain - Tuning.pointerMinGain)
            * pow(speedRatio, Tuning.pointerGainExponent)

        let accelerated = CGPoint(x: normalized.x * gain, y: normalized.y * gain)
        smoothedPanDelta = lowPass(previous: smoothedPanDelta, current: accelerated, blend: Tuning.pointerSmoothingBlend)
        return smoothedPanDelta
    }

    private func adjustedScrollDelta(rawDelta: CGPoint) -> CGPoint {
        let now = CACurrentMediaTime()
        let dt = elapsedTime(now: now, previous: &lastScrollTimestamp)

        // Keep the same natural direction as a MacBook trackpad.
        let normalized = CGPoint(x: rawDelta.x, y: -rawDelta.y)
        let speed = hypot(normalized.x, normalized.y) / dt
        let speedRatio = min(1.0, speed / Tuning.scrollSpeedForMaxGain)
        let gain = Tuning.scrollMinGain + (Tuning.scrollMaxGain - Tuning.scrollMinGain) * speedRatio

        let accelerated = CGPoint(x: normalized.x * gain, y: normalized.y * gain)
        smoothedScrollDelta = lowPass(previous: smoothedScrollDelta, current: accelerated, blend: Tuning.scrollSmoothingBlend)
        return smoothedScrollDelta
    }

    private func lowPass(previous: CGPoint, current: CGPoint, blend: Double) -> CGPoint {
        let keep = 1.0 - blend
        return CGPoint(
            x: (previous.x * keep) + (current.x * blend),
            y: (previous.y * keep) + (current.y * blend)
        )
    }

    private func elapsedTime(now: CFTimeInterval, previous: inout CFTimeInterval?) -> Double {
        let dt: CFTimeInterval
        if let previous {
            dt = max(1.0 / 240.0, min(0.05, now - previous))
        } else {
            dt = 1.0 / 120.0
        }
        previous = now
        return dt
    }

    private func sendMomentumScroll(_ delta: CGPoint) {
        let event = GestureEngine.scroll(deltaX: delta.x, deltaY: delta.y)
        sendEvent(event)
    }
}

private final class TrackpadHapticEngine {
    private enum Keys {
        static let hapticFeedback = "hapticFeedback"
    }

    private var impactGenerators: [UIImpactFeedbackGenerator.FeedbackStyle: UIImpactFeedbackGenerator] = [
        .light: UIImpactFeedbackGenerator(style: .light),
        .medium: UIImpactFeedbackGenerator(style: .medium),
        .heavy: UIImpactFeedbackGenerator(style: .heavy)
    ]
    private let selectionGenerator = UISelectionFeedbackGenerator()
    private let notificationGenerator = UINotificationFeedbackGenerator()

    func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard isEnabled else { return }
        let generator = impactGenerators[style] ?? UIImpactFeedbackGenerator(style: style)
        impactGenerators[style] = generator
        generator.impactOccurred()
        generator.prepare()
    }

    func selectionChanged() {
        guard isEnabled else { return }
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
    }

    func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard isEnabled else { return }
        notificationGenerator.notificationOccurred(type)
        notificationGenerator.prepare()
    }

    private var isEnabled: Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Keys.hapticFeedback) != nil else {
            return true
        }
        return defaults.bool(forKey: Keys.hapticFeedback)
    }
}

// MARK: - InputEventType → MessageType

extension InputEventType {
    /// Map InputEventType to the corresponding MessageType for wire transmission.
    var messageType: MessageType {
        switch self {
        case .mouseMove: return .mouseMove
        case .leftClick, .leftDown, .leftUp, .rightClick: return .mouseClick
        case .scroll: return .mouseScroll
        case .pinchZoom: return .mouseScroll
        case .keyDown: return .keyPress
        case .keyUp: return .keyRelease
        }
    }
}
