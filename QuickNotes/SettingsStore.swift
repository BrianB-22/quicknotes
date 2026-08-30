import Foundation
import SwiftUI
import AppKit
import ServiceManagement

enum NoteFontSize: String, CaseIterable, Identifiable {
    case small, medium, large

    var id: String { rawValue }

    var label: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }

    var pointSize: CGFloat {
        switch self {
        case .small: return 11
        case .medium: return 13
        case .large: return 16
        }
    }
}

enum AutoRelockDelay: String, CaseIterable, Identifiable {
    case immediate, twoMinutes, fiveMinutes, tenMinutes, untilQuit

    var id: String { rawValue }

    var label: String {
        switch self {
        case .immediate: return "Immediate"
        case .twoMinutes: return "2 minutes"
        case .fiveMinutes: return "5 minutes"
        case .tenMinutes: return "10 minutes"
        case .untilQuit: return "Until app quits"
        }
    }

    /// Seconds until an unlocked note auto re-locks on its own. Nil for
    /// `.immediate` (relocks instantly when you switch away or close the
    /// popover instead of on a timer) and `.untilQuit` (no timer at all).
    var seconds: TimeInterval? {
        switch self {
        case .immediate: return nil
        case .twoMinutes: return 120
        case .fiveMinutes: return 300
        case .tenMinutes: return 600
        case .untilQuit: return nil
        }
    }
}

final class SettingsStore: ObservableObject {
    @Published var launchAtLogin: Bool = false {
        didSet { applyLaunchAtLogin() }
    }

    @Published var noteFontSize: NoteFontSize = .medium {
        didSet { UserDefaults.standard.set(noteFontSize.rawValue, forKey: "com.quicknotes.noteFontSize") }
    }

    /// When true, a note's list title stays visible (a first-line snapshot taken
    /// at lock time) even while the note is locked. When false, locked notes
    /// always show a generic "Locked Note" label instead.
    @Published var showTitlePreviewWhileLocked: Bool = false {
        didSet { UserDefaults.standard.set(showTitlePreviewWhileLocked, forKey: "com.quicknotes.showTitlePreviewWhileLocked") }
    }

    /// How long an unlocked note stays readable before it re-locks itself.
    @Published var autoRelockDelay: AutoRelockDelay = .immediate {
        didSet { UserDefaults.standard.set(autoRelockDelay.rawValue, forKey: "com.quicknotes.autoRelockDelay") }
    }

    @Published var globalHotkeyEnabled: Bool = true {
        didSet { UserDefaults.standard.set(globalHotkeyEnabled, forKey: "com.quicknotes.globalHotkeyEnabled") }
    }

    @Published var useTouchIDForLockedNotes: Bool = false {
        didSet { UserDefaults.standard.set(useTouchIDForLockedNotes, forKey: "com.quicknotes.useTouchIDForLockedNotes") }
    }

    @Published var checkForUpdatesEnabled: Bool = true {
        didSet { UserDefaults.standard.set(checkForUpdatesEnabled, forKey: "com.quicknotes.checkForUpdatesEnabled") }
    }

    /// When on (default), leaving a plain note you've edited saves its previous
    /// text as a recoverable version. Locked notes are excluded regardless of
    /// this setting — see `NoteStore.checkpointVersion`.
    @Published var versionHistoryEnabled: Bool = true {
        didSet { UserDefaults.standard.set(versionHistoryEnabled, forKey: "com.quicknotes.versionHistoryEnabled") }
    }

    init() {
        if UserDefaults.standard.object(forKey: "com.quicknotes.showTitlePreviewWhileLocked") != nil {
            showTitlePreviewWhileLocked = UserDefaults.standard.bool(forKey: "com.quicknotes.showTitlePreviewWhileLocked")
        }
        if let raw = UserDefaults.standard.string(forKey: "com.quicknotes.noteFontSize"),
           let size = NoteFontSize(rawValue: raw) {
            noteFontSize = size
        }
        if let raw = UserDefaults.standard.string(forKey: "com.quicknotes.autoRelockDelay"),
           let delay = AutoRelockDelay(rawValue: raw) {
            autoRelockDelay = delay
        }
        if UserDefaults.standard.object(forKey: "com.quicknotes.globalHotkeyEnabled") != nil {
            globalHotkeyEnabled = UserDefaults.standard.bool(forKey: "com.quicknotes.globalHotkeyEnabled")
        }
        // Touch ID is shelved as a future feature (see SettingsView.swift) — deliberately
        // not restoring any previously-saved `true` value here, so it stays off even for
        // an install that had it enabled before this was shelved.
        if UserDefaults.standard.object(forKey: "com.quicknotes.checkForUpdatesEnabled") != nil {
            checkForUpdatesEnabled = UserDefaults.standard.bool(forKey: "com.quicknotes.checkForUpdatesEnabled")
        }
        if UserDefaults.standard.object(forKey: "com.quicknotes.versionHistoryEnabled") != nil {
            versionHistoryEnabled = UserDefaults.standard.bool(forKey: "com.quicknotes.versionHistoryEnabled")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            print("Launch at login error: \(error)")
        }
    }

    /// Checks GitHub's latest release once and, if it's newer than this build,
    /// asks the user whether to open that release page in the browser — a
    /// browser window just appearing out of nowhere with no explanation was
    /// confusing, so this is a real prompt, not a silent redirect.
    func checkForUpdates() {
        guard checkForUpdatesEnabled else { return }
        guard let url = URL(string: "https://api.github.com/repos/BrianB-22/quicknotes/releases/latest") else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String,
                  let htmlString = json["html_url"] as? String,
                  let releaseURL = URL(string: htmlString) else { return }
            let remote = tag.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
            guard Self.isNewer(remote, than: current) else { return }
            DispatchQueue.main.async {
                Self.promptToDownload(version: remote, url: releaseURL)
            }
        }.resume()
    }

    private static func promptToDownload(version: String, url: URL) {
        // An accessory (menu-bar-only) app isn't guaranteed to be frontmost
        // just because a background network check completed — without this,
        // the alert can appear behind other windows or fail to take focus.
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "A New Version is Available"
        alert.informativeText = "QuickNotes \(version) is available. Would you like to download it?"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Not Now")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(url)
        }
    }

    private static func isNewer(_ remote: String, than current: String) -> Bool {
        // Takes each component's leading numeric prefix rather than dropping
        // non-numeric components outright (`Int("2-beta")` is nil) — dropping
        // desyncs positional comparison against the other version entirely,
        // instead of just treating the suffix as insignificant.
        func components(_ version: String) -> [Int] {
            version.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        }
        let r = components(remote)
        let c = components(current)
        for i in 0..<max(r.count, c.count) {
            let rv = i < r.count ? r[i] : 0
            let cv = i < c.count ? c[i] : 0
            if rv != cv { return rv > cv }
        }
        return false
    }
}
