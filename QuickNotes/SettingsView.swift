import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var noteStore: NoteStore
    @Environment(\.dismiss) private var dismiss
    @State private var showingShortcuts = false

    private var appVersion: String {
        let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(shortVersion) (\(buildNumber))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Settings")
                    .font(.headline)
                Spacer()
                Button(action: { showingShortcuts = true }) {
                    Image(systemName: "questionmark.circle")
                }
                .buttonStyle(.borderless)
                .reliableHelp("Keyboard Shortcuts")
            }

            Toggle("Launch at login", isOn: $settings.launchAtLogin)

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Open QuickNotes with ⌥N from anywhere", isOn: $settings.globalHotkeyEnabled)
                Text("Works system-wide, even when QuickNotes isn't in focus.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Note text size")
                Picker("Note text size", selection: $settings.noteFontSize) {
                    ForEach(NoteFontSize.allCases) { size in
                        Text(size.label).tag(size)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Show note preview while locked", isOn: $settings.showTitlePreviewWhileLocked)
                Text("When on, a locked note's list title shows a snapshot of its first line from before it was locked. When off, locked notes always show a generic \"Locked Note\" label.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Auto re-lock unlocked notes")
                Picker("Auto re-lock unlocked notes", selection: $settings.autoRelockDelay) {
                    ForEach(AutoRelockDelay.allCases) { delay in
                        Text(delay.label).tag(delay)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                Text("How long an unlocked note stays readable before it locks itself again. \"Immediate\" locks it the moment you switch notes or close QuickNotes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if BiometricAuth.isAvailable {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Unlock notes with Touch ID", isOn: $settings.useTouchIDForLockedNotes)
                    Text("Saves a note's passcode in the macOS Keychain behind Touch ID, so you can unlock without typing it. The passcode is still required as a fallback.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Button("Show Notes in Finder…") {
                    noteStore.revealNotesFolderInFinder()
                }
                Text("Opens the folder on this Mac where your notes are stored as plain files.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Text("QuickNotes \(appVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
        .sheet(isPresented: $showingShortcuts) {
            KeyboardShortcutsView(globalHotkeyEnabled: settings.globalHotkeyEnabled)
        }
    }
}

private struct KeyboardShortcutsView: View {
    @Environment(\.dismiss) private var dismiss
    let globalHotkeyEnabled: Bool

    private var shortcuts: [(String, String)] {
        var items = [
            ("⌘N", "New note"),
            ("Right-click menu bar icon", "Paste clipboard as new note"),
            ("⌘Return", "Confirm Lock, Unlock, or Delete"),
            ("Esc", "Cancel a dialog")
        ]
        if globalHotkeyEnabled {
            items.insert(("⌥N", "Open QuickNotes from anywhere"), at: 1)
        }
        return items
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Keyboard Shortcuts")
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(shortcuts, id: \.1) { shortcut, description in
                    HStack {
                        Text(shortcut)
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 150, alignment: .leading)
                        Text(description)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
