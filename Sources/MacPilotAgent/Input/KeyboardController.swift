// KeyboardController.swift
// MacPilot — MacPilotAgent / Input
//
// Generates macOS keyboard events using Quartz CGEvent API.
// Requires Accessibility permission.

import Foundation
import CoreGraphics
import AppKit
import SharedCore

// MARK: - KeyboardController

/// Controls macOS keyboard input via CGEvent.
///
/// Generates key press and release events with modifier support.
public final class KeyboardController {

    // MARK: - Properties

    /// Event source for generating keyboard events.
    private let eventSource: CGEventSource?

    // MARK: - Init

    public init() {
        self.eventSource = CGEventSource(stateID: .combinedSessionState)
    }

    // MARK: - Key Events

    /// Press a key down.
    ///
    /// - Parameters:
    ///   - keyCode: The macOS virtual key code.
    ///   - modifiers: Modifier flags (shift, cmd, alt, ctrl).
    public func keyDown(keyCode: UInt16, modifiers: CGEventFlags = []) {
        guard let event = CGEvent(
            keyboardEventSource: eventSource,
            virtualKey: keyCode,
            keyDown: true
        ) else { return }

        if !modifiers.isEmpty {
            event.flags = modifiers
        }

        event.post(tap: .cghidEventTap)
    }

    /// Release a key.
    ///
    /// - Parameters:
    ///   - keyCode: The macOS virtual key code.
    ///   - modifiers: Modifier flags.
    public func keyUp(keyCode: UInt16, modifiers: CGEventFlags = []) {
        guard let event = CGEvent(
            keyboardEventSource: eventSource,
            virtualKey: keyCode,
            keyDown: false
        ) else { return }

        if !modifiers.isEmpty {
            event.flags = modifiers
        }

        event.post(tap: .cghidEventTap)
    }

    /// Press and release a key (full keystroke).
    ///
    /// - Parameters:
    ///   - keyCode: The macOS virtual key code.
    ///   - modifiers: Modifier flags.
    public func keyPress(keyCode: UInt16, modifiers: CGEventFlags = []) {
        keyDown(keyCode: keyCode, modifiers: modifiers)
        keyUp(keyCode: keyCode, modifiers: modifiers)
    }

    /// Type a string by generating key events for each character.
    ///
    /// - Parameter text: The text to type.
    public func typeText(_ text: String) {
        for scalar in text.unicodeScalars {
            guard let event = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: true) else {
                continue
            }

            var char = UniChar(scalar.value)
            event.keyboardSetUnicodeString(stringLength: 1, unicodeString: &char)
            event.post(tap: .cghidEventTap)

            // Key up
            guard let upEvent = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: false) else {
                continue
            }
            upEvent.keyboardSetUnicodeString(stringLength: 1, unicodeString: &char)
            upEvent.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Common Shortcuts

    /// Send Cmd+C (Copy).
    public func copy() {
        keyPress(keyCode: KeyCode.c, modifiers: .maskCommand)
    }

    /// Send Cmd+V (Paste).
    public func paste() {
        keyPress(keyCode: KeyCode.v, modifiers: .maskCommand)
    }

    /// Send Cmd+Z (Undo).
    public func undo() {
        keyPress(keyCode: KeyCode.z, modifiers: .maskCommand)
    }

    /// Send Cmd+Space (Spotlight).
    public func spotlight() {
        keyPress(keyCode: KeyCode.space, modifiers: .maskCommand)
    }

    /// Send Escape.
    public func escape() {
        keyPress(keyCode: KeyCode.escape)
    }

    /// Send Return/Enter.
    public func returnKey() {
        keyPress(keyCode: KeyCode.returnKey)
    }

    // MARK: - Process InputEvent

    /// Process a keyboard InputEvent from the iPhone.
    ///
    /// - Parameter event: The input event to execute.
    public func processEvent(_ inputEvent: InputEvent) {
        guard let keyCode = inputEvent.data.keyCode else { return }

        if let mediaKey = MediaKeyType.fromVirtualKeyCode(keyCode) {
            let isDown = inputEvent.type == .keyDown
            postMediaKey(mediaKey, isDown: isDown)
            return
        }

        let flags = modifierFlags(from: inputEvent.data.modifiers)

        switch inputEvent.type {
        case .keyDown:
            keyDown(keyCode: keyCode, modifiers: flags)
        case .keyUp:
            keyUp(keyCode: keyCode, modifiers: flags)
        default:
            break
        }
    }

    /// Convert raw modifier bits to CGEventFlags.
    private func modifierFlags(from raw: UInt?) -> CGEventFlags {
        guard let raw = raw else { return [] }
        return CGEventFlags(rawValue: UInt64(raw))
    }

    private func postMediaKey(_ mediaKey: MediaKeyType, isDown: Bool) {
        let flags = NSEvent.ModifierFlags(rawValue: 0xA00)
        let data1 = Int((mediaKey.rawValue << 16) | (Int32(isDown ? 0xA : 0xB) << 8))
        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        ) else {
            return
        }

        event.cgEvent?.post(tap: .cghidEventTap)
    }
}

private enum MediaKeyType: Int32 {
    case volumeUp = 0
    case volumeDown = 1
    case mute = 7
    case playPause = 16
    case nextTrack = 17
    case previousTrack = 18

    static func fromVirtualKeyCode(_ keyCode: UInt16) -> MediaKeyType? {
        switch keyCode {
        case 0x64: return .playPause
        case 0x65: return .nextTrack
        case 0x62: return .previousTrack
        case 0x48: return .volumeUp
        case 0x49: return .volumeDown
        case 0x4A: return .mute
        default: return nil
        }
    }
}

// MARK: - Key Codes

/// Common macOS virtual key codes.
public enum KeyCode {
    public static let a: UInt16 = 0x00
    public static let s: UInt16 = 0x01
    public static let d: UInt16 = 0x02
    public static let f: UInt16 = 0x03
    public static let h: UInt16 = 0x04
    public static let g: UInt16 = 0x05
    public static let z: UInt16 = 0x06
    public static let x: UInt16 = 0x07
    public static let c: UInt16 = 0x08
    public static let v: UInt16 = 0x09
    public static let b: UInt16 = 0x0B
    public static let q: UInt16 = 0x0C
    public static let w: UInt16 = 0x0D
    public static let e: UInt16 = 0x0E
    public static let r: UInt16 = 0x0F
    public static let y: UInt16 = 0x10
    public static let t: UInt16 = 0x11
    public static let o: UInt16 = 0x13
    public static let u: UInt16 = 0x14
    public static let i: UInt16 = 0x22
    public static let p: UInt16 = 0x23
    public static let l: UInt16 = 0x25
    public static let j: UInt16 = 0x26
    public static let k: UInt16 = 0x28
    public static let n: UInt16 = 0x2D
    public static let m: UInt16 = 0x2E

    public static let returnKey: UInt16 = 0x24
    public static let tab: UInt16 = 0x30
    public static let space: UInt16 = 0x31
    public static let delete: UInt16 = 0x33
    public static let escape: UInt16 = 0x35

    public static let leftArrow: UInt16 = 0x7B
    public static let rightArrow: UInt16 = 0x7C
    public static let downArrow: UInt16 = 0x7D
    public static let upArrow: UInt16 = 0x7E

    public static let f1: UInt16 = 0x7A
    public static let f2: UInt16 = 0x78
    public static let f3: UInt16 = 0x63
    public static let f4: UInt16 = 0x76
    public static let f5: UInt16 = 0x60
}
