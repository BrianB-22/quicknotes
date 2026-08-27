import SwiftUI
import AppKit

struct NoteListView: View {
    @EnvironmentObject var noteStore: NoteStore
    @EnvironmentObject var settings: SettingsStore
    @Binding var showingSettings: Bool
    @State private var passcodePrompt: PasscodePrompt?
    @State private var searchText = ""
    @State private var pendingDeleteID: UUID?
    @State private var versionHistoryPrompt: VersionHistoryPrompt?
    @State private var deletionNotice: DeletionNotice?

    private var filteredNotes: [Note] {
        guard !searchText.isEmpty else { return noteStore.notes }
        return noteStore.notes.filter { note in
            if note.isLocked {
                // A note unlocked-for-viewing this session is functionally
                // unlocked from the user's perspective — match its live
                // content/title, not the stale on-disk snapshot, so the title
                // shown in the row (see NoteRow below) can't fail to match.
                if let unlockedText = noteStore.decryptedCache[note.id] {
                    return unlockedText.localizedCaseInsensitiveContains(searchText)
                        || note.listTitle(showLockedPreview: settings.showTitlePreviewWhileLocked, unlockedText: unlockedText)
                            .localizedCaseInsensitiveContains(searchText)
                }
                return note.listTitle(showLockedPreview: settings.showTitlePreviewWhileLocked)
                    .localizedCaseInsensitiveContains(searchText)
            }
            return (note.plainText ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button(action: newNote) {
                    Image(systemName: "square.and.pencil")
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .keyboardShortcut("n", modifiers: .command)
                .reliableHelp("New Note (⌘N)")

                Button(action: pasteAsNewNote) {
                    Image(systemName: "doc.on.clipboard")
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .reliableHelp("New Note from Clipboard")

                Spacer()

                Button(action: { showingSettings = true }) {
                    Image(systemName: "gearshape")
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .reliableHelp("Settings")
            }
            .buttonStyle(.borderless)
            .padding(10)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search notes", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)

            Divider()

            List(selection: $noteStore.selectedNoteID) {
                ForEach(filteredNotes) { note in
                    NoteRow(note: note)
                        .tag(note.id)
                        .contextMenu {
                            Button(note.isLocked ? "Unlock…" : "Lock…") {
                                passcodePrompt = PasscodePrompt(id: note.id, mode: note.isLocked ? .unlock : .lock)
                            }
                            if note.isLocked {
                                Button("Remove Lock…") {
                                    passcodePrompt = PasscodePrompt(id: note.id, mode: .removeLock)
                                }
                            } else {
                                // Locked notes (including one currently unlocked-for-viewing)
                                // never have history under the versioning rules — see
                                // NoteStore.checkpointVersion — so there's nothing to show.
                                Button("Version History…") {
                                    versionHistoryPrompt = VersionHistoryPrompt(id: note.id)
                                }
                            }
                            Button(note.isPinned ? "Unpin" : "Pin") {
                                noteStore.togglePin(note.id)
                            }
                            Menu("Label") {
                                Button("None") { noteStore.setColorLabel(nil, for: note.id) }
                                Divider()
                                ForEach(NoteColorLabel.allCases) { label in
                                    Button(label.label) { noteStore.setColorLabel(label, for: note.id) }
                                }
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                pendingDeleteID = note.id
                            }
                        }
                }
            }
            .listStyle(.sidebar)
        }
        .sheet(item: $passcodePrompt) { prompt in
            PasscodeSheet(prompt: prompt).environmentObject(noteStore).environmentObject(settings)
        }
        .sheet(item: $versionHistoryPrompt) { prompt in
            VersionHistoryView(noteID: prompt.id).environmentObject(noteStore)
        }
        .confirmationDialog(
            "Delete this note?",
            isPresented: Binding(get: { pendingDeleteID != nil }, set: { if !$0 { pendingDeleteID = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let id = pendingDeleteID, let note = noteStore.notes.first(where: { $0.id == id }) {
                    let notice = DeletionNotice(
                        note: note,
                        showLockedPreview: settings.showTitlePreviewWhileLocked,
                        unlockedText: noteStore.decryptedCache[id]
                    )
                    noteStore.delete(id)
                    deletionNotice = notice
                }
                pendingDeleteID = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteID = nil }
        }
        .alert(
            "Moved to Trash",
            isPresented: Binding(get: { deletionNotice != nil }, set: { if !$0 { deletionNotice = nil } }),
            presenting: deletionNotice
        ) { _ in
            Button("OK") { deletionNotice = nil }
        } message: { notice in
            Text("\"\(notice.title)\" was moved to the Trash as \(notice.filename). To restore it, copy the file back into the Notes folder (Settings → Show Notes in Finder…).")
        }
        .onChange(of: noteStore.selectedNoteID) { _, newValue in
            // NoteStore only ever nils this out itself when the selected note
            // was actually deleted (never just hidden by the search filter), so
            // this is safe to repair from the currently visible, filtered list.
            guard newValue == nil, !filteredNotes.isEmpty else { return }
            DispatchQueue.main.async {
                noteStore.selectedNoteID = filteredNotes.first?.id
            }
        }
    }

    private func newNote() {
        noteStore.createNote(text: "")
    }

    private func pasteAsNewNote() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        noteStore.createNote(text: text)
    }
}

private struct NoteRow: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var noteStore: NoteStore
    let note: Note

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if let colorLabel = note.colorLabel {
                Circle()
                    .fill(colorLabel.color)
                    .frame(width: 8, height: 8)
                    .padding(.top, 5)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if note.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: max(settings.noteFontSize.pointSize - 3, 8)))
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                    Text(note.listTitle(showLockedPreview: settings.showTitlePreviewWhileLocked,
                                         unlockedText: noteStore.decryptedCache[note.id]))
                        .font(.system(size: settings.noteFontSize.pointSize, weight: .medium))
                        .lineLimit(1)
                }
                RelativeTimeText(date: note.modifiedAt)
                    .font(.system(size: max(settings.noteFontSize.pointSize - 2, 9)))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

/// Relative timestamp clamped to minute granularity ("Just now" instead of
/// "3 seconds ago"), refreshing once a minute rather than every second.
private struct RelativeTimeText: View {
    let date: Date

    private static let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    var body: some View {
        TimelineView(.periodic(from: date, by: 60)) { context in
            Text(label(now: context.date))
        }
    }

    private func label(now: Date) -> String {
        let interval = now.timeIntervalSince(date)
        if interval < 60 { return "Just now" }
        return Self.formatter.localizedString(for: date, relativeTo: now)
    }
}

struct PasscodePrompt: Identifiable {
    enum Mode { case lock, unlock, removeLock }
    let id: UUID
    let mode: Mode
}

struct VersionHistoryPrompt: Identifiable {
    let id: UUID
}

/// Shown after a delete completes, confirming where the note actually went —
/// `NoteStore.delete` moves the JSON file to the macOS Trash rather than
/// removing it outright, so this tells the user exactly what to look for if
/// they want it back.
struct DeletionNotice {
    let title: String
    let filename: String

    init(note: Note, showLockedPreview: Bool, unlockedText: String?) {
        title = note.listTitle(showLockedPreview: showLockedPreview, unlockedText: unlockedText)
        filename = "\(note.id.uuidString).json"
    }
}

struct PasscodeSheet: View {
    @EnvironmentObject var noteStore: NoteStore
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    let prompt: PasscodePrompt

    @State private var passcode = ""
    @State private var confirmPasscode = ""
    @State private var errorMessage: String?

    private var offerTouchID: Bool {
        (prompt.mode == .unlock || prompt.mode == .removeLock) && settings.useTouchIDForLockedNotes
            && BiometricAuth.isAvailable && KeychainStore.hasPasscode(for: prompt.id)
    }

    private var title: String {
        switch prompt.mode {
        case .lock: return "Lock Note"
        case .unlock: return "Unlock Note"
        case .removeLock: return "Remove Lock"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            if offerTouchID {
                Button {
                    unlockWithTouchID()
                } label: {
                    Label("Unlock with Touch ID", systemImage: "touchid")
                        .frame(maxWidth: .infinity)
                }
                Text("or enter the passcode")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SecureField("Passcode", text: $passcode)
                .textFieldStyle(.roundedBorder)

            if prompt.mode == .lock {
                SecureField("Confirm Passcode", text: $confirmPasscode)
                    .textFieldStyle(.roundedBorder)

                Text("⚠️ Make a note of this passcode somewhere safe. There is no recovery option — if you forget it, this note's content is permanently unreadable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("⚠️ Locking only encrypts this note's text. Any file paths or links inside it point to files that are not encrypted themselves.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("⚠️ This note's version history will be lost when it's locked.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button(submitLabel) { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(passcode.isEmpty || (prompt.mode == .lock && passcode != confirmPasscode))
            }
        }
        .padding(20)
        .frame(width: 300)
        .onAppear {
            // Only pre-fill for unlocking/removing a lock on an already-locked
            // note — you're just proving you know the existing passcode there,
            // so skipping the retype is harmless. Locking is choosing a
            // passcode for THIS note; pre-filling both fields there would let
            // you lock it by hitting Return without ever having typed
            // anything, silently reusing whatever passcode a previous note
            // happened to use.
            //
            // Different notes can have different passcodes, so blindly
            // reusing the last one used anywhere isn't just unhelpful when
            // wrong — it confidently shows a passcode that belongs to some
            // other note, which then fails on submit. Verify it actually
            // decrypts THIS note before pre-filling; otherwise leave the field
            // empty rather than show something misleading.
            if prompt.mode != .lock,
               let remembered = noteStore.lastUsedPasscode,
               let payload = noteStore.notes.first(where: { $0.id == prompt.id })?.encryptedPayload,
               (try? LockManager.decrypt(payload, passcode: remembered)) != nil {
                passcode = remembered
            }
        }
    }

    private var submitLabel: String {
        switch prompt.mode {
        case .lock: return "Lock"
        case .unlock: return "Unlock"
        case .removeLock: return "Remove Lock"
        }
    }

    private func submit() {
        switch prompt.mode {
        case .lock:
            noteStore.lock(prompt.id, passcode: passcode)
            if settings.useTouchIDForLockedNotes {
                KeychainStore.save(passcode: passcode, for: prompt.id)
            }
            dismiss()
        case .unlock:
            if noteStore.unlock(prompt.id, passcode: passcode) {
                dismiss()
            } else {
                errorMessage = "Incorrect passcode."
                passcode = ""
            }
        case .removeLock:
            if noteStore.removeLock(prompt.id, passcode: passcode) {
                dismiss()
            } else {
                errorMessage = "Incorrect passcode."
                passcode = ""
            }
        }
    }

    /// The Keychain item is biometry-gated (see `KeychainStore`), so reading it
    /// already triggers the system's own Touch ID prompt — no separate
    /// `BiometricAuth` pre-check here, or the user would see two prompts back
    /// to back.
    ///
    /// `SecItemCopyMatching` is a synchronous, blocking call, and against a
    /// `SecAccessControl`-protected item it blocks the calling thread for as
    /// long as the system Touch ID sheet is up. Calling it directly from this
    /// button action (main thread) froze the entire app — clicks stopped
    /// registering anywhere, not just in this sheet — whenever that system
    /// prompt didn't get input focus cleanly. Dispatching the read to a
    /// background queue keeps the main thread (and the rest of the UI) free
    /// regardless of what the system prompt does; only the resulting note-store
    /// mutation hops back to main, since `NoteStore` publishes `@Published`
    /// state that must be touched there.
    private func unlockWithTouchID() {
        DispatchQueue.global(qos: .userInitiated).async {
            let savedPasscode = KeychainStore.loadPasscode(for: prompt.id)
            DispatchQueue.main.async {
                guard let savedPasscode else { return }
                switch prompt.mode {
                case .unlock:
                    if noteStore.unlock(prompt.id, passcode: savedPasscode) { dismiss() }
                case .removeLock:
                    if noteStore.removeLock(prompt.id, passcode: savedPasscode) { dismiss() }
                case .lock:
                    break
                }
            }
        }
    }
}
