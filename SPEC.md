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
- Right-click a row: Lock…/Unlock…, **Remove Lock…** (locked notes only — permanently decrypts and converts back to a plain note; see Locking), **Version History…** (plain notes only — see Version History below), Pin/Unpin, **Label** submenu (six colors — red is a plain color, *not* a "sort to top" special case, see below), Delete (confirms before deleting, same dialog as the detail-pane trash button — see Delete below)
- A small pin glyph (leading, before the title) marks pinned notes; a colored dot marks labeled notes
- Deleting the selected note re-selects the first note from the **currently visible (filtered)** list — not the unfiltered list, which used to leave the list looking empty while a hidden note sat open in the detail pane

### Note Detail
- Header: formatted modified date/time (scales with the font-size setting), Copy, **Save Note As…** (opens a native `NSSavePanel`, writes the current text to the chosen location — `.md` extension/content-type suggested in MD mode, `.txt` otherwise; filename suggested from the note's first line), a lock button whose icon/action depends on state (`lock` → `lock.fill` → `lock.open.fill`), Delete (confirmation dialog)
- Editor: `LinkAwareTextEditor` — a custom `NSViewRepresentable` wrapping `NSTextView` in `NSScrollView`, standing in for SwiftUI's plain `TextEditor`
  - URLs/mailto detected via `NSDataDetector`; absolute file paths detected line-by-line (a path can contain spaces, so it's matched as "the whole trimmed line, if it starts with `/`" rather than token-by-token)
  - Click opens a link directly — AppKit's default behavior for `.link`-attributed ranges in an editable `NSTextView`, **no modifier key required** (a doc comment claiming "Cmd-click" shipped briefly and was wrong; verify framework behavior against reality, not memory)
  - `DroppableTextView` subclass accepts a dropped file/folder from Finder and inserts its path as its own line at the drop point
- A newly created or newly selected note auto-focuses the editor via a one-shot `Binding<Bool>` — see Design Decisions for why it must be one-shot, not sticky
- Bottom bar below the editor: a **TXT/MD** segmented toggle (per-note, persisted — see Storage) and, in Text mode, buttons to insert markdown syntax (Bold, Italic, Code, Heading, Bulleted List, Checklist, Link) at the current selection; in MD mode the buttons are replaced with a "Read-only — checkboxes are tappable" label
  - Insertion uses the same one-shot-binding pattern as editor auto-focus: a button sets a `pendingFormat` value, `LinkAwareTextEditor` consumes and clears it in `updateNSView`
  - MD mode renders mostly read-only via `AttributedString(markdown:, options: .full)`. Three gotchas, all shipped once and fixed: (1) `.full` parsing strips block-boundary newlines and list-marker characters entirely and represents structure only via `presentationIntent` metadata — `MarkdownPreviewView` has to manually reinsert a separator whenever a run's block identity changes and re-add bullet/ordinal markers for list items (skipping this makes every block run together on one line with no markers); (2) that separator has to be a full blank line (`"\n\n"`) between separate blocks, not a bare `"\n"` — a single newline just moves to the next line and still reads cramped compared to Text mode's visible blank row, though consecutive items of the *same* list stay tight with a single `"\n"`; (3) a single Enter *within* a paragraph is a CommonMark "soft break" (renders as a plain space per spec, not a line break — `<br>` or two trailing spaces are needed for a real one) — wrong default for a quick-notes app, so every `.softBreak` inline intent is rendered as an actual `"\n"` instead
  - **Checklists are the one interactive exception**: `- [ ] task` / `- [x] task` lines (and `*` in place of `-`) don't go through the `.full` block parser at all — Foundation's `AttributedString(markdown:)` has no native checklist presentation-intent, so it would otherwise render the literal text "[ ] task" as a bullet item. Instead `MarkdownPreviewView` classifies each source line first: contiguous non-checkbox lines are grouped into a block and rendered as above, and each checkbox line becomes its own row (a tappable `square`/`checkmark.square.fill` button + the item's text, parsed inline-only so bold/links inside it still work, struck through when checked). Since `text` is a `Binding` sourced from the same `textBinding(for:)` used by the Text-mode editor, toggling a checkbox is just a normal edit as far as the rest of the app is concerned — `NoteStore.updateText`/`updateLockedText`, search, and version-history checkpointing all pick it up with no special-casing. Only the checkbox glyph is a tap target, not the row text, so `.textSelection(.enabled)` still lets you select/copy a checklist item's text without toggling it by accident.

### Locking (Encryption)
- Per-note AES-GCM encryption; key derived with PBKDF2 (200k iterations, per-note random salt) from a passcode typed at lock time (`LockManager.swift`)
- Nothing password-derived is stored anywhere by default — a wrong passcode just fails GCM's authentication check, there's no separate verifier to leak
- The lock sheet shows three warnings: no passcode recovery exists, linked files inside the note are *not* themselves encrypted (only the note's text), and locking will lose the note's version history (see Version History)
- The most recently used passcode is remembered for the rest of the session and forgotten when the popover closes — unconditionally, regardless of the auto re-lock delay setting (only the *notes themselves* stay decrypted longer under a longer delay, not the remembered passcode). It only pre-fills an Unlock/Remove Lock sheet if it's actually verified to decrypt *that* note first (a real `LockManager.decrypt` attempt, not just assumed) — different notes can have different passcodes, so blindly reusing the last one used anywhere would confidently show a wrong passcode rather than an empty field

- The key derived at unlock is cached in memory for that viewing session (`NoteStore.sessionKeys`) and reused for every edit; editing a locked note does **not** redo the 200k-iteration PBKDF2 derive per keystroke — only the initial unlock (and a fresh `lock()`) pays that cost
- Touch ID unlock is **shelved as a future feature** — the underlying plumbing (`KeychainStore.swift`'s `SecAccessControl(.biometryCurrentSet)` hardening, the entitlement fix, the background-thread fix) is still in place, but the Settings toggle and "Unlock with Touch ID" button are hidden (`SettingsView.swift`) since it kept throwing errors even after the entitlement fix was confirmed correct. Passcode is the only working unlock method right now. See Design Decisions for the investigation trail if this gets revisited
- **Remove Lock…**: verifies the passcode, then permanently converts a locked note back into a normal plain-text note — clears the encrypted payload, title snapshot, and any saved Keychain entry. Until this existed there was no way back once a note was locked
- Auto re-lock delay is configurable: Immediate / 2 / 5 / 10 min / Until app quits — backed by a real per-note `Timer`, wrapped in a `ProcessInfo` background-activity token so App Nap doesn't defer it while the popover is closed and the app has no visible window; editing a locked note while it's unlocked pushes its timer back out
- Optional first-line title preview while locked (off by default): a snapshot is captured **only when the setting is on**, at lock time, at edit time, and at the relock-backfill step alike — never written to disk otherwise, so there's nothing to leak from a note locked while the setting was off. Shown at display time (not lock time), so toggling the setting affects existing locked notes' *visibility* immediately — but a note locked while the setting was off has no snapshot until you unlock-and-relock it once *with the setting on*, which backfills it

### Version History
- On by default (`SettingsStore.versionHistoryEnabled`). A version is checkpointed when you *leave* a note you've edited — switching to another note, or closing the popover — never per keystroke and never on a timer; it represents "how the note looked before this editing session," not an undo log
- Checkpointing compares the note's current text against a baseline captured when it was selected (`NoteStore.editSessionBaselines`); if unchanged, nothing is saved
- Capped at 30 versions per note (`NoteStore.maxVersionsPerNote`); oldest dropped first past that
- **Excluded entirely for any note that is or has been locked**, with no exception for a temporarily-unlocked-for-viewing session — see Locking above and Design Decisions below for why. `lock()` clears `versionHistory` the moment a note is locked; the context-menu item is hidden whenever `isLocked` is true
- View-only: right-click → **Version History…** opens `VersionHistoryView.swift`, a two-pane timeline (list of past versions newest-first, selected version's full text read-only + Copy to Clipboard). No restore button by design — you copy what you need and paste it back into the note yourself
  - The note's **current** live text is synthesized as an extra row (`VersionHistoryView.HistoryEntry.current`) and always listed first, tagged "(Current)" next to its timestamp — not a real `NoteVersion`, since the current text was never itself checkpointed. Only added when at least one real past version exists (`entries` stays empty and the friendly "No previous versions yet" empty state shows otherwise) — a lone "(Current)" row with nothing to compare it against wouldn't be useful. Selected by default when the sheet opens.
- Search does **not** look inside version history — `filteredNotes` only ever matches a note's current text/title, so content that's only in a past version won't surface from the search field; you have to know which note to check and dig through its history manually (left as-is deliberately, see `PUNCHDOWN.md` §6.11 if this gets revisited)

### Delete
- `NoteStore.delete` moves the note's JSON file to the macOS Trash (`FileManager.trashItem`) rather than removing it outright — recoverable the same way any Finder delete is, no custom in-app trash/undo system needed
- After the delete confirmation, a follow-up alert names the note and its filename (`<uuid>.json`) and points to Settings → **Show Notes in Finder…** as the restore path — copy the file back into the Notes folder from `~/.Trash`
- The note's title is captured *before* calling `delete()`, not after — once deleted it's gone from `noteStore.notes`, so there's nothing left to read a title from

### Settings
| Setting | Default |
|---|---|
| Launch at Login | Off |
| Open QuickNotes with ⌥N from anywhere | On |
| Note Text Size | Medium *(Small / Medium / Large)* |
| Show Note Preview While Locked | Off |
| Auto Re-lock Unlocked Notes | Immediate *(2 / 5 / 10 min / Until app quits)* |
| Keep Version History | On |
| Check for New Versions | On |

*(Touch ID unlock exists in code but its Settings toggle is currently hidden — shelved as a future feature, see Locking above.)*

Also in Settings: a "?" button opens a Keyboard Shortcuts sheet (wording adapts if the global hotkey is off); "Show Notes in Finder…"; version number + a link to bernacki.me.

### Update Check
On launch, if enabled, hits `api.github.com/repos/BrianB-22/quicknotes/releases/latest`, compares semver to `CFBundleShortVersionString`, and — if newer — just opens that release page in the browser. No in-app download or install flow; the user decides there.

---

## Storage
- One JSON file per note in `~/Library/Application Support/QuickNotes/<uuid>.json`
- No sync, no accounts, no analytics, no network calls except the optional update check above
- `Note` fields: `id`, `createdAt`, `modifiedAt`, `isPinned`, `isLocked`, `colorLabel`, `plainText` (nil while locked), `encryptedPayload` (nil while unlocked), `lockedTitleSnapshot`, `previewMode` (Text/MD, optional — nil on notes written before this field existed, treated as Text), `versionHistory` (array of `{text, savedAt}`, optional — nil for locked notes and for plain notes with no history yet; see Version History)

## Architecture
| File | Role |
|---|---|
| `QuickNotesApp.swift` | `@main` entry, `@NSApplicationDelegateAdaptor` |
| `AppDelegate.swift` | `NSStatusItem`, `NSPopover`, global-hotkey wiring, launch-time update check |
| `ContentView.swift` | Root `HSplitView` — list + detail, hosts the Settings sheet |
| `NoteListView.swift` | Toolbar, search, `List`, `NoteRow`, `PasscodeSheet` |
| `NoteDetailView.swift` | Header, lock-button state machine, delete confirmation, editor host |
| `LinkAwareTextEditor.swift` | Custom `NSViewRepresentable` editor — link detection, file drop, markdown-insertion actions |
| `MarkdownPreviewView.swift` | Read-only rendered markdown for MD preview mode |
| `Note.swift` | `Note` model, `NoteColorLabel` enum |
| `NoteStore.swift` | `ObservableObject` — CRUD, persistence, sort order, lock/unlock/relock timers |
| `LockManager.swift` | AES-GCM encrypt/decrypt, PBKDF2 key derivation |
| `KeychainStore.swift` | Per-note passcode storage in the Keychain |
| `BiometricAuth.swift` | `LocalAuthentication` (Touch ID) wrapper |
| `HotkeyManager.swift` | Carbon global-hotkey wrapper (ported from QuickCal) |
| `ReliableHelp.swift` | AppKit-backed tooltip — SwiftUI's `.help()` is unreliable on icon buttons hosted in an `NSPopover` |
| `SettingsStore.swift` | `ObservableObject` — `UserDefaults`-backed settings, update-check logic |
| `QuickNotes.entitlements` | `keychain-access-groups` — required for `SecAccessControl`-protected (Touch ID) Keychain items; see Design Decisions |
| `SettingsView.swift` | Settings sheet, `KeyboardShortcutsView` |
| `VersionHistoryView.swift` | Read-only version-history timeline + copy-to-clipboard for a plain note |

---

## Design Decisions & Gotchas
Notes for whoever (human or Claude) touches this code next — each of these was a real bug found the hard way, not a hypothetical.

- **Popover uses `.applicationDefined`, not `.transient`, + a global `NSEvent` mouseUp monitor for outside-click dismissal.** A plain `.transient` popover closes the instant you mouseDown in Finder to start dragging a file — before the drag ever reaches the popover — which made drag-and-drop into a note impossible. The monitor only fires for events on *other* apps' windows, so a drop that lands back inside our own popover never triggers a close.
- **The note list re-sorts only when you switch away from a note, not on every keystroke.** `updateText` used to call `resort()` on every character typed, which re-mutated and re-diffed the whole `notes` array continuously while typing — strongly suspected as the cause of clicks on other rows occasionally being swallowed. Sort now happens once, in `selectedNoteID`'s `didSet`.
- **`NSViewRepresentable.Coordinator.parent` must be reassigned in `updateNSView` on every call.** `LinkAwareTextEditor` is a struct; without `context.coordinator.parent = self`, the long-lived `Coordinator` keeps writing edits back through whichever `text` binding existed the first time it was created — i.e., notes silently stopped saving once you switched away from the first note you'd opened. This actually shipped before being caught.
- **`shouldFocus` must be a one-shot `Binding<Bool>`, reset immediately after use, not a value that stays `true`.** A sticky "should focus" flag re-attempted `makeFirstResponder` on every re-render (including every keystroke), which could fight the user's own clicks and intermittently block typing.
- **`AttributedString(markdown:options:)` with `.full` syntax drops newlines and list markers from the string itself.** Block structure (paragraph/header/list-item boundaries) is represented only via `presentationIntent` metadata, not literal characters — the first version of `MarkdownPreviewView` rendered every block concatenated on one line with no bullets, because nothing was reinserting separators. Fix: walk `attributed.runs`, insert a `\n` whenever `presentationIntent.components.first?.identity` changes from the previous run, and re-add a bullet/ordinal marker when that block is a `.listItem`.
- **A single Enter within one paragraph parses as a CommonMark "soft break," which Foundation renders as a plain space, not a line break.** This is spec-correct (only two trailing spaces or a backslash count as a "hard" break) but produced a real user-facing bug in `MarkdownPreviewView`: typing several lines with a single Enter between each rendered them all run together, and only an explicit `<br>` (or trailing hard-break markup) produced a visible break. Fix: detect `run.inlinePresentationIntent.contains(.softBreak)` and render it as `"\n"` instead of the space the parser puts there — every typed Enter should read as a new line in a quick-notes app, spec purity aside.
- **A bare `"\n"` between markdown blocks isn't the same as the blank row the user sees in Text mode.** The first fix for the "blocks run together" gotcha above inserted one `"\n"` per block-identity change, which moves to the next line but produces no visual gap — still reads as cramped/squished compared to a real markdown renderer, and compared to what the user's raw text looks like in Text mode. Fix: use `"\n\n"` between separate blocks, but keep consecutive items of the *same* list tight with a single `"\n"` (track whether both the current and previous block are `.listItem`s of one list; only that case gets the tight separator).
- **PBKDF2 at 200k iterations is too slow to redo on every keystroke.** `updateLockedText` used to call `LockManager.encrypt(_:passcode:)` on every character typed, which re-derives the key from scratch each time — tens of ms per call, so typing in a locked note visibly lagged. Fix: derive the key once at `unlock()` and cache it (`NoteStore.sessionKeys`); `updateLockedText` uses a keyed `LockManager.encrypt(_:key:salt:)` overload that skips the derive entirely (~1000x faster in practice, confirmed with a standalone timing probe). Reusing the note's existing salt across saves within one session is safe — AES-GCM's `seal` already generates a fresh internal nonce per call.
- **A `SecAccessControl`-protected Keychain item can't also carry a plain `kSecAttrAccessible` key.** The two are mutually exclusive on one item; setting both when adding the biometry-gated passcode item is a mistake to watch for if this code is touched again.
- **Once a Keychain item requires biometry, checking it *exists* must not read its data.** `KeychainStore.hasPasscode` doesn't call `loadPasscode` — reading the protected value (even to throw it away) triggers the system Touch ID prompt, which would fire just to decide whether to show the "Unlock with Touch ID" button, before the user asked for anything. Existence is checked via a query with no `kSecReturnData`, which only touches metadata.
- **A `SecAccessControl`-protected Keychain item needs a `keychain-access-groups` entitlement, or `SecItemAdd` fails silently with OSStatus -34018 ("A required entitlement isn't present").** The app had no entitlements file at all (`CODE_SIGN_ENTITLEMENTS = ""`) — a valid Team-signed build (not ad-hoc) still isn't enough on its own for biometry-gated items. Confirmed by inspecting the actual built `.app`'s entitlements directly (`codesign -d --entitlements :- QuickNotes.app`, which showed only the default debug `get-task-allow`) and reproducing -34018 with a standalone probe using the same access-control flags. Fix: added `QuickNotes/QuickNotes.entitlements` declaring `keychain-access-groups = [$(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)]`, wired into `CODE_SIGN_ENTITLEMENTS` for both build configs. Without this, `KeychainStore.save()` silently failed every time Touch ID was enabled — no passcode ever actually reached the Keychain, so the "Unlock with Touch ID" button never appeared for any note, no matter how it was locked. Even after this fix, Touch ID kept throwing errors in testing, so it's now shelved (UI hidden) as a future feature rather than shipped — see the Locking section above.
- **`SecItemCopyMatching` against a `SecAccessControl`-protected item is synchronous and blocks the calling thread for as long as the system Touch ID sheet is up.** Calling `KeychainStore.loadPasscode` directly from a SwiftUI button action (main thread) froze the *entire app* — every click stopped registering anywhere, not just in the unlock sheet — reported live and reproduced by relaunching fixing it (consistent with a blocked main thread). Fix: `unlockWithTouchID` dispatches the Keychain read to a background queue and only hops back to `DispatchQueue.main` for the resulting `NoteStore` mutation, since that touches `@Published` state.
- **Don't manually call `BiometricAuth.authenticate` before reading a biometry-gated Keychain item.** Once the item's own `SecAccessControl` requires Touch ID, `SecItemCopyMatching` triggers the OS prompt itself as part of the read. Also calling the app's own `LAContext` check first shows two Touch ID prompts back to back.
- **`Timer` doesn't drift across system sleep — App Nap is the real background-timer risk, not sleep.** An earlier note here claimed relock timers "don't survive sleep." That's not accurate: `Timer`'s fire date is wall-clock (`Date`) based, so an overdue timer fires promptly on wake, no drift. The real, well-documented risk for an `LSUIElement` app that rarely has a visible window is **App Nap** deferring background timers while idle-and-unseen. Fix: bracket each scheduled relock timer with a `ProcessInfo.processInfo.beginActivity`/`endActivity` token (`NoteStore.relockActivities`).
- **Any new `Note` field must be `Optional`.** `NoteStore.loadAll()` calls `JSONDecoder().decode(Note.self, from:)` directly with no custom `init(from:)`; a non-optional field with no key in an already-written note's JSON file throws, and `compactMap` in `loadAll()` silently drops that note entirely. `previewMode`, `lockedTitleSnapshot`, and `versionHistory` are all `Optional` for exactly this reason — treat `nil` as the pre-feature default in a computed property instead.
- **Version history is excluded for locked notes on purpose, no exceptions.** It stores full plaintext copies of a note's past text inline in its own JSON file with no extra encryption — reasonable for a plain note, but if it were allowed during even a temporary unlocked-for-viewing session, the file would end up holding a plaintext history sitting right next to the encrypted payload, undermining the entire point of locking that note. This is the same class of bug as the locked-title-snapshot leak (§2.1 in `PUNCHDOWN.md`), applied consistently: `lock()` clears `versionHistory` the moment a note is locked, `checkpointVersion` guards on `!isLocked`, and the context-menu item is hidden whenever `isLocked` is true. If this note's history feels important enough to keep, "Remove Lock…" is the way to get versioning back — permanently decrypt it, and it starts accumulating history again from that point forward.
- **Red is not a "star" that sorts notes to the top.** This was tried (`NoteColorLabel.sortsToTop`) and explicitly reverted — pinning is the only thing that sorts a note to the top. Don't reintroduce it without being asked.
- **Local-only is a deliberate choice, not a missing feature.** iCloud/CloudKit sync was discussed and intentionally deferred to keep the "no cloud, no accounts" pitch intact. If sync ever comes up again: iCloud Drive (point the storage folder at the app's ubiquity container) is the cheap option with coarse conflict handling; CloudKit is the robust option but means replacing the flat-JSON persistence layer entirely.
- **Checklist detection doesn't track fenced-code-block (` ``` `) state across lines.** `MarkdownPreviewView`'s checkbox parser looks at each source line in isolation, so a literal `- [ ] example` written *inside* a ``` code block would still render as a live, tappable checkbox rather than plain code text. Known limitation, not a bug that's been missed — full block-state tracking felt like too much machinery for a personal quick-notes app; revisit only if it actually bites.
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
