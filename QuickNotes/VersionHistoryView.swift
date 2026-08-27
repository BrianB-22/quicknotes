import SwiftUI
import AppKit

/// Read-only timeline of a plain note's past versions (see `NoteStore.checkpointVersion`),
/// with copy-to-clipboard for manual recovery. Deliberately no restore action — the
/// user copies whatever text they need and pastes it back into the note themselves.
struct VersionHistoryView: View {
    @EnvironmentObject var noteStore: NoteStore
    @Environment(\.dismiss) private var dismiss
    let noteID: UUID

    @State private var selectedVersionID: Date?

    private var versions: [NoteVersion] {
        let note = noteStore.notes.first(where: { $0.id == noteID })
        return (note?.versionHistory ?? []).sorted { $0.savedAt > $1.savedAt }
    }

    private var selectedVersion: NoteVersion? {
        versions.first(where: { $0.id == selectedVersionID }) ?? versions.first
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
        List(versions, selection: $selectedVersionID) { version in
            VStack(alignment: .leading, spacing: 2) {
                Text(version.savedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 13, weight: .medium))
                Text(firstLine(of: version.text))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.vertical, 2)
            .tag(version.id)
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var detail: some View {
        if let selectedVersion {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(selectedVersion.savedAt.formatted(date: .long, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(action: { copyToClipboard(selectedVersion.text) }) {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                }
                .padding(10)

                Divider()

                ScrollView {
                    Text(selectedVersion.text)
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
