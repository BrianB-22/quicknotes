# Security Overview

QuickNotes is a small, single-developer macOS menu bar app. This document exists so it can be independently verified — everything below is checkable against the actual source in this repository, not just asserted.

## No external dependencies

Zero third-party libraries, SDKs, or Swift Packages. Verifiable directly: `QuickNotes.xcodeproj/project.pbxproj` contains no `XCRemoteSwiftPackageReference` or `PBXPackageProductDependency` entries — grep for either and the result is empty. Everything is built against Apple's own frameworks (SwiftUI, AppKit, Carbon, LocalAuthentication, Security, CryptoKit-equivalent via `CommonCrypto`).

No analytics SDK, no crash reporter, no telemetry framework of any kind.

## Network activity — exactly one endpoint, one purpose

The entire codebase makes **one** outbound network call, from `SettingsStore.checkForUpdates()`:

```
GET https://api.github.com/repos/BrianB-22/quicknotes/releases/latest
```

- Fires once, on app launch, only if "Check for new versions" is enabled in Settings (on by default, toggleable off)
- No request body, no query parameters, no auth token, no identifying headers beyond what `URLSession` sends by default
- Reads public release metadata only (tag name, release URL) — nothing about the user, the device, or note content is ever sent
- If a newer version is found, it shows a native confirmation dialog and only opens the browser if the user clicks "Download" — never automatic
- Every other `URL` reference in the codebase is a **user-initiated** link click inside a note (opens in the default browser, standard `NSWorkspace.open`) — not something the app calls out to on its own

This is the app's only network behavior. Disabling the setting makes the app fully offline.

## Data storage & privacy

- Notes are stored as individual plain-text JSON files in `~/Library/Application Support/QuickNotes/` — no database, no cloud sync, no account/login of any kind
- No iCloud, no Dropbox, no third-party storage integration
- "Show Notes in Finder…" in Settings opens that folder directly, so the storage format and location are fully transparent to the user

## Per-note encryption (optional, opt-in per note)

- AES-GCM authenticated encryption, key derived via PBKDF2 (200,000 iterations, unique random salt per note) from a user-chosen passcode
- Nothing password-derived is stored anywhere by default — a wrong passcode simply fails GCM's built-in authentication check; there is no separate verifier/hash to compromise
- Implementation: `LockManager.swift`

## Entitlements & sandboxing

- **The app is not sandboxed** (no `com.apple.security.app-sandbox` entitlement). Disclosed plainly rather than glossed over — since the source is public, this is verifiable either way, so there's nothing gained by hiding it.
- The **only** entitlement requested is `keychain-access-groups`, required to scope the app's own Keychain storage (used for an optional, currently-disabled-in-UI Touch ID convenience feature). It does not grant access to any other app's Keychain items.
- No camera, microphone, contacts, calendar, location, or other sensitive-resource entitlements of any kind.

## Code signing & notarization

Every released build is signed with a Developer ID Application certificate and notarized by Apple — meaning Apple's own automated malware/security scan has vetted each release binary before it's distributed. Verify any downloaded build yourself:

```
codesign -dv --verbose=4 QuickNotes.app
spctl -a -vv QuickNotes.app
```

## Full source availability

This repository is public. Every line of code that ships in a release is here to read — nothing closed-source, nothing obfuscated. The `Building from Source` section in `README.md` covers building it directly from source if you'd rather not trust a pre-built binary at all.

## Reporting a concern

This is a personal, unpaid side project — there's no formal disclosure program, but [private vulnerability reporting](https://github.com/BrianB-22/quicknotes/security/advisories/new) is enabled on this repository for anything that shouldn't be filed as a public issue. For anything else, open a regular issue, or reach out via [bernacki.me](https://bernacki.me).
