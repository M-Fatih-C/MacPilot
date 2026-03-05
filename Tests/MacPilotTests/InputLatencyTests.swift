// InputLatencyTests.swift
// MacPilot — Tests
//
// Validates input event pipeline performance:
//   - Event creation latency
//   - Event encoding speed
//   - Batch processing throughput
//   - Wire size

import XCTest
@testable import SharedCore

final class InputLatencyTests: XCTestCase {

    // MARK: - Event Creation

    func testMouseMoveEventCreation() {
        measure {
            for _ in 0..<1000 {
                _ = InputEvent(
                    type: .mouseMove,
                    data: InputEventData(deltaX: 1.5, deltaY: -2.0)
                )
            }
        }
    }

    func testKeyEventCreation() {
        measure {
            for _ in 0..<1000 {
                _ = InputEvent(
                    type: .keyDown,
                    data: InputEventData(keyCode: 0x08, modifiers: 0x100000)
                )
            }
        }
    }

    // MARK: - Encoding

    func testMouseMoveEncodingThroughput() {
        let event = InputEvent(type: .mouseMove, data: InputEventData(deltaX: 10.5, deltaY: -3.2))

        measure {
            for _ in 0..<1000 {
                _ = try? MessageProtocol.encodePlaintext(event, type: .mouseMove)
            }
        }
    }

    func testKeyEventEncodingThroughput() {
        let event = InputEvent(type: .keyDown, data: InputEventData(keyCode: 0x31, modifiers: 0x100000))

        measure {
            for _ in 0..<1000 {
                _ = try? MessageProtocol.encodePlaintext(event, type: .keyPress)
            }
        }
    }

    // MARK: - Decoding

    func testMouseMoveDecodingThroughput() throws {
        let event = InputEvent(type: .mouseMove, data: InputEventData(deltaX: 10.5, deltaY: -3.2))
        let encoded = try MessageProtocol.encodePlaintext(event, type: .mouseMove)

        measure {
            for _ in 0..<1000 {
                _ = try? MessageProtocol.decodePlaintext(encoded, as: InputEvent.self)
            }
        }
    }

    // MARK: - Latency Budgets

    func testSingleEventEncodingUnder1ms() throws {
        let event = InputEvent(type: .mouseMove, data: InputEventData(deltaX: 5.0, deltaY: -3.0))

        let start = CFAbsoluteTimeGetCurrent()
        _ = try MessageProtocol.encodePlaintext(event, type: .mouseMove)
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        XCTAssertLessThan(elapsed, 0.001, "Single encode should be < 1ms")
    }

    func testRoundTripUnder2ms() throws {
        let event = InputEvent(type: .keyDown, data: InputEventData(keyCode: 0x31, modifiers: 0))

        let start = CFAbsoluteTimeGetCurrent()
        let encoded = try MessageProtocol.encodePlaintext(event, type: .keyPress)
        let decoded = try MessageProtocol.decodePlaintext(encoded, as: InputEvent.self)
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        XCTAssertEqual(decoded.payload.type, .keyDown)
        XCTAssertLessThan(elapsed, 0.002, "Round-trip should be < 2ms")
    }

    // MARK: - Wire Size

    func testMouseMoveWireSize() throws {
        let event = InputEvent(type: .mouseMove, data: InputEventData(deltaX: 10.5, deltaY: -3.2))
        let encoded = try MessageProtocol.encodePlaintext(event, type: .mouseMove)

        XCTAssertLessThan(encoded.count, 500, "Mouse move wire size should be compact")
    }

    // MARK: - Batch

    func testBatchEncodingThroughput() {
        let events = (0..<100).map { i in
            InputEvent(type: .mouseMove, data: InputEventData(deltaX: Double(i), deltaY: Double(-i)))
        }

        measure {
            for event in events {
                _ = try? MessageProtocol.encodePlaintext(event, type: .mouseMove)
            }
        }
    }

    // MARK: - InputEvent Types

    func testAllInputEventTypes() {
        let types: [InputEventType] = [
            .mouseMove, .leftClick, .rightClick,
            .scroll, .pinchZoom,
            .keyDown, .keyUp
        ]

        for type in types {
            let event = InputEvent(type: type, data: InputEventData())
            XCTAssertEqual(event.type, type)
        }
    }

    // MARK: - Rate Limiter Logic

    func testTokenBucketBasicLogic() {
        // Simulate a token bucket: 200 capacity, consume 200, next should fail
        var tokens: Double = 200
        let capacity: Double = 200

        var consumed = 0
        for _ in 0..<200 {
            if tokens >= 1.0 {
                tokens -= 1.0
                consumed += 1
            }
        }
        XCTAssertEqual(consumed, 200)
        XCTAssertLessThan(tokens, 1.0, "Bucket should be empty")

        // Refill: simulate 100ms at 200/sec = 20 tokens
        let elapsed = 0.1
        let refillRate = 200.0
        tokens = min(capacity, tokens + elapsed * refillRate)
        XCTAssertEqual(tokens, 20.0, accuracy: 0.01)
    }
}
