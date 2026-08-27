import Foundation
import SwiftUI
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
        if UserDefaults.standard.object(forKey: "com.quicknotes.useTouchIDForLockedNotes") != nil {
            useTouchIDForLockedNotes = UserDefaults.standard.bool(forKey: "com.quicknotes.useTouchIDForLockedNotes")
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
}
