import AppKit
import SwiftUI
import Combine
import Carbon

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var detachedWindow: NSWindow?
    let settings = SettingsStore()
    lazy var noteStore = NoteStore(settings: settings)
    private let hotkeyManager = HotkeyManager()
    private var cancellables = Set<AnyCancellable>()
    private var outsideClickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBarItem()
        setupPopover()

        NotificationCenter.default.addObserver(
            forName: .quickNotesDetach, object: nil, queue: .main
        ) { [weak self] _ in
            self?.openDetachedWindow()
        }

        hotkeyManager.onActivate = { [weak self] in self?.togglePopoverFromHotkey() }
        applyGlobalHotkey(enabled: settings.globalHotkeyEnabled)
        // @Published fires on willSet, so settings.globalHotkeyEnabled isn't
        // written yet when this runs — use the value the publisher hands us.
        settings.$globalHotkeyEnabled
            .dropFirst()
            .sink { [weak self] enabled in self?.applyGlobalHotkey(enabled: enabled) }
            .store(in: &cancellables)

        // Turning Touch ID off shouldn't leave previously saved passcodes
        // sitting in the Keychain indefinitely with no way for the user to
        // know they're still there.
        settings.$useTouchIDForLockedNotes
            .dropFirst()
            .sink { [weak self] enabled in
                if !enabled { self?.noteStore.wipeAllSavedTouchIDPasscodes() }
            }
            .store(in: &cancellables)

        settings.checkForUpdates()
    }

    // MARK: - Setup

    private func setupMenuBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "QuickNotes")
        button.action = #selector(togglePopover(_:))
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 640, height: 480)
        // `.transient` closes the instant the user clicks anywhere outside the
        // popover — including the mouseDown that starts dragging a file out of
        // Finder to drop it in a note. Managing this ourselves lets a drop that
        // lands back inside our own window survive.
        popover.behavior = .applicationDefined
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: ContentView()
                .environmentObject(settings)
                .environmentObject(noteStore)
        )

        // A mouseUp on another app's window only fires here (global monitors
        // never see events on our own app's windows), so a drag-and-drop that's
        // released over our popover doesn't trigger this at all — only a click
        // that actually lands elsewhere does.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp, .rightMouseUp]) { [weak self] _ in
            guard let self, self.popover.isShown else { return }
            self.popover.performClose(nil)
        }
    }

    // MARK: - Hotkey

    private func applyGlobalHotkey(enabled: Bool) {
        if enabled {
            hotkeyManager.register(keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(optionKey), id: 1)
        } else {
            hotkeyManager.unregister()
        }
    }

    private func togglePopoverFromHotkey() {
        if closeDetachedWindowIfOpen(), let button = statusItem.button {
            showPopover(from: button)
            return
        }
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            showPopover(from: button)
        }
    }

    // MARK: - Actions

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp { showContextMenu(); return }
        guard let button = statusItem.button else { return }
        if closeDetachedWindowIfOpen() {
            showPopover(from: button)
            return
        }
        if popover.isShown { popover.performClose(button) }
        else { showPopover(from: button) }
    }

    // MARK: - Detached window

    /// The menu bar icon is meant to always be a reliable way back, even if the
    /// detached window got lost behind other windows, minimized, or pushed to
    /// another Space — "bring it forward" isn't guaranteed to be visible or
    /// obvious when that happens. Closing it and reopening the familiar
    /// anchored popover instead loses nothing: it's the same `NoteStore`
    /// underneath either way, so the same note/selection is still right there.
    @discardableResult
    private func closeDetachedWindowIfOpen() -> Bool {
        guard let window = detachedWindow else { return false }
        window.close()
        return true
    }

    private func openDetachedWindow() {
        popover.performClose(nil)

        if let window = detachedWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "QuickNotes"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: ContentView(isDetached: true)
                .environmentObject(settings)
                .environmentObject(noteStore)
        )
        window.setFrameAutosaveName("QuickNotesDetachedWindow")
        if window.frame.origin == .zero {
            // No autosaved position yet (first time detaching) — center it.
            window.center()
        }

        detachedWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === detachedWindow else { return }
        detachedWindow = nil
        // Same "no QuickNotes surface is visible anymore" bookkeeping the
        // popover does on close — checkpoint, relock, force any stuck sheet
        // closed (see NoteStore.popoverCloseTick).
        noteStore.popoverDidClose()
    }

    private func showPopover(from button: NSStatusBarButton) {
        // An LSUIElement (accessory) app isn't the frontmost app just because
        // its status-item button was clicked — that action fires independent
        // of app activation, which is why the icon reliably toggles the
        // popover open/closed even when this is skipped. But without actually
        // activating the app, the popover's own content view hierarchy isn't
        // guaranteed to be the one receiving real mouse events: it can show
        // fully rendered yet silently swallow every click until something
        // (e.g. relaunching) forces activation. `.makeKey()` alone isn't
        // enough — it makes the window key within our app, but doesn't make
        // our app the active one at the WindowServer level.
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func popoverDidClose(_ notification: Notification) {
        noteStore.popoverDidClose()
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Paste Clipboard as New Note", action: #selector(pasteClipboardAsNewNote), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "About QuickNotes", action: #selector(showAbout), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit QuickNotes", action: #selector(quitApp), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func pasteClipboardAsNewNote() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        noteStore.createNote(text: text)
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [:])
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

extension Notification.Name {
    static let quickNotesDetach = Notification.Name("com.quicknotes.detach")
}
