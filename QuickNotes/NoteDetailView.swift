import SwiftUI
import AppKit
import UniformTypeIdentifiers
import os

struct NoteDetailView: View {
    @EnvironmentObject var noteStore: NoteStore
    @EnvironmentObject var settings: SettingsStore
    @State private var passcodePrompt: PasscodePrompt?
    @State private var showingDeleteConfirmation = false
    @State private var deletionNotice: DeletionNotice?
    @State private var shouldFocusEditor = false
    @State private var pendingFormat: MarkdownFormatAction?

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
                        Group {
                            if note.effectivePreviewMode == .markdown {
                                MarkdownPreviewView(text: textBinding(for: note), fontSize: settings.noteFontSize.pointSize)
                            } else {
                                LinkAwareTextEditor(
                                    text: textBinding(for: note),
                                    fontSize: settings.noteFontSize.pointSize,
                                    shouldFocus: $shouldFocusEditor,
                                    pendingFormat: $pendingFormat
                                )
                            }
                        }
                        Divider()
                        formatBar(for: note)
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
                if let note = selectedNote {
                    let notice = DeletionNotice(
                        note: note,
                        showLockedPreview: settings.showTitlePreviewWhileLocked,
                        unlockedText: noteStore.decryptedCache[note.id]
                    )
                    noteStore.delete(note.id)
                    deletionNotice = notice
                }
            }
            Button("Cancel", role: .cancel) {}
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
        .onChange(of: noteStore.selectedNoteID) { _, _ in
            shouldFocusEditor = true
        }
        // See NoteStore.popoverCloseTick.
        .onChange(of: noteStore.popoverCloseTick) { _, _ in
            passcodePrompt = nil
            showingDeleteConfirmation = false
            deletionNotice = nil
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

            Button(action: { exportNote(note) }) {
                Image(systemName: "square.and.arrow.down")
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .reliableHelp("Save Note As…")
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

    private func currentText(for note: Note) -> String {
        note.isLocked ? (noteStore.decryptedCache[note.id] ?? "") : (note.plainText ?? "")
    }

    private func textBinding(for note: Note) -> Binding<String> {
        Binding(
            get: { currentText(for: note) },
            set: { newValue in
                if note.isLocked {
                    noteStore.updateLockedText(newValue, for: note.id)
                } else {
                    noteStore.updateText(newValue, for: note.id)
                }
            }
        )
    }

    private func previewModeBinding(for note: Note) -> Binding<NotePreviewMode> {
        Binding(
            get: { note.effectivePreviewMode },
            set: { noteStore.setPreviewMode($0, for: note.id) }
        )
    }

    @ViewBuilder
    private func formatBar(for note: Note) -> some View {
        HStack(spacing: 10) {
            Picker("", selection: previewModeBinding(for: note)) {
                Text("TXT").tag(NotePreviewMode.text)
                Text("MD").tag(NotePreviewMode.markdown)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 110)

            Divider().frame(height: 16)

            if note.effectivePreviewMode == .text {
                formatButton("bold", action: .bold, help: "Bold")
                formatButton("italic", action: .italic, help: "Italic")
                formatButton("chevron.left.forwardslash.chevron.right", action: .code, help: "Code")
                formatButton("textformat.size", action: .heading, help: "Heading")
                formatButton("list.bullet", action: .bulletList, help: "Bulleted List")
                formatButton("checklist", action: .checklist, help: "Checklist Item")
                formatButton("link", action: .link, help: "Link")
            } else {
                Text("Read-only — checkboxes are tappable")
                    .font(.system(size: max(settings.noteFontSize.pointSize - 3, 9)))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func formatButton(_ systemImage: String, action: MarkdownFormatAction, help: String) -> some View {
        Button(action: { pendingFormat = action }) {
            Image(systemName: systemImage)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .reliableHelp(help)
    }

    private func copyToClipboard(_ note: Note) {
        let content = currentText(for: note)
        guard !content.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
    }

    private func exportNote(_ note: Note) {
        let content = currentText(for: note)
        let isMarkdown = note.effectivePreviewMode == .markdown

        let panel = NSSavePanel()
        panel.allowedContentTypes = [isMarkdown ? (UTType(filenameExtension: "md") ?? .plainText) : .plainText]
        panel.nameFieldStringValue = suggestedFileName(for: content, isMarkdown: isMarkdown)
        panel.canCreateDirectories = true

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                Self.exportLogger.error("Failed to export note to \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static let exportLogger = Logger(subsystem: "com.quicknotes", category: "export")

    private func suggestedFileName(for content: String, isMarkdown: Bool) -> String {
        let firstLine = content
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        // "/" isn't valid in a filename; anything else NSSavePanel already guards.
        let sanitized = trimmed.replacingOccurrences(of: "/", with: "-")
        let base = sanitized.isEmpty ? "Note" : String(sanitized.prefix(80))
        return "\(base).\(isMarkdown ? "md" : "txt")"
    }
}
