import Foundation
import Combine
import AppKit

final class NoteStore: ObservableObject {
    @Published var notes: [Note] = []
    @Published var selectedNoteID: UUID? {
        didSet {
            guard let old = oldValue, old != selectedNoteID else { return }
            if settings.autoRelockDelay == .immediate {
                relock(old)
            }
            // Re-sort here, once, when you actually leave a note — not on every
            // keystroke while editing it (see updateText). Re-sorting the whole
            // list on every character was churning the sidebar's List constantly
            // while typing, which could eat clicks meant for other rows.
            resort()
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

    private var sessionPasscodes: [UUID: String] = [:]
    private var relockTimers: [UUID: Timer] = [:]
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
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(Note.self, from: data)
            }
            .sorted(by: sortOrder)
    }

    private func persist(_ note: Note) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(note) else { return }
        try? data.write(to: fileURL(for: note.id), options: .atomic)
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
        notes.removeAll { $0.id == id }
        decryptedCache[id] = nil
        sessionPasscodes[id] = nil
        KeychainStore.deletePasscode(for: id)
        try? FileManager.default.removeItem(at: fileURL(for: id))
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

    // MARK: - Locking

    func lock(_ id: UUID, passcode: String) {
        guard let idx = notes.firstIndex(where: { $0.id == id }),
              !notes[idx].isLocked,
              let plainText = notes[idx].plainText,
              let payload = try? LockManager.encrypt(plainText, passcode: passcode) else { return }
        notes[idx].encryptedPayload = payload
        notes[idx].lockedTitleSnapshot = firstLine(of: plainText)
        notes[idx].plainText = nil
        notes[idx].isLocked = true
        notes[idx].modifiedAt = Date()
        decryptedCache[id] = nil
        sessionPasscodes[id] = nil
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
        lastUsedPasscode = passcode
        scheduleAutoRelock(for: id)
        return true
    }

    /// Re-encrypts a locked note's edits using the passcode from this unlock session.
    func updateLockedText(_ text: String, for id: UUID) {
        guard let idx = notes.firstIndex(where: { $0.id == id }),
              notes[idx].isLocked,
              let passcode = sessionPasscodes[id],
              let payload = try? LockManager.encrypt(text, passcode: passcode) else { return }
        decryptedCache[id] = text
        notes[idx].encryptedPayload = payload
        notes[idx].lockedTitleSnapshot = firstLine(of: text)
        notes[idx].modifiedAt = Date()
        persist(notes[idx])
        scheduleAutoRelock(for: id) // editing counts as activity; push the timer back out
    }

    func relock(_ id: UUID) {
        relockTimers[id]?.invalidate()
        relockTimers[id] = nil

        // Backfills the title snapshot for notes that were locked before this
        // feature existed (or while the preview setting was off), so simply
        // viewing and re-locking a note is enough to pick it up.
        if let idx = notes.firstIndex(where: { $0.id == id }),
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
    }

    func relockAll() {
        for id in decryptedCache.keys {
            relock(id)
        }
        lastUsedPasscode = nil
    }

    /// Called when the popover closes. Only force-relocks everything when the
    /// auto-relock setting is "Immediate" — longer delays and "until quit" are
    /// meant to survive the popover closing, backed by a real Timer since this
    /// is a background app that keeps running.
    func popoverDidClose() {
        if settings.autoRelockDelay == .immediate {
            relockAll()
        }
    }

    private func scheduleAutoRelock(for id: UUID) {
        relockTimers[id]?.invalidate()
        relockTimers[id] = nil
        guard let seconds = settings.autoRelockDelay.seconds else { return }
        relockTimers[id] = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            self?.relock(id)
        }
    }

    private func firstLine(of text: String) -> String {
        let line = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        return line.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Storage location

    func revealNotesFolderInFinder() {
        NSWorkspace.shared.open(directory)
    }
}
