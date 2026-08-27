# QuickNotes — Code Review Punchdown

Full review of all 16 Swift sources + project config, 2026-08-26. Items are ordered roughly by severity within each section. Includes issues in code added this week (markdown preview/format bar, Save As), flagged as such.

**Status (2026-08-26):** all of §1 (Bugs) and §2 (Security & Privacy) are fixed, plus the two data-loss items the user selected from §3 (delete confirmation, Remove Lock). See the implementation plan (`/Users/brian/.claude/plans/streamed-forging-noodle.md`) for exact scope and rationale. §4 (Performance, beyond the §1.1 fix), most of §5 (UX polish), and the rest of §6 (Feature Candidates) remain open — deferred by choice, not overlooked.

**Update (2026-08-27):** §2.2's Touch ID hardening kept throwing errors even after its entitlement fix (see §2.2 below for the full investigation) — the feature is now **shelved**: code intact, Settings toggle and unlock button hidden, README's Touch ID mention removed. Passcode-only locking is unaffected and is the only unlock method currently exposed in the UI.

---

## 1. Likely Bugs

### 1.1 ✅ FIXED — Typing in an unlocked-locked note runs 200k PBKDF2 iterations per keystroke
`NoteStore.updateLockedText` (NoteStore.swift:163) calls `LockManager.encrypt` on every character typed, and every `encrypt` call re-derives the key with PBKDF2 at 200,000 iterations (LockManager.swift:15) plus generates a fresh salt. PBKDF2-SHA256 at 200k is deliberately slow — tens of ms per call — so editing a locked note does slow key derivation *and* a full re-encrypt *and* a disk write on **every keystroke**. Typing lag on locked notes is the expected symptom.
**Fixed:** the key derived at `unlock()` is cached (`NoteStore.sessionKeys`) and reused by a new keyed `LockManager.encrypt(_:key:salt:)` overload; `updateLockedText` no longer re-derives. Confirmed with a standalone timing probe: ~1350x faster per save.

### 1.2 ✅ FIXED — `pendingFormat` binding is written synchronously during `updateNSView` *(new this week)*
LinkAwareTextEditor.swift:105–108: `pendingFormat = nil` — and worse, the whole `apply()` chain, which fires `textDidChange` → `parent.text = ...` — runs synchronously inside `updateNSView`. That's a SwiftUI state write during view update ("Modifying state during view update, this will cause undefined behavior" purple runtime warning). The neighboring `shouldFocus` consumption got this right by deferring via `DispatchQueue.main.async`; the format consumption should do the same.
**Fixed:** wrapped in `DispatchQueue.main.async`, matching `shouldFocus`.

### 1.3 ⚠️ PARTIALLY ADDRESSED — The format-button doc comment promises a toggle that doesn't exist *(new this week)*
The `MarkdownFormatAction` comment (LinkAwareTextEditor.swift:4–10) says re-selecting the wrapped text lets "a second click of the same button toggle it back off." No unwrap logic exists — clicking Bold on `**bold**` produces `****bold****`. Either implement unwrap-if-already-wrapped or fix the comment.
**Resolved by choice:** comment corrected to describe actual behavior; real toggle-off was explicitly declined for this pass (still fits as feature candidate §6.5).

### 1.4 ✅ FIXED — `lastUsedPasscode` survives popover close unless auto-relock is "Immediate"
SPEC.md and the field's own doc comment (NoteStore.swift:27–30) say the session passcode is "cleared … when the popover closes." But `popoverDidClose()` (NoteStore.swift:207) only calls `relockAll()` — the only place that nils `lastUsedPasscode` — when `autoRelockDelay == .immediate`. With any other setting, the passcode stays in memory (and keeps pre-filling unlock sheets) indefinitely across popover open/close cycles. Behavior and documentation disagree; decide which is intended.
**Fixed:** `popoverDidClose()` now clears `lastUsedPasscode` unconditionally; note-relocking still respects the delay setting as before.

### 1.5 ✅ FIXED — Search ignores the live content of a note that's unlocked-for-viewing
`filteredNotes` (NoteListView.swift:11–20) filters locked notes by `listTitle(showLockedPreview:)` **without** passing `unlockedText`, while `NoteRow` (line 142) displays the live 🔓 title from `decryptedCache`. So a locked note you've just unlocked shows its real title in the list but is *searchable* only by its stale snapshot / "Locked Note" label — the visible title can fail to match a search for its own text.
**Fixed:** when a note is decrypted-for-viewing, `filteredNotes` now matches against both its live content and live title, not the stale snapshot.

