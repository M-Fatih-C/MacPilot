# MacPilot Smoke Test Report

- Date: 2026-03-06 02:43:19 +03
- Scope: End-to-end runtime verification against local `MacPilotAgent` over `wss://127.0.0.1:8443`
- Runner: `/tmp/macpilot_smoke_probe.swift` (compiled with `swiftc -parse-as-library`)

## Checks

| Check | Result | Details |
|---|---|---|
| iOS connection | PASS | Received `authChallenge` from server device `6DE5455D-ED55-3D1D-2ADC-DAD5CC79ED4D` |
| authentication handshake | PASS | Mutual signature verification passed |
| metrics pipeline | PASS | CPU `7.91%`, RAM `13166280704/17179869184` |
| input events | PASS | `mouseMove` accepted, connection remained alive (`ping/pong`) |
| command execution | PASS | Response received; `success=false`, output: `runScript is disabled in this build.` |
| file browsing | PASS | `fileBrowseResponse` for `~`, item count `9` |

## Summary

- Total checks: 6
- Failures: 0
- Smoke status: PASS

## Build And Launch Validation

- `xcodebuild -project MacPilot.xcodeproj -scheme MacPilot-iOS -configuration Debug -destination 'generic/platform=iOS Simulator' build`: `BUILD SUCCEEDED`
- Simulator launch check: `xcrun simctl launch booted com.macpilot.MacPilotiOS` returned PID and app process was terminable via `xcrun simctl terminate`, confirming launch success.

## Raw Probe Output

```text
SMOKE|iOS_connection|PASS|Received authChallenge from 6DE5455D-ED55-3D1D-2ADC-DAD5CC79ED4D
SMOKE|authentication_handshake|PASS|Mutual signature verification passed
SMOKE|metrics_pipeline|PASS|CPU=7.91 RAM=13166280704/17179869184
SMOKE|input_events|PASS|Input event accepted, connection remained alive
SMOKE|command_execution|PASS|success=false output=runScript is disabled in this build.
SMOKE|file_browsing|PASS|path=~ count=9
SMOKE_SUMMARY|total=6|failed=0
```

## Notes

- Command execution channel is operational, but script execution itself is intentionally disabled in current build (`runScript is disabled in this build.`).
- iOS-to-agent connectivity in this report is validated at protocol level using the smoke probe client; simulator app auto-connect was not observed without manual in-app interaction/configuration.
