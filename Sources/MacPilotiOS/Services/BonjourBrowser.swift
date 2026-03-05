// BonjourBrowser.swift
// MacPilot — MacPilot-iOS / Services
//
// Discovers MacPilotAgent on the local network using Bonjour (mDNS).
// Browses for _macpilot._tcp services and resolves endpoints.

import Foundation
import Network
import Combine
import SharedCore

// MARK: - DiscoveredMac

/// Represents a Mac discovered via Bonjour.
public struct DiscoveredMac: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let endpoint: NWEndpoint

    public init(name: String, endpoint: NWEndpoint) {
        self.id = name
        self.name = name
        self.endpoint = endpoint
    }
}

// MARK: - BonjourBrowser

/// Discovers MacPilotAgent instances on the local network via Bonjour.
///
/// Usage:
/// ```swift
/// let browser = BonjourBrowser()
/// browser.startBrowsing()
/// // Observe browser.discoveredMacs for results
/// ```
@MainActor
public final class BonjourBrowser: ObservableObject {

    // MARK: - Published State

    /// List of discovered Mac instances on the network.
    @Published public private(set) var discoveredMacs: [DiscoveredMac] = []

    /// Whether the browser is actively scanning.
    @Published public private(set) var isBrowsing: Bool = false

    // MARK: - Properties

    private var browser: NWBrowser?
    private let queue = DispatchQueue(label: "com.macpilot.bonjour", qos: .userInitiated)

    // MARK: - Init

    public init() {}

    // MARK: - Browse

    /// Start browsing for MacPilot services on the local network.
    public func startBrowsing() {
        guard !isBrowsing else { return }

        let descriptor = NWBrowser.Descriptor.bonjour(
            type: NetworkConstants.bonjourServiceType,
            domain: NetworkConstants.bonjourDomain
        )

        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        let nwBrowser = NWBrowser(for: descriptor, using: parameters)
        self.browser = nwBrowser

        nwBrowser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                self?.handleBrowserState(state)
            }
        }

        nwBrowser.browseResultsChangedHandler = { [weak self] results, changes in
            Task { @MainActor [weak self] in
                self?.handleResultsChanged(results, changes: changes)
            }
        }

        nwBrowser.start(queue: queue)
        isBrowsing = true

        print("[MacPilot][Bonjour] Started browsing for \(NetworkConstants.bonjourServiceType)...")
    }

    /// Stop browsing.
    public func stopBrowsing() {
        browser?.cancel()
        browser = nil
        isBrowsing = false
        discoveredMacs = []
        print("[MacPilot][Bonjour] Stopped browsing")
    }

    // MARK: - Handlers

    private func handleBrowserState(_ state: NWBrowser.State) {
        switch state {
        case .ready:
            print("[MacPilot][Bonjour] Browser ready")
        case .failed(let error):
            print("[MacPilot][Bonjour] Browser failed: \(error.localizedDescription)")
            isBrowsing = false
            // Retry after a delay
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s
                startBrowsing()
            }
        case .cancelled:
            isBrowsing = false
        default:
            break
        }
    }

    private func handleResultsChanged(
        _ results: Set<NWBrowser.Result>,
        changes: Set<NWBrowser.Result.Change>
    ) {
        var macs: [DiscoveredMac] = []

        for result in results {
            switch result.endpoint {
            case .service(let name, let type, let domain, _):
                let mac = DiscoveredMac(
                    name: name,
                    endpoint: result.endpoint
                )
                macs.append(mac)
                print("[MacPilot][Bonjour] Found: \(name) (\(type)\(domain))")
            default:
                break
            }
        }

        discoveredMacs = macs
    }
}
