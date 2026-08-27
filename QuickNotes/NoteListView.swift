import SwiftUI
import AppKit

struct NoteListView: View {
    @EnvironmentObject var noteStore: NoteStore
    @EnvironmentObject var settings: SettingsStore
    @Binding var showingSettings: Bool
    @State private var passcodePrompt: PasscodePrompt?
    @State private var searchText = ""

    private var filteredNotes: [Note] {
        guard !searchText.isEmpty else { return noteStore.notes }
        return noteStore.notes.filter { note in
            if note.isLocked {
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
                                noteStore.delete(note.id)
                            }
                        }
                }
            }
            .listStyle(.sidebar)
        }
        .sheet(item: $passcodePrompt) { prompt in
            PasscodeSheet(prompt: prompt).environmentObject(noteStore).environmentObject(settings)
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
                Text(note.listTitle(showLockedPreview: settings.showTitlePreviewWhileLocked,
                                     unlockedText: noteStore.decryptedCache[note.id]))
                    .font(.system(size: settings.noteFontSize.pointSize, weight: .medium))
                    .lineLimit(1)
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
    enum Mode { case lock, unlock }
    let id: UUID
    let mode: Mode
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
        prompt.mode == .unlock && settings.useTouchIDForLockedNotes
            && BiometricAuth.isAvailable && KeychainStore.hasPasscode(for: prompt.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(prompt.mode == .lock ? "Lock Note" : "Unlock Note")
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
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button(prompt.mode == .lock ? "Lock" : "Unlock") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(passcode.isEmpty || (prompt.mode == .lock && passcode != confirmPasscode))
            }
        }
        .padding(20)
        .frame(width: 300)
        .onAppear {
            if let remembered = noteStore.lastUsedPasscode {
                passcode = remembered
                if prompt.mode == .lock { confirmPasscode = remembered }
            }
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
        }
    }

    private func unlockWithTouchID() {
        BiometricAuth.authenticate(reason: "Unlock this note") { success in
            guard success, let savedPasscode = KeychainStore.loadPasscode(for: prompt.id) else { return }
            if noteStore.unlock(prompt.id, passcode: savedPasscode) {
                dismiss()
            }
        }
    }
}
