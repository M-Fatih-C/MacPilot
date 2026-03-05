# MacPilot Public Architecture

## High-Level
MacPilot is a local-network remote control system:
- iOS client app discovers Mac target on LAN.
- macOS agent receives commands and returns status/metrics.
- shared core module defines message models and cross-platform contracts.

## Targets
- `SharedCore` (iOS + macOS framework)
- `MacPilotAgent` (macOS daemon)
- `MacPilotHelper` (macOS setup app)
- `MacPilot-iOS` (iPhone app)
- `MacPilotTests` (unit/perf tests)

## Runtime Flow (Public View)
1. Device discovery
2. Connection establishment
3. Bidirectional messaging for control + telemetry
4. File operations and command execution via explicit request/response models

## Notes
Detailed private security protocol documentation is intentionally excluded from the public repository.
