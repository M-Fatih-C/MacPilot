# MacPilot

![MacPilot Logo](Docs/Branding/logo.png)

MacPilot is a multi-target Apple project for local-network Mac remote control and monitoring.

## Modules
- `SharedCore`: Shared models and networking abstractions for iOS + macOS targets.
- `MacPilotAgent`: macOS daemon target that hosts the control server.
- `MacPilotHelper`: macOS setup/onboarding app.
- `MacPilot-iOS`: iPhone client app (trackpad, dashboard, shortcuts, files).
- `MacPilotTests`: unit/performance tests for core behaviors.

## Current Project Status
- macOS targets (`MacPilotAgent`, `MacPilotHelper`) build successfully.
- `MacPilotTests` pass in local run.
- iOS target requires signing/team configuration before device/archive builds.

## Public Repository Scope
This public repository intentionally excludes private security protocol documentation.
Implementation evolves in phased milestones under [FIX_PLAN.md](FIX_PLAN.md).

## Quick Start
```bash
# Run tests
xcodebuild test -project MacPilot.xcodeproj -scheme MacPilotTests -destination 'platform=macOS'

# Build macOS targets
xcodebuild build -project MacPilot.xcodeproj -scheme MacPilotAgent -destination 'platform=macOS'
xcodebuild build -project MacPilot.xcodeproj -scheme MacPilotHelper -destination 'platform=macOS'
```

## License
TBD
