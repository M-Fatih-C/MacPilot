// main.swift
// MacPilot — MacPilotAgent (macOS Daemon)
//
// Entry point for the MacPilotAgent launchd daemon.
// Starts the WebSocket server and keeps the process alive.

import Foundation
import SharedCore

// MARK: - Main

let server = WebSocketServer()

server.onClientConnected = { client in
    log("Main", "iPhone connected: \(client.id)")
}

server.onClientDisconnected = {
    log("Main", "iPhone disconnected")
}

server.onMessageReceived = { data, client in
    log("Main", "Received \(data.count) bytes")
    // TODO: Route messages through AuthManager and dispatch to handlers
}

do {
    log("Main", "MacPilotAgent v\(SharedCore.version) starting...")
    try server.start()
    log("Main", "WebSocket server running on port \(NetworkConstants.port)")
} catch {
    log("Main", "Failed to start server: \(error.localizedDescription)")
    exit(1)
}

// Keep the daemon alive
RunLoop.current.run()
