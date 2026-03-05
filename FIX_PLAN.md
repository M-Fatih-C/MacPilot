# MacPilot Fix Plan

## Goal
Stabilize architecture, close critical security gaps, and ship a production-ready local-network remote control stack.

## Priority 0 (Critical Security and Trust)
1. Enforce TLS certificate pinning on iOS verify block (`MacConnection`).
2. Implement full auth handshake path (challenge-sign-verify) before marking connection as `connected`.
3. Enable ephemeral key exchange and switch runtime message flow from plaintext to encrypted envelope.
4. Add server-side message gate: reject control/command/file messages before auth + session key establishment.

### P0 Acceptance Criteria
- Client cannot connect with mismatched certificate fingerprint.
- Unauthenticated messages are rejected server-side.
- Input/command/file payloads are encrypted in transit (application layer).

## Priority 1 (Core Functionality Completion)
1. Implement agent message router in `main.swift` for:
   - input events
   - metrics requests
   - command requests
   - file browse/download/upload
2. Wire iOS inbound message dispatcher to:
   - `DashboardViewModel.handleMetricsResponse`
   - `FileViewModel.handleBrowseResponse`
   - `FileTransferService.handleDownloadChunk`
3. Complete `DaemonInstaller` install/uninstall/running checks.
4. Complete file upload picker flow in `FileBrowserView` and bind to `FileTransferService`.

### P1 Acceptance Criteria
- Dashboard metrics update from real agent responses.
- File browser and transfers work end-to-end.
- Daemon installation is controllable from helper app.

## Priority 2 (Reliability and Quality)
1. Fix shortcut/media key event lifecycle (keyDown + keyUp where required).
2. Improve network restriction behavior for valid local interfaces (Wi-Fi/Ethernet) while preserving local-only policy.
3. Add integration tests for handshake + encrypted message pipeline.
4. Add iOS signing profile/team setup documentation.

### P2 Acceptance Criteria
- No stuck key states during shortcut usage.
- Local interface policy is deterministic and test-covered.
- CI can validate tests/build for publishable targets.

## Suggested Execution Order
1. P0 first and block merge until complete.
2. P1 second to restore complete product behavior.
3. P2 hardening before release candidate tag.