### 1.6 ✅ FIXED — `Note.swift` doc comment contradicts actual snapshot behavior
Note.swift:39–41 says the locked-title snapshot is "kept only if 'show note preview while locked' was on at that time." In reality `NoteStore.lock()` (line 139) and `updateLockedText` (line 170) capture it **unconditionally**; the setting is only consulted at display time (which SPEC.md describes correctly). The comment is wrong — and see §2.1 for why the unconditional capture itself is a concern.
**Fixed as a side effect of §2.1:** the code now matches this comment exactly; no doc edit was needed.

### 1.7 ✅ FIXED — `linePrefix` selection math can drift if an insert is refused
LinkAwareTextEditor.swift multi-line prefix path: `addedLength = prefix.length * lineStarts.count` assumes every `shouldChangeText` returned true, but the loop `continue`s on refusal. If any insert is skipped the final `setSelectedRange` overshoots. Edge case (refusals are rare), but the count should track actual insertions.
**Fixed:** tracks `insertedCount`, computes `addedLength` from actual successful inserts.

### 1.8 ✅ FIXED — Update-check semver comparison mishandles pre-release tags
`SettingsStore.isNewer` (SettingsStore.swift:144): a tag like `v1.2-beta` splits to `["1", "2-beta"]`, `Int("2-beta")` is nil and gets **dropped** by `compactMap`, so it compares as `1` — i.e. `1.2-beta` reads as older than `1.1`. Harmless as long as releases are plain `vX.Y`, but a footgun the day a pre-release tag is published as "latest."
**Fixed:** takes each component's leading numeric prefix instead of dropping non-numeric components outright, preserving positional alignment. Verified against 6 cases including the original bug case.

---

## 2. Security & Privacy Concerns

### 2.1 ✅ FIXED — A locked note's first line is stored in **plaintext on disk**, always
`lock()` writes `lockedTitleSnapshot` into the note's JSON regardless of whether "Show note preview while locked" is on. The whole point of locking is that content is unreadable without the passcode — yet the first line (often the most identifying line: "Bank PIN backup", "Passwords for X") sits in cleartext in `<uuid>.json` even for users who never enabled the preview setting. The display-time toggle only controls *showing* it, not *storing* it.
**Fixed, going forward only (by choice):** `lock()`, `updateLockedText()`, and `relock()`'s backfill all now gate writing the snapshot behind `settings.showTitlePreviewWhileLocked`. Notes already carrying a plaintext snapshot from before this fix are left alone until next unlock-and-relock — no forced migration/scrub was built.

