import SwiftUI
import Carbon

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
                Toggle("Open QuickNotes with a hotkey", isOn: $settings.globalHotkeyEnabled)
                Text("Works system-wide, even when QuickNotes isn't in focus.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if settings.globalHotkeyEnabled {
                    HotkeyRecorder(keyCode: $settings.globalHotkeyKeyCode, modifiers: $settings.globalHotkeyModifiers)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Open the pop-out window with a hotkey", isOn: $settings.windowHotkeyEnabled)
                Text("Jumps straight to the detached window — the same thing the pop-out toolbar button does — from anywhere, without opening the popover first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if settings.windowHotkeyEnabled {
                    HotkeyRecorder(keyCode: $settings.windowHotkeyKeyCode, modifiers: $settings.windowHotkeyModifiers)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Text Size")
                Picker("Text Size", selection: $settings.noteFontSize) {
                    ForEach(NoteFontSize.allCases) { size in
                        Text(size.label).tag(size)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Show titles for locked notes", isOn: $settings.showTitlePreviewWhileLocked)
                Text("When on, a locked note keeps its first-line title visible in the list, so it's easier to find at a glance. When off (more private), every locked note shows a generic \"Locked Note\" label instead — its title stays hidden until you unlock it.")
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

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Keep version history", isOn: $settings.versionHistoryEnabled)
                Text("Saves a note's previous text each time you leave it after editing, so you can recover it from Version History (right-click a note) if you accidentally wipe something out. Locked notes are excluded — history is cleared when a note is locked.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Move deleted notes to the Trash", isOn: $settings.moveDeletedNotesToTrash)
                Text("When on, deleting a note moves it to the macOS Trash, recoverable until you empty it. When off, deleting is immediate and permanent — there's no way to get the note back.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Touch ID unlock is shelved as a future feature — SecAccessControl-protected
            // Keychain items need a `keychain-access-groups` entitlement that wasn't wired
            // up correctly, and even after fixing that it kept throwing errors. Rather than
            // ship a broken/confusing option, the toggle is hidden until this is revisited;
            // see the "Touch ID" entries in PUNCHDOWN.md and SPEC.md's Design Decisions for
            // the full investigation. Passcode-only locking is unaffected.

            Toggle("Check for new versions", isOn: $settings.checkForUpdatesEnabled)

            VStack(alignment: .leading, spacing: 4) {
                Button("Show Notes in Finder…") {
                    noteStore.revealNotesFolderInFinder()
                }
                Text("Opens the folder on this Mac where your notes are stored as plain files.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 2) {
                HStack {
                    Spacer()
                    Text("QuickNotes \(appVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                HStack {
                    Spacer()
                    Link("bernacki.me", destination: URL(string: "https://bernacki.me")!)
                        .font(.caption)
                    Spacer()
                }
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
            KeyboardShortcutsView(
                globalHotkeyEnabled: settings.globalHotkeyEnabled,
                globalHotkeyKeyCode: settings.globalHotkeyKeyCode,
                globalHotkeyModifiers: settings.globalHotkeyModifiers,
                windowHotkeyEnabled: settings.windowHotkeyEnabled,
                windowHotkeyKeyCode: settings.windowHotkeyKeyCode,
                windowHotkeyModifiers: settings.windowHotkeyModifiers
            )
        }
    }
}

private struct KeyboardShortcutsView: View {
    @Environment(\.dismiss) private var dismiss
    let globalHotkeyEnabled: Bool
    let globalHotkeyKeyCode: UInt32
    let globalHotkeyModifiers: UInt32
    let windowHotkeyEnabled: Bool
    let windowHotkeyKeyCode: UInt32
    let windowHotkeyModifiers: UInt32

    private var shortcuts: [(String, String)] {
        var items = [
            ("⌘N", "New note"),
            ("Right-click menu bar icon", "Paste clipboard as new note"),
            ("⌘Return", "Confirm Lock, Unlock, or Delete"),
            ("Esc", "Cancel a dialog")
        ]
        if globalHotkeyEnabled, globalHotkeyKeyCode != 0 {
            let label = HotkeyRecorder.displayString(keyCode: globalHotkeyKeyCode, modifiers: globalHotkeyModifiers)
            items.insert((label, "Open QuickNotes from anywhere"), at: 1)
        }
        if windowHotkeyEnabled, windowHotkeyKeyCode != 0 {
            let label = HotkeyRecorder.displayString(keyCode: windowHotkeyKeyCode, modifiers: windowHotkeyModifiers)
            items.insert((label, "Open the pop-out window"), at: (globalHotkeyEnabled && globalHotkeyKeyCode != 0) ? 2 : 1)
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

// MARK: - HotkeyRecorder

/// A click-to-record control for a global hotkey — ported from QuickCal's
/// implementation of the same thing.
struct HotkeyRecorder: View {
    @Binding var keyCode: UInt32
    @Binding var modifiers: UInt32
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button(action: toggleRecording) {
            Text(isRecording ? "Press keys…" : Self.displayString(keyCode: keyCode, modifiers: modifiers))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(isRecording ? Color.accentColor : .primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(minWidth: 120)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(
                            isRecording ? Color.accentColor : Color.secondary.opacity(0.35),
                            lineWidth: isRecording ? 1.5 : 1
                        )
                        .background(RoundedRectangle(cornerRadius: 5)
                            .fill(Color(NSColor.controlBackgroundColor)))
                )
        }
        .buttonStyle(.plain)
    }

    private func toggleRecording() {
        if isRecording { stopRecording(); return }
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) { self.stopRecording(); return nil }
            let mods = Self.carbonMods(from: event.modifierFlags)
            guard mods != 0 else { return event }
            self.keyCode = UInt32(event.keyCode)
            self.modifiers = mods
            self.stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }

    private static func carbonMods(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }

    static func displayString(keyCode: UInt32, modifiers: UInt32) -> String {
        guard keyCode != 0 || modifiers != 0 else { return "Click to record" }
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        s += keyLabel(for: keyCode)
        return s
    }

    private static func keyLabel(for code: UInt32) -> String {
        let names: [UInt32: String] = [
            UInt32(kVK_Space): "Space", UInt32(kVK_Return): "↩",
            UInt32(kVK_Tab): "⇥", UInt32(kVK_Delete): "⌫",
            UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2",
            UInt32(kVK_F3): "F3", UInt32(kVK_F4): "F4",
            UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
            UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8",
            UInt32(kVK_F9): "F9", UInt32(kVK_F10): "F10",
            UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
            UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B",
            UInt32(kVK_ANSI_C): "C", UInt32(kVK_ANSI_D): "D",
            UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
            UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H",
            UInt32(kVK_ANSI_I): "I", UInt32(kVK_ANSI_J): "J",
            UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
            UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N",
            UInt32(kVK_ANSI_O): "O", UInt32(kVK_ANSI_P): "P",
            UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
            UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T",
            UInt32(kVK_ANSI_U): "U", UInt32(kVK_ANSI_V): "V",
            UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
            UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
            UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1",
            UInt32(kVK_ANSI_2): "2", UInt32(kVK_ANSI_3): "3",
            UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
            UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7",
            UInt32(kVK_ANSI_8): "8", UInt32(kVK_ANSI_9): "9",
        ]
        return names[code] ?? "Key(\(code))"
    }
}
