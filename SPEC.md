# QuickNotes — Product Spec

## Overview
QuickNotes is a macOS menu bar app for quick, disposable plain-text notes — the sticky-note-on-your-monitor experience without the clutter. One click gives you a list of notes and the selected note's content; everything is stored locally with no accounts, no sync, and no network calls beyond an optional GitHub-release version check.

## Core Requirements
- Note icon in the menu bar; click to open/close the popover
- No Dock icon (`LSUIElement = YES`)
- Fully local — no network calls except the optional update check
- Global hotkey ⌥N (toggleable in Settings, on by default)

## Window / Layout
- Popover size: 640 × 480 pt
- Popover behavior: **`.applicationDefined`**, not `.transient` — see Design Decisions below
- Left panel (200–300 pt): toolbar (New, Paste as New Note, Settings gear) + search field + note list
- Right panel (min 340 pt): note detail — header bar + editor
- Settings sheet: 360 pt wide, height sizes to content

---

## Feature List

### Menu Bar
- Status item icon: SF Symbol `note.text`
- Left-click toggles the popover
- Right-click shows a context menu: **Paste Clipboard as New Note**, About QuickNotes, Quit QuickNotes
- ⌥N global hotkey via Carbon (`HotkeyManager.swift`, ported from QuickCal), toggle lives in Settings

### Note List
- Sort order: pinned notes first, then by `modifiedAt` descending
- A note's title is always its first line (or, if locked, a 🔒/🔓 label — see Locking)
- Relative timestamp ("Just now", "12 min. ago"), minute granularity, refreshes on a `TimelineView(.periodic(by: 60))` — deliberately not per-second
- Toolbar: **New Note** (⌘N, also focuses the editor), **Paste Clipboard as New Note**, **Settings**
- Search field with a one-click **×** to clear; filters by title (locked notes) or content (unlocked notes)
- Right-click a row: Lock…/Unlock…, Pin/Unpin, **Label** submenu (six colors — red is a plain color, *not* a "sort to top" special case, see below), Delete
- A small pin glyph (leading, before the title) marks pinned notes; a colored dot marks labeled notes
- Deleting the selected note re-selects the first note from the **currently visible (filtered)** list — not the unfiltered list, which used to leave the list looking empty while a hidden note sat open in the detail pane

