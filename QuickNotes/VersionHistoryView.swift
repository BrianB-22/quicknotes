import SwiftUI
import AppKit

/// Read-only timeline of a plain note's past versions (see `NoteStore.checkpointVersion`),
/// with copy-to-clipboard for manual recovery. Deliberately no restore action — the
/// user copies whatever text they need and pastes it back into the note themselves.
struct VersionHistoryView: View {
    @EnvironmentObject var noteStore: NoteStore
    @Environment(\.dismiss) private var dismiss
    let noteID: UUID

    @State private var selectedEntryID: String?

    /// A row in the timeline — either the note's live text right now (always
    /// shown first, tagged "(Current)", so it's easy to compare against past
    /// versions without leaving the sheet) or an actual saved `NoteVersion`.
    private enum HistoryEntry: Identifiable {
        case current(text: String, modifiedAt: Date)
        case past(NoteVersion)

        var id: String {
            switch self {
            case .current: return "current"
            case .past(let version): return version.savedAt.ISO8601Format()
            }
        }

        var text: String {
            switch self {
            case .current(let text, _): return text
            case .past(let version): return version.text
            }
        }

        var savedAt: Date {
            switch self {
            case .current(_, let modifiedAt): return modifiedAt
            case .past(let version): return version.savedAt
            }
        }

        var isCurrent: Bool {
            if case .current = self { return true }
            return false
        }
    }

    private var note: Note? {
        noteStore.notes.first(where: { $0.id == noteID })
    }

    private var versions: [NoteVersion] {
        (note?.versionHistory ?? []).sorted { $0.savedAt > $1.savedAt }
    }

    /// Current text is only prepended when there's at least one past version
    /// to compare it against — with none, the empty state below is more
    /// useful than a solo "(Current)" row with nothing to diff against.
    private var entries: [HistoryEntry] {
        guard let note, !versions.isEmpty else { return [] }
        return [.current(text: note.plainText ?? "", modifiedAt: note.modifiedAt)] + versions.map(HistoryEntry.past)
    }

    private var selectedEntry: HistoryEntry? {
        entries.first(where: { $0.id == selectedEntryID }) ?? entries.first
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Version History")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(10)

            Divider()

            if versions.isEmpty {
                emptyState
            } else {
                HSplitView {
                    versionList
                        .frame(minWidth: 180, idealWidth: 200, maxWidth: 240)
                    detail
                        .frame(minWidth: 300)
                }
            }
        }
        .frame(width: 560, height: 420)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("No previous versions yet")
                .foregroundStyle(.secondary)
            Text("A version is saved each time you leave this note after editing it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var versionList: some View {
        List(entries, selection: $selectedEntryID) { entry in
            row(for: entry).tag(entry.id)
        }
        .listStyle(.sidebar)
    }

    private func row(for entry: HistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(entry.savedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 13, weight: .medium))
                if entry.isCurrent {
                    Text("(Current)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Text(firstLine(of: entry.text))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var detail: some View {
        if let selectedEntry {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    HStack(spacing: 4) {
                        Text(selectedEntry.savedAt.formatted(date: .long, time: .shortened))
                        if selectedEntry.isCurrent {
                            Text("(Current)")
                                .fontWeight(.semibold)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Spacer()

                    Button(action: { copyToClipboard(selectedEntry.text) }) {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                }
                .padding(10)

                Divider()

                ScrollView {
                    Text(selectedEntry.text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
            }
        } else {
            Text("Select a version")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func firstLine(of text: String) -> String {
        let line = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Empty" : trimmed
    }

    private func copyToClipboard(_ text: String) {
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
