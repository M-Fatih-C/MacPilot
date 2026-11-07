# MacPilot

A native Swift prototype for controlling a Mac from an iPhone: trackpad/keyboard
input, system metrics, shortcuts and chunked file transfer. This repository is
an iOS client, a macOS agent and a shared protocol library.

## Architecture

- `Sources/SharedCore/`: message envelopes, payloads, CryptoKit and Keychain helpers.
- `Sources/MacPilotAgent/`: WSS server, authentication/router, input events,
  system metrics, command allowlist and file-transfer handling.
- `Sources/MacPilotiOS/`: SwiftUI screens, connection/discovery and gesture logic.
- `Sources/MacPilotHelper/`: setup/permission UI, with unfinished installer pieces.
- `Tests/MacPilotTests/`: protocol, crypto, handshake, transfer and encoding tests.

Bonjour advertises `_macpilot._tcp`; the default port is 8443. Transport uses
Network.framework WSS with TLS. The current router uses plaintext **application
envelopes inside WSS**; the separate AES-GCM envelope implementation is not
mandatory in the active router. Do not describe this as fully deployed extra
application-layer encryption.

## Build

Use macOS with Xcode; project targets require macOS 14 / iOS 17 or later.
Open `MacPilot.xcodeproj` and select `MacPilotAgent`, `MacPilotHelper` or
`MacPilot-iOS`. `project.yml` is the XcodeGen source if regenerating the project.
Device builds need your own signing configuration. A local agent needs the
appropriate Accessibility/network/file permissions for the actions you enable.

```bash
xcodebuild -project MacPilot.xcodeproj -scheme MacPilotTests \
  -destination 'platform=macOS' \
  -only-testing:MacPilotTests/NetworkingTests \
  -only-testing:MacPilotTests/FileTransferTests \
  -only-testing:MacPilotTests/InputLatencyTests \
  CODE_SIGNING_ALLOWED=NO test
```

The audit passed those 38 selected tests. Other crypto/certificate tests use
Keychain singletons and were not run against the user's identity store. Physical
iPhone–Mac connectivity, permissions, file transfer and destructive commands were
not exercised. See [Turkish technical reference](README.tr.md),
[architecture](ARCHITECTURE_PUBLIC.md) and the historical
[smoke-test notes](Docs/SMOKE_TEST_2026-03-06.md).

## Security and status

This is a prototype for a controlled local network. Certificate pinning and P256
challenge signatures exist, but first-contact trust currently bootstraps an
unknown peer rather than requiring an explicit operator pairing approval.
Treat first pairing as an unresolved authorization boundary; do not expose the
agent on an untrusted network. A production pairing redesign needs separate review.

The command channel is allowlisted; `runScript` is disabled in this build and
destructive power commands additionally require `MACPILOT_ALLOW_DESTRUCTIVE=1`.
Input/file access is still powerful. Share only synthetic demonstrations and
avoid publishing device identities, paths or personal file listings.


## License and contact

No license file is currently included; no new license or redistribution grant is asserted here. Author: [Muhammet Fatih Çetintaş](https://github.com/M-Fatih-C).