### Note Detail
- Header: formatted modified date/time (scales with the font-size setting), Copy, a lock button whose icon/action depends on state (`lock` → `lock.fill` → `lock.open.fill`), Delete (confirmation dialog)
- Editor: `LinkAwareTextEditor` — a custom `NSViewRepresentable` wrapping `NSTextView` in `NSScrollView`, standing in for SwiftUI's plain `TextEditor`
  - URLs/mailto detected via `NSDataDetector`; absolute file paths detected line-by-line (a path can contain spaces, so it's matched as "the whole trimmed line, if it starts with `/`" rather than token-by-token)
  - Click opens a link directly — AppKit's default behavior for `.link`-attributed ranges in an editable `NSTextView`, **no modifier key required** (a doc comment claiming "Cmd-click" shipped briefly and was wrong; verify framework behavior against reality, not memory)
  - `DroppableTextView` subclass accepts a dropped file/folder from Finder and inserts its path as its own line at the drop point
- A newly created or newly selected note auto-focuses the editor via a one-shot `Binding<Bool>` — see Design Decisions for why it must be one-shot, not sticky

### Locking (Encryption)
- Per-note AES-GCM encryption; key derived with PBKDF2 (200k iterations, per-note random salt) from a passcode typed at lock time (`LockManager.swift`)
- Nothing password-derived is stored anywhere by default — a wrong passcode just fails GCM's authentication check, there's no separate verifier to leak
- The lock sheet shows two warnings: no passcode recovery exists, and linked files inside the note are *not* themselves encrypted, only the note's text
- The most recently used passcode is remembered for the rest of the session (pre-fills future lock/unlock sheets) and forgotten when the popover closes
- Optional Touch ID: a note's passcode is saved to the Keychain (`KeychainStore.swift`) after locking; unlocking gates *reading* it back behind a Touch ID prompt (`BiometricAuth.swift`, `LocalAuthentication`) — the typed passcode still works as a fallback
- Auto re-lock delay is configurable: Immediate / 2 / 5 / 10 min / Until app quits — backed by a real per-note `Timer`; editing a locked note while it's unlocked pushes its timer back out
- Optional first-line title preview while locked (off by default): a snapshot is captured at lock time and shown only if the setting is on *at display time* (not lock time), so toggling the setting affects existing locked notes immediately — but a note locked before this ever existed has no snapshot until you unlock-and-relock it once, which also backfills it

### Settings
| Setting | Default |
|---|---|
| Launch at Login | Off |
| Open QuickNotes with ⌥N from anywhere | On |
| Note Text Size | Medium *(Small / Medium / Large)* |
| Show Note Preview While Locked | Off |
| Auto Re-lock Unlocked Notes | Immediate *(2 / 5 / 10 min / Until app quits)* |
| Unlock Notes with Touch ID | Off *(only shown if Touch ID hardware is present)* |
| Check for New Versions | On |

Also in Settings: a "?" button opens a Keyboard Shortcuts sheet (wording adapts if the global hotkey is off); "Show Notes in Finder…"; version number + a link to bernacki.me.

### Update Check
On launch, if enabled, hits `api.github.com/repos/BrianB-22/quicknotes/releases/latest`, compares semver to `CFBundleShortVersionString`, and — if newer — just opens that release page in the browser. No in-app download or install flow; the user decides there.

---

## Storage
- One JSON file per note in `~/Library/Application Support/QuickNotes/<uuid>.json`
- No sync, no accounts, no analytics, no network calls except the optional update check above
- `Note` fields: `id`, `createdAt`, `modifiedAt`, `isPinned`, `isLocked`, `colorLabel`, `plainText` (nil while locked), `encryptedPayload` (nil while unlocked), `lockedTitleSnapshot`

## Architecture
| File | Role |
|---|---|
| `QuickNotesApp.swift` | `@main` entry, `@NSApplicationDelegateAdaptor` |
| `AppDelegate.swift` | `NSStatusItem`, `NSPopover`, global-hotkey wiring, launch-time update check |
| `ContentView.swift` | Root `HSplitView` — list + detail, hosts the Settings sheet |
| `NoteListView.swift` | Toolbar, search, `List`, `NoteRow`, `PasscodeSheet` |
| `NoteDetailView.swift` | Header, lock-button state machine, delete confirmation, editor host |
| `LinkAwareTextEditor.swift` | Custom `NSViewRepresentable` editor — link detection, file drop |
| `Note.swift` | `Note` model, `NoteColorLabel` enum |
| `NoteStore.swift` | `ObservableObject` — CRUD, persistence, sort order, lock/unlock/relock timers |
| `LockManager.swift` | AES-GCM encrypt/decrypt, PBKDF2 key derivation |
| `KeychainStore.swift` | Per-note passcode storage in the Keychain |
| `BiometricAuth.swift` | `LocalAuthentication` (Touch ID) wrapper |
| `HotkeyManager.swift` | Carbon global-hotkey wrapper (ported from QuickCal) |
| `ReliableHelp.swift` | AppKit-backed tooltip — SwiftUI's `.help()` is unreliable on icon buttons hosted in an `NSPopover` |
| `SettingsStore.swift` | `ObservableObject` — `UserDefaults`-backed settings, update-check logic |
| `SettingsView.swift` | Settings sheet, `KeyboardShortcutsView` |

---

## Design Decisions & Gotchas
Notes for whoever (human or Claude) touches this code next — each of these was a real bug found the hard way, not a hypothetical.

- **Popover uses `.applicationDefined`, not `.transient`, + a global `NSEvent` mouseUp monitor for outside-click dismissal.** A plain `.transient` popover closes the instant you mouseDown in Finder to start dragging a file — before the drag ever reaches the popover — which made drag-and-drop into a note impossible. The monitor only fires for events on *other* apps' windows, so a drop that lands back inside our own popover never triggers a close.
- **The note list re-sorts only when you switch away from a note, not on every keystroke.** `updateText` used to call `resort()` on every character typed, which re-mutated and re-diffed the whole `notes` array continuously while typing — strongly suspected as the cause of clicks on other rows occasionally being swallowed. Sort now happens once, in `selectedNoteID`'s `didSet`.
- **`NSViewRepresentable.Coordinator.parent` must be reassigned in `updateNSView` on every call.** `LinkAwareTextEditor` is a struct; without `context.coordinator.parent = self`, the long-lived `Coordinator` keeps writing edits back through whichever `text` binding existed the first time it was created — i.e., notes silently stopped saving once you switched away from the first note you'd opened. This actually shipped before being caught.
- **`shouldFocus` must be a one-shot `Binding<Bool>`, reset immediately after use, not a value that stays `true`.** A sticky "should focus" flag re-attempted `makeFirstResponder` on every re-render (including every keystroke), which could fight the user's own clicks and intermittently block typing.
- **Red is not a "star" that sorts notes to the top.** This was tried (`NoteColorLabel.sortsToTop`) and explicitly reverted — pinning is the only thing that sorts a note to the top. Don't reintroduce it without being asked.
- **Local-only is a deliberate choice, not a missing feature.** iCloud/CloudKit sync was discussed and intentionally deferred to keep the "no cloud, no accounts" pitch intact. If sync ever comes up again: iCloud Drive (point the storage folder at the app's ubiquity container) is the cheap option with coarse conflict handling; CloudKit is the robust option but means replacing the flat-JSON persistence layer entirely.
- **This dev machine has Xcode.app but the sandboxed shell's `xcode-select` still points at Command Line Tools**, so `xcodebuild` isn't usable from an assistant's Bash tool here even after running `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` in a real terminal — building/running has to happen through the Xcode GUI, and `plutil -lint` on `project.pbxproj` is the extent of what can be verified headlessly.

## Release Process
1. Xcode → Product → Archive (destination must be **My Mac**, not "Any Mac")
2. Organizer → Distribute App → Direct Distribution (signs with the Developer ID Application certificate, submits for notarization automatically)
3. Export the notarized `.app` once notarization completes
4. Stage it with an `Applications` symlink and build a DMG:
   ```
   hdiutil create -volname "QuickNotes" -srcfolder <staging-dir> -ov -format UDZO QuickNotes_vX.X.dmg
   ```
5. `gh release create <tag> <dmg-path> --title "QuickNotes vX.X" --notes "..."` (or `gh release upload --clobber` to replace an existing release's asset)

Repo: [github.com/BrianB-22/quicknotes](https://github.com/BrianB-22/quicknotes) · Sibling project / style template: [github.com/BrianB-22/quickcal](https://github.com/BrianB-22/quickcal)
