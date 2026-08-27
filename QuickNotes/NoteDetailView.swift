import SwiftUI
import AppKit

struct NoteDetailView: View {
    @EnvironmentObject var noteStore: NoteStore
    @EnvironmentObject var settings: SettingsStore
    @State private var passcodePrompt: PasscodePrompt?
    @State private var showingDeleteConfirmation = false
    @State private var shouldFocusEditor = false

    private var selectedNote: Note? {
        noteStore.notes.first { $0.id == noteStore.selectedNoteID }
    }

    var body: some View {
        Group {
            if let note = selectedNote {
                VStack(spacing: 0) {
                    header(for: note)
                    Divider()
                    if note.isLocked && noteStore.decryptedCache[note.id] == nil {
                        lockedPlaceholder(for: note)
                    } else {
                        LinkAwareTextEditor(
                            text: textBinding(for: note),
                            fontSize: settings.noteFontSize.pointSize,
                            shouldFocus: $shouldFocusEditor
                        )
                    }
                }
            } else {
                Text("Select or create a note")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(item: $passcodePrompt) { prompt in
            PasscodeSheet(prompt: prompt).environmentObject(noteStore).environmentObject(settings)
        }
        .confirmationDialog("Delete this note?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let id = selectedNote?.id { noteStore.delete(id) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .onChange(of: noteStore.selectedNoteID) { _, _ in
            shouldFocusEditor = true
        }
    }

    private func header(for note: Note) -> some View {
        HStack(spacing: 10) {
            Text(note.modifiedAt.formatted(date: .long, time: .shortened))
                .font(.system(size: max(settings.noteFontSize.pointSize - 2, 9)))
                .foregroundStyle(.secondary)

            Spacer()

            Button(action: { copyToClipboard(note) }) {
                Image(systemName: "doc.on.doc")
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .reliableHelp("Copy Note to Clipboard")
            .disabled(note.isLocked && noteStore.decryptedCache[note.id] == nil)

            lockButton(for: note)

            Button(action: { showingDeleteConfirmation = true }) {
                Image(systemName: "trash")
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .reliableHelp("Delete Note")
        }
        .buttonStyle(.borderless)
        .padding(10)
    }

    @ViewBuilder
    private func lockButton(for note: Note) -> some View {
        if !note.isLocked {
            Button(action: { passcodePrompt = PasscodePrompt(id: note.id, mode: .lock) }) {
                Image(systemName: "lock")
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .reliableHelp("Lock Note")
        } else if noteStore.decryptedCache[note.id] != nil {
            Button(action: { noteStore.relock(note.id) }) {
                Image(systemName: "lock.open.fill")
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .reliableHelp("Re-lock")
        } else {
            Button(action: { passcodePrompt = PasscodePrompt(id: note.id, mode: .unlock) }) {
                Image(systemName: "lock.fill")
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .reliableHelp("Unlock Note")
        }
    }

    private func lockedPlaceholder(for note: Note) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Button("Unlock…") {
                passcodePrompt = PasscodePrompt(id: note.id, mode: .unlock)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func textBinding(for note: Note) -> Binding<String> {
        Binding(
            get: {
                note.isLocked ? (noteStore.decryptedCache[note.id] ?? "") : (note.plainText ?? "")
            },
            set: { newValue in
                if note.isLocked {
                    noteStore.updateLockedText(newValue, for: note.id)
                } else {
                    noteStore.updateText(newValue, for: note.id)
                }
            }
        )
    }

    private func copyToClipboard(_ note: Note) {
        let content = note.isLocked ? (noteStore.decryptedCache[note.id] ?? "") : (note.plainText ?? "")
        guard !content.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
    }
}