### 2.2 ⏸️ SHELVED (hardening was fixed, feature is now hidden) — Touch ID gating is app-side only — the Keychain item itself is not biometry-protected
KeychainStore.swift admits it in its own comment: the passcode is stored with plain `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and **no** `SecAccessControl`. The `BiometricAuth` prompt is a UI gate, not a cryptographic one: anyone with the Mac login password can read the passcode via Keychain Access.app, and any code running as this app can skip the prompt entirely. Real protection means `SecAccessControlCreateWithFlags(..., .biometryCurrentSet)` on the item so the Secure Enclave enforces the biometric check.
**Fixed:** `KeychainStore.save` now builds the item with `SecAccessControl(.biometryCurrentSet)`; the OS enforces the biometric check on read. Two follow-on fixes this required: `hasPasscode` was rewritten to check existence without triggering a Touch ID prompt (it no longer calls `loadPasscode`), and `unlockWithTouchID` no longer does its own `BiometricAuth.authenticate` pre-check (would have shown two prompts back to back). **Known limitation, accepted:** items saved before this fix aren't retroactively hardened — they self-heal on the note's next lock or Touch ID re-toggle.
**Regression #1, found and fixed right after shipping this:** `SecItemCopyMatching` against a `SecAccessControl`-protected item is a synchronous, blocking call — it blocks the calling thread for as long as the system Touch ID sheet is up. `unlockWithTouchID` called it directly from a SwiftUI button action (main thread), and when the system prompt didn't get input focus cleanly, the *entire app* froze — every click stopped registering, not just the unlock sheet. Reported live by the user, reproduced by "had to exit and load it" (force-quit) fixing it, consistent with a blocked main thread rather than a logic bug. **Fixed:** the Keychain read now runs on a background queue; only the resulting `NoteStore` mutation (`unlock`/`removeLock`) hops back to `DispatchQueue.main`, since that's the only part touching `@Published` state.

**Regression #2, found right after fixing #1 — the "Unlock with Touch ID" button never appeared at all, even freshly locking a note with the setting on.** Root cause, confirmed by two independent checks rather than guessed: (1) a standalone probe reproduced `SecItemAdd` failing with OSStatus **-34018 "A required entitlement isn't present"** when creating a `SecAccessControl(.biometryCurrentSet)` item; (2) inspecting the real built `.app`'s actual entitlements (`codesign -d --entitlements :- QuickNotes.app`) showed it had none at all beyond the default debug `get-task-allow` — the project's `CODE_SIGN_ENTITLEMENTS` build setting was empty. A valid Team-signed build (this one is: Team ID `47T99HK7GU`, not ad-hoc) still needs an explicit `keychain-access-groups` entitlement for biometry-gated Keychain items; without it, `KeychainStore.save()` was silently failing on every single lock, so no note ever actually got a Touch ID passcode saved, no matter what. **Fixed:** added `QuickNotes/QuickNotes.entitlements` declaring `keychain-access-groups`, wired into `CODE_SIGN_ENTITLEMENTS` for both Debug and Release.

### 2.3 ✅ FIXED — Disabling the Touch ID setting leaves passcodes in the Keychain
Toggling "Unlock notes with Touch ID" off (SettingsStore.swift:82) doesn't delete previously saved passcodes. Combined with §2.2, a user who tried Touch ID once and turned it off still has every passcode from that era sitting in the Keychain. The toggle's `didSet` should purge (or the setting text should say passcodes are kept).
**Fixed:** `NoteStore.wipeAllSavedTouchIDPasscodes()`, called from a new `AppDelegate` observer on the setting's toggle-to-off transition.

### 2.4 ✅ FIXED (corrected framing) — Relock timers can be delayed by App Nap, not "sleep"
Originally written as "`scheduleAutoRelock` uses `Timer.scheduledTimer`, which doesn't count time the Mac spends asleep... stays decrypted-in-memory... long after wall-clock time." **This framing turned out to be inaccurate** — `Timer`'s fire date is wall-clock (`Date`) based, so sleep doesn't cause drift; an overdue timer fires promptly on wake. The real, well-documented risk for an app with no visible window most of the time is **App Nap** deferring background timers while idle-and-unseen.
**Fixed:** each scheduled relock timer is now bracketed with a `ProcessInfo.processInfo.beginActivity`/`endActivity` token (`NoteStore.relockActivities`) so macOS doesn't throttle it.

### 2.5 ✅ FIXED — Silent failure modes around persistence
Every disk operation is `try?`: `persist()` (NoteStore.swift:67), `loadAll()`'s `compactMap` (drops undecodable files without a trace), and the new `exportNote` write (NoteDetailView.swift). Disk-full, permissions, or a corrupt JSON file all fail invisibly — the worst case being an edit the user believes is saved. At minimum, log; ideally surface a one-time alert when a persist fails.
**Fixed, logging only (by choice):** all three sites now log via `os.Logger` on failure, discoverable in Console.app. A user-facing alert was considered out of scope for this pass — still open as a follow-up if wanted.

---

## 3. Data-Loss / Destructive-Action Concerns

### 3.1 ⚠️ PARTIALLY FIXED — Context-menu Delete is instant and unrecoverable; detail-pane Delete confirms
NoteListView.swift:89 deletes immediately from the right-click menu (no dialog), while the trash button in NoteDetailView goes through a confirmation. Same action, different safety rails — and there is **no undo and no trash** anywhere: `delete()` removes the JSON file on the spot. A slip on the context menu is permanent data loss. Recommend: confirm in both places, or (better, see §6.1) a soft-delete.
**Fixed:** context-menu Delete now confirms via the same dialog pattern as the detail-pane trash button. **Still open by choice:** no trash/undo — a slip past the confirmation is still permanent (§6.1).

### 3.2 ✅ FIXED (Remove Lock only) — There is no way to permanently remove a lock or change a passcode
Nothing in the codebase ever sets `isLocked = false`. `unlock()` only decrypts into the session cache; `relock()` restores the locked state. Once a note is locked: you cannot convert it back to a plain note, and you cannot change its passcode (locking is guarded by `!notes[idx].isLocked`). The only escape hatch is copy-text-out → delete note → recreate. This is a functional hole, not just a nicety — see §6.2.
**Fixed:** new "Remove Lock…" context-menu item (`NoteStore.removeLock`) verifies the passcode, decrypts, and converts the note back to plain text — clearing the encrypted payload, snapshot, and Keychain entry. **Still open:** "Change Passcode…" (re-encrypt with a new passcode without ever exposing the note in between) was not built this pass.

---

## 4. Performance

- **4.1 Full-document work on every keystroke.** `textDidChange` re-runs `applyLinkDetection` (NSDataDetector over the whole text + line enumeration) and `updateText` persists the entire note to disk, per keystroke. Fine at sticky-note scale; will lag on a pasted 10k-line log. A short debounce on both would cover it. **Note:** the multiplier this had with §1.1 (PBKDF2 per keystroke) is gone now that §1.1 is fixed; debouncing itself was explicitly declined for this pass and remains open.
- **4.2 `MarkdownPreviewView.rendered` re-parses on every body evaluation.** No caching; each SwiftUI render re-parses the markdown and re-walks all runs. Cheap for small notes, but an easy `@State`-cached (text, fontSize) → AttributedString memo if it ever shows up in profiling.
- **4.3 `updateNSView` does an O(n) string compare** (`textView.string != text`) every render pass. Known cost of the pattern; noted for completeness.

---

## 5. UX / Consistency / Polish

- **5.1 NSSavePanel and About panel in an LSUIElement app** *(Save As is new this week)*: menu-bar apps aren't "active" in the normal sense; `panel.begin {}` and `orderFrontStandardAboutPanel` can open **behind** other apps' windows without an `NSApp.activate(ignoringOtherApps: true)` first. Needs a GUI check; likely both call sites want an activate. (Not sandboxed — no entitlements — so at least the panel is in-process and the outside-click monitor won't close the popover for it.)
- **5.2 Touch ID failure is silent.** `unlockWithTouchID` (NoteListView.swift:283) just returns on failure — no error text, sheet stays open with no feedback. Same if the Keychain passcode turns out to be stale/wrong.
- **5.3 Passcode mismatch while locking gives no message** — the Lock button silently disables when the confirm field differs. A small "passcodes don't match" caption would explain the dead button.
- **5.4 ✅ FIXED — Unlock pre-fill uses the last passcode from *any* note.** With per-note passcodes, the pre-filled value is often wrong for this note; the user hits Return, gets "Incorrect passcode," and the field clears. Consider pre-filling only when that passcode actually belongs to this note (or not pre-filling at all now that Touch ID exists).
  **Fixed:** rather than remove pre-fill entirely, `PasscodeSheet`'s `onAppear` now attempts a real `LockManager.decrypt` with the remembered passcode against *this* note's payload and only pre-fills if that actually succeeds — reported live by the user after seeing it confidently pre-fill a wrong passcode for a note with a different one.
- **5.5 Enabling Touch ID doesn't cover already-locked notes.** The passcode is only saved to the Keychain at lock time. Notes locked before the setting was enabled never offer Touch ID (`hasPasscode` is false) until re-locked. A successful manual unlock could backfill the Keychain when the setting is on.
- **5.6 ✅ FIXED (line breaks + paragraph spacing) — MD preview loses features the Text editor has** *(new this week)*: file-path lines aren't clickable links, blockquotes/thematic breaks/tables/nested-list indentation aren't rendered (a `---` line vanishes entirely — its block has no text runs). **Still open:** clickable file links, blockquote/thematic-break/table rendering.
  **User-reported symptom #1 (root cause found and fixed):** a single Enter between lines with no blank line — i.e. within one paragraph — never produced a visible break in MD mode; only `<br>` or trailing hard-break markup did. Root cause: that's a CommonMark "soft break," which Foundation's parser renders as a plain space by spec, not a line break — confirmed with a standalone probe showing the parser literally substitutes `" "` for the typed `\n` and marks the run `inlinePresentationIntent.softBreak`. **Fixed:** `MarkdownPreviewView` now detects `.softBreak` and renders it as an actual `"\n"` instead.
  **User-reported symptom #2 (found right after, same root cause family):** even *separate* paragraphs (blank-line-separated in Text mode) rendered squished together with no visible gap in MD mode — the first fix above only inserted a single `"\n"` per block-identity change, which moves to the next line but isn't the same as the blank row the user actually sees in Text mode. **Fixed:** block separators are now `"\n\n"` (a real blank line) between distinct blocks, while consecutive items of the *same* list stay tight with a single `"\n"` so lists don't get an unwanted gap between every item.
- **5.7 Search text persists across popover close/open.** Reopening shows yesterday's filter still applied — with the note list mysteriously short. Clearing `searchText` on close (or on popover open) matches the "disposable" spirit.
- **5.8 No Esc-to-close for the popover.** `.applicationDefined` opts out of the standard escape handling; keyboard users have no way to dismiss without clicking elsewhere or re-hitting ⌥N.
- **5.9 No ⌘F to focus search** — small, but it's the kind of app you drive from the keyboard.
- **5.10 Accessibility:** all header/toolbar buttons are icon-only with tooltips via `reliableHelp`, but no `.accessibilityLabel`s — VoiceOver reads them as unlabeled buttons.
- **5.11 Update check opens the browser unannounced at launch.** With Launch-at-Login on, a new release means the Mac boots into a GitHub page with no explanation. A notification or a badge in Settings would be gentler. Also: the check runs only at launch, and this is a background app that can stay up for weeks — a longer-running instance never learns about updates.
- **5.12 `HotkeyManager.registry` never removes entries** (HotkeyManager.swift:8) — `unregister()` clears the Carbon refs but leaves the manager in the static dictionary, keeping it alive forever. Harmless with one app-lifetime instance; a leak if the class is ever used more dynamically.
- **5.13 Hardcoded English throughout** — fine for a personal app; noted in case distribution ambitions grow.

---

## 6. Feature Candidates

Ordered by how much they'd matter, weighed against the app's "disposable, local, no clutter" pitch.

1. ⚠️ **Trash / undo delete.** Delete confirmation shipped (§3.1); the trash/undo half was explicitly declined for this pass and is still the single biggest remaining safety gap. Even a "deleted notes linger in a `.Trash` subfolder for 7 days" scheme keeps the flat-JSON design.
2. ✅ **Remove Lock / Change Passcode.** "Remove Lock…" shipped (§3.2); "Change Passcode…" was not built this pass.
3. ✅ **Encrypt (or opt-in-only capture) the locked-title snapshot** — shipped as opt-in-only capture (§2.1).
4. ✅ **Hardware-backed Touch ID** via `SecAccessControl` — shipped (§2.2).
5. ⚠️ **Markdown toggle-off on format buttons** — declined this pass; comment corrected instead (§1.3).
6. **Export/backup all notes** (zip of the JSON folder, or a folder of `.txt`/`.md` via the existing per-note export logic). Still open.
7. **Live in-place markdown styling** (Bear-style) — the deferred third option from the original MD discussion; the biggest lift on this list, and it would subsume the read-only preview. Still open.
8. **Configurable global hotkey** — ⌥N conflicts with typing "ñ"-adjacent option-key input on some layouts; a recorder control would fix it for everyone. Still open.
9. **Periodic update check** for long-running instances (§5.11). Still open.
10. **Word/character count** in the format bar's empty right side — cheap, on-theme. Still open.
11. **Search through version history.** `filteredNotes` only ever checks a note's *current* text/title — never `versionHistory` — so content that got wiped out and only survives in a past version can't be found by search; you have to already know (or guess) which note to check, then dig through its Version History manually. Left as-is for now (user's call, 2026-08-27) — noted here as a candidate if the feature gets revisited.

---

## 7. Testing & Tooling

- **No test target exists.** The most test-worthy units are pure and dependency-free: `LockManager` round-trips, `SettingsStore.isNewer`, `Note.listTitle`, `suggestedFileName`, sort order, and the `MarkdownFormatAction.apply` selection math (already validated once via a throwaway NSTextView harness this week — that harness is exactly the seed of a real XCTest file).
- **Headless build verification is limited to `swiftc -typecheck` + `plutil -lint`** on this machine (documented in SPEC.md). Anything touching AppKit runtime behavior (panels, popover, first-responder dances) requires a human in the Xcode GUI — worth keeping a manual smoke-test checklist alongside the release process.
