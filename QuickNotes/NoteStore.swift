import Foundation
import Combine
import AppKit
import CryptoKit
import os

final class NoteStore: ObservableObject {
    private static let logger = Logger(subsystem: "com.quicknotes", category: "persistence")

    @Published var notes: [Note] = []
    @Published var selectedNoteID: UUID? {
        didSet {
            if let old = oldValue, old != selectedNoteID {
                if settings.autoRelockDelay == .immediate {
                    relock(old)
                }
                checkpointVersion(for: old)
                // Re-sort here, once, when you actually leave a note — not on every
                // keystroke while editing it (see updateText). Re-sorting the whole
                // list on every character was churning the sidebar's List constantly
                // while typing, which could eat clicks meant for other rows.
                resort()
            }
            // Seed the baseline for whatever's now selected (including the very
            // first selection at launch) so a later checkpoint has something to
            // diff against. A just-deleted old note simply won't be found by
            // checkpointVersion above, since delete() removes it from `notes`
            // before nil-ing selectedNoteID.
            if let newID = selectedNoteID {
                editSessionBaselines[newID] = notes.first(where: { $0.id == newID })?.plainText
            }
        }
    }

    /// Plaintext for locked notes the user has unlocked during this viewing
    /// session. Never persisted — cleared on re-lock, note switch (if the
    /// auto-relock setting is "Immediate"), a relock timer firing, or the
    /// popover closing.
    @Published private(set) var decryptedCache: [UUID: String] = [:]

    /// The most recently used passcode this session, offered as a pre-filled
    /// convenience for locking/unlocking further notes. Cleared along with
    /// everything else when the popover closes.
    @Published private(set) var lastUsedPasscode: String?

    /// Bumped every time `popoverDidClose()` runs. Views with a local,
    /// plain-`@State`-driven `.sheet`/`.confirmationDialog`/`.alert`
    /// (Settings, lock/unlock passcode prompts, Version History, delete
    /// confirmation) observe this to force their own presentation closed.
    /// Without it, force-closing the popover from the tray icon while one of
    /// those is open — rather than dismissing it first — leaves its SwiftUI
    /// presentation state stuck `true` behind a popover window that just got
    /// torn down; every future reopen of the popover then shows a fully
    /// unresponsive note list, because a phantom modal that isn't visibly
    /// there is still capturing input. Reported live by the user
    /// (2026-08-29), reproduced via: open Settings → close the popover from
    /// the tray icon (not Done) → reopen.
    @Published private(set) var popoverCloseTick = 0

    private var sessionPasscodes: [UUID: String] = [:]
    /// Keys derived from a session's passcode, cached so re-encrypting on every
    /// keystroke (`updateLockedText`) doesn't redo the 200k-iteration PBKDF2
    /// derive each time — that alone was the dominant per-keystroke cost.
    private var sessionKeys: [UUID: SymmetricKey] = [:]
    private var relockTimers: [UUID: Timer] = [:]
    /// A plain note's text as of when it was last selected — the baseline
    /// `checkpointVersion` diffs against to decide whether leaving it should
    /// save a version. Never populated for a locked note.
    private var editSessionBaselines: [UUID: String] = [:]
    /// Keeps the process from being App Nap–throttled while a relock timer is
    /// pending — this app has no visible window most of the time (popover
    /// closed), which is exactly the profile App Nap targets for deferral.
    private var relockActivities: [UUID: NSObjectProtocol] = [:]
    private let settings: SettingsStore
    private let directory: URL

