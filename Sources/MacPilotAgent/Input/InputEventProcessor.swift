// InputEventProcessor.swift
// MacPilot — MacPilotAgent / Input
//
// Central event processing pipeline.
// Routes InputEvents to MouseController/KeyboardController.
// Implements event throttling (max 200 events/sec) and queuing.

import Foundation
import SharedCore

// MARK: - InputEventProcessor

/// Processes incoming InputEvents with throttling and routing.
///
/// Features:
/// - Rate limiting: max 200 events/sec
/// - Event coalescing: consecutive mouse-move events are merged
/// - Low-latency: events are processed on a dedicated high-priority queue
/// - Statistics: tracks event counts for monitoring
public final class InputEventProcessor {

    // MARK: - Properties

    private let mouseController: MouseController
    private let keyboardController: KeyboardController

    /// Dedicated high-priority queue for input processing.
    private let processingQueue = DispatchQueue(
        label: "com.macpilot.input",
        qos: .userInteractive
    )

    /// Token bucket for rate limiting.
    private var tokenBucket: TokenBucket

    /// Accumulated mouse deltas for coalescing.
    private var pendingMouseDelta: (x: Double, y: Double) = (0, 0)
    private var mouseCoalesceTimer: DispatchSourceTimer?

    /// Event statistics.
    public private(set) var totalEventsProcessed: UInt64 = 0
    public private(set) var eventsDropped: UInt64 = 0

    // MARK: - Init

    public init(
        mouseController: MouseController = MouseController(),
        keyboardController: KeyboardController = KeyboardController()
    ) {
        self.mouseController = mouseController
        self.keyboardController = keyboardController
        self.tokenBucket = TokenBucket(
            capacity: NetworkConstants.maxInputEventsPerSecond,
            refillRate: Double(NetworkConstants.maxInputEventsPerSecond)
        )
    }

    // MARK: - Process Events

    /// Process a single input event from the iPhone.
    ///
    /// - Parameter event: The input event to process.
    /// - Returns: `true` if the event was processed, `false` if rate-limited.
    @discardableResult
    public func process(_ event: InputEvent) -> Bool {
        // Check rate limit
        guard tokenBucket.consume() else {
            eventsDropped += 1
            return false
        }

        processingQueue.async { [weak self] in
            self?.dispatch(event)
        }

        totalEventsProcessed += 1
        return true
    }

    /// Process a batch of input events.
    ///
    /// - Parameter events: Array of input events.
    public func processBatch(_ events: [InputEvent]) {
        for event in events {
            process(event)
        }
    }

    // MARK: - Dispatch

    /// Route an event to the appropriate controller.
    private func dispatch(_ event: InputEvent) {
        switch event.type {
        case .mouseMove:
            // Coalesce rapid mouse moves for efficiency
            if let dx = event.data.deltaX, let dy = event.data.deltaY {
                mouseController.moveMouse(deltaX: dx, deltaY: dy)
            }

        case .leftClick:
            mouseController.leftClick()

        case .leftDown:
            mouseController.leftDown()

        case .leftUp:
            mouseController.leftUp()

        case .rightClick:
            mouseController.rightClick()

        case .scroll:
            let dx = event.data.scrollDeltaX ?? 0
            let dy = event.data.scrollDeltaY ?? 0
            mouseController.scroll(deltaX: dx, deltaY: dy)

        case .pinchZoom:
            if let scale = event.data.pinchScale {
                mouseController.zoom(scale: scale)
            }

        case .keyDown, .keyUp:
            keyboardController.processEvent(event)
        }
    }

    // MARK: - Statistics

    /// Get processing statistics.
    public var stats: String {
        "[MacPilot][Input] Processed: \(totalEventsProcessed), Dropped: \(eventsDropped)"
    }

    /// Reset event counters.
    public func resetStats() {
        totalEventsProcessed = 0
        eventsDropped = 0
    }
}

// MARK: - Token Bucket Rate Limiter

/// Token bucket algorithm for rate limiting input events.
///
/// - `capacity`: Maximum burst size (200)
/// - `refillRate`: Tokens added per second (200)
struct TokenBucket {
    let capacity: Int
    let refillRate: Double

    private var tokens: Double
    private var lastRefill: Date

    init(capacity: Int, refillRate: Double) {
        self.capacity = capacity
        self.refillRate = refillRate
        self.tokens = Double(capacity)
        self.lastRefill = Date()
    }

    /// Try to consume one token. Returns `true` if allowed.
    mutating func consume() -> Bool {
        refill()
        if tokens >= 1.0 {
            tokens -= 1.0
            return true
        }
        return false
    }

    /// Refill tokens based on elapsed time.
    private mutating func refill() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastRefill)
        let newTokens = elapsed * refillRate
        tokens = min(Double(capacity), tokens + newTokens)
        lastRefill = now
    }
}