    init(settings: SettingsStore) {
        self.settings = settings
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = support.appendingPathComponent("QuickNotes", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        loadAll()
        selectedNoteID = notes.first?.id
    }

    // MARK: - Persistence

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString).appendingPathExtension("json")
    }

    private func loadAll() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        notes = files
            .compactMap { url -> Note? in
                guard let data = try? Data(contentsOf: url) else {
                    Self.logger.error("Could not read note file at \(url.lastPathComponent, privacy: .public)")
                    return nil
                }
                do {
                    return try decoder.decode(Note.self, from: data)
                } catch {
                    Self.logger.error("Could not decode note file at \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    return nil
                }
            }
            .sorted(by: sortOrder)
    }

    private func persist(_ note: Note) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(note)
            try data.write(to: fileURL(for: note.id), options: .atomic)
        } catch {
            Self.logger.error("Failed to persist note \(note.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func sortOrder(_ lhs: Note, _ rhs: Note) -> Bool {
        if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
        return lhs.modifiedAt > rhs.modifiedAt
    }

    private func resort() {
        notes.sort(by: sortOrder)
    }

    // MARK: - CRUD

    @discardableResult
    func createNote(text: String) -> UUID {
        let now = Date()
        let note = Note(id: UUID(), createdAt: now, modifiedAt: now, plainText: text)
        notes.insert(note, at: 0)
        persist(note)
        selectedNoteID = note.id
        return note.id
    }

    func updateText(_ text: String, for id: UUID) {
        guard let idx = notes.firstIndex(where: { $0.id == id }), !notes[idx].isLocked else { return }
        notes[idx].plainText = text
        notes[idx].modifiedAt = Date()
        persist(notes[idx])
    }

    func delete(_ id: UUID) {
        relockTimers[id]?.invalidate()
        relockTimers[id] = nil
        endRelockActivity(for: id)
        notes.removeAll { $0.id == id }
        decryptedCache[id] = nil
        sessionPasscodes[id] = nil
        sessionKeys[id] = nil
        editSessionBaselines[id] = nil
        KeychainStore.deletePasscode(for: id)
        // Moves to the macOS Trash rather than removing outright, so an
        // accidental delete is recoverable — copy the file back into the
        // Notes folder (see NoteListView/NoteDetailView's post-delete notice).
        do {
            try FileManager.default.trashItem(at: fileURL(for: id), resultingItemURL: nil)
        } catch {
            Self.logger.error("Failed to move note \(id, privacy: .public) to Trash: \(error.localizedDescription, privacy: .public)")
        }
        // Picking a replacement is left to the view layer (see NoteListView),
        // since only it knows which notes are visible under the active search.
        if selectedNoteID == id { selectedNoteID = nil }
    }

    func togglePin(_ id: UUID) {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[idx].isPinned.toggle()
        persist(notes[idx])
        resort()
    }

    func setColorLabel(_ label: NoteColorLabel?, for id: UUID) {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[idx].colorLabel = label
        persist(notes[idx])
    }

    func setPreviewMode(_ mode: NotePreviewMode, for id: UUID) {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[idx].previewMode = mode
        persist(notes[idx])
    }

    // MARK: - Locking

    func lock(_ id: UUID, passcode: String) {
        guard let idx = notes.firstIndex(where: { $0.id == id }),
              !notes[idx].isLocked,
              let plainText = notes[idx].plainText,
              let payload = try? LockManager.encrypt(plainText, passcode: passcode) else { return }
        notes[idx].encryptedPayload = payload
        // Only capture the title snapshot when the preview setting is actually
        // on — this is content escaping encryption onto disk in plaintext, so
        // it should never be written just because a lock happened to occur.
        notes[idx].lockedTitleSnapshot = settings.showTitlePreviewWhileLocked ? firstLine(of: plainText) : nil
        // Same reasoning as the title snapshot above: history accumulated while
        // this note was plain is still plaintext sitting in its JSON file. Once
        // it's locked, that file should hold nothing readable outside the
        // encrypted payload — so any history it had is cleared here, not kept
        // around "just in case." Versioning starts fresh if it's ever unlocked
        // for good via `removeLock`.
        notes[idx].versionHistory = nil
        notes[idx].plainText = nil
        notes[idx].isLocked = true
        notes[idx].modifiedAt = Date()
        decryptedCache[id] = nil
        sessionPasscodes[id] = nil
        sessionKeys[id] = nil
        editSessionBaselines[id] = nil
        lastUsedPasscode = passcode
        persist(notes[idx])
    }

    @discardableResult
    func unlock(_ id: UUID, passcode: String) -> Bool {
        guard let idx = notes.firstIndex(where: { $0.id == id }),
              notes[idx].isLocked,
              let payload = notes[idx].encryptedPayload,
              let text = try? LockManager.decrypt(payload, passcode: passcode) else { return false }
        decryptedCache[id] = text
        sessionPasscodes[id] = passcode
        sessionKeys[id] = LockManager.deriveKey(passcode: passcode, salt: payload.salt)
        lastUsedPasscode = passcode
        scheduleAutoRelock(for: id)
        return true
    }

    /// Re-encrypts a locked note's edits using the key cached at unlock time —
    /// deliberately not re-deriving from the passcode here, since this runs on
    /// every keystroke and PBKDF2 at 200k iterations is too slow to repeat that
    /// often (see `sessionKeys`).
    func updateLockedText(_ text: String, for id: UUID) {
        guard let idx = notes.firstIndex(where: { $0.id == id }),
              notes[idx].isLocked,
              let salt = notes[idx].encryptedPayload?.salt else { return }

        let payload: EncryptedPayload?
        if let key = sessionKeys[id] {
            payload = try? LockManager.encrypt(text, key: key, salt: salt)
        } else if let passcode = sessionPasscodes[id] {
            // Defensive fallback; shouldn't happen since unlock() always populates sessionKeys.
            payload = try? LockManager.encrypt(text, passcode: passcode)
        } else {
            payload = nil
        }
        guard let payload else { return }

        decryptedCache[id] = text
        notes[idx].encryptedPayload = payload
        if settings.showTitlePreviewWhileLocked {
            notes[idx].lockedTitleSnapshot = firstLine(of: text)
        }
        notes[idx].modifiedAt = Date()
        persist(notes[idx])
        scheduleAutoRelock(for: id) // editing counts as activity; push the timer back out
    }

    /// Verifies the passcode, then permanently converts a locked note back into
    /// a normal plain-text note — unlike `unlock()`, which only decrypts into
    /// the in-session view cache. There is otherwise no way back once a note is
    /// locked: no code path ever sets `isLocked = false` besides this one.
    @discardableResult
    func removeLock(_ id: UUID, passcode: String) -> Bool {
        guard let idx = notes.firstIndex(where: { $0.id == id }),
              notes[idx].isLocked,
              let payload = notes[idx].encryptedPayload,
              let text = try? LockManager.decrypt(payload, passcode: passcode) else { return false }

        relockTimers[id]?.invalidate()
        relockTimers[id] = nil
        endRelockActivity(for: id)

        notes[idx].isLocked = false
        notes[idx].plainText = text
        notes[idx].encryptedPayload = nil
        notes[idx].lockedTitleSnapshot = nil
        notes[idx].modifiedAt = Date()
        decryptedCache[id] = nil
        sessionPasscodes[id] = nil
        sessionKeys[id] = nil
        KeychainStore.deletePasscode(for: id)
        persist(notes[idx])
        resort() // modifiedAt changed
        return true
    }

    func relock(_ id: UUID) {
        relockTimers[id]?.invalidate()
        relockTimers[id] = nil
        endRelockActivity(for: id)

        // Backfills the title snapshot for notes that were locked before this
        // feature existed, so simply viewing and re-locking a note is enough to
        // pick it up — but only when the preview setting is actually on; when
        // it's off there's nothing to backfill (nothing should be captured).
        if settings.showTitlePreviewWhileLocked,
           let idx = notes.firstIndex(where: { $0.id == id }),
           notes[idx].isLocked,
           let text = decryptedCache[id] {
            let snapshot = firstLine(of: text)
            if notes[idx].lockedTitleSnapshot != snapshot {
                notes[idx].lockedTitleSnapshot = snapshot
                persist(notes[idx])
            }
        }
        decryptedCache[id] = nil
        sessionPasscodes[id] = nil
        sessionKeys[id] = nil
    }

    func relockAll() {
        for id in decryptedCache.keys {
            relock(id)
        }
        lastUsedPasscode = nil
    }

    /// Called when the popover closes. The remembered passcode is always
    /// forgotten here (a per-popover-session convenience, not tied to the
    /// relock delay) — but notes themselves only force-relock when the
    /// auto-relock setting is "Immediate"; longer delays and "until quit" are
    /// meant to survive the popover closing, backed by a real Timer since this
    /// is a background app that keeps running.
    func popoverDidClose() {
        lastUsedPasscode = nil
        // Closing the popover without switching notes first would otherwise
        // skip the checkpoint that normally happens in selectedNoteID's didSet.
        if let id = selectedNoteID {
            checkpointVersion(for: id)
        }
        if settings.autoRelockDelay == .immediate {
            relockAll()
        }
        popoverCloseTick += 1
    }

    /// Called when the Touch ID setting is turned off — otherwise a previously
    /// saved passcode just sits in the Keychain indefinitely with no way for
    /// the user to know it's still there.
    func wipeAllSavedTouchIDPasscodes() {
        for note in notes where note.isLocked {
            KeychainStore.deletePasscode(for: note.id)
        }
    }

    private func scheduleAutoRelock(for id: UUID) {
        relockTimers[id]?.invalidate()
        relockTimers[id] = nil
        endRelockActivity(for: id)
        guard let seconds = settings.autoRelockDelay.seconds else { return }
        relockActivities[id] = ProcessInfo.processInfo.beginActivity(
            options: .userInitiated, reason: "QuickNotes auto re-lock timer"
        )
        relockTimers[id] = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            self?.relock(id)
        }
    }

    private func endRelockActivity(for id: UUID) {
        guard let activity = relockActivities[id] else { return }
        ProcessInfo.processInfo.endActivity(activity)
        relockActivities[id] = nil
    }

    private func firstLine(of text: String) -> String {
        let line = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        return line.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Version history

    private static let maxVersionsPerNote = 30

    /// Saves `id`'s text as of when it was last selected (its `editSessionBaselines`
    /// entry) as a recoverable version, if it actually changed since then. Called
    /// when leaving a note (switching away, or closing the popover) rather than
    /// per keystroke — a version represents "how the note looked before this
    /// editing session," not a full undo log. No-ops for a locked note (never
    /// populated a baseline to begin with) or a just-deleted one (no longer in
    /// `notes`).
    private func checkpointVersion(for id: UUID) {
        guard settings.versionHistoryEnabled,
              let idx = notes.firstIndex(where: { $0.id == id }),
              !notes[idx].isLocked,
              let baseline = editSessionBaselines[id],
              let current = notes[idx].plainText,
              current != baseline else { return }

        var history = notes[idx].versionHistory ?? []
        history.append(NoteVersion(text: baseline, savedAt: Date()))
        if history.count > Self.maxVersionsPerNote {
            history.removeFirst(history.count - Self.maxVersionsPerNote)
        }
        notes[idx].versionHistory = history
        persist(notes[idx])
        editSessionBaselines[id] = current
    }

    // MARK: - Storage location

    func revealNotesFolderInFinder() {
        NSWorkspace.shared.open(directory)
    }
}
