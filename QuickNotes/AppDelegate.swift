import AppKit
import SwiftUI
import Combine
import Carbon

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    let settings = SettingsStore()
    lazy var noteStore = NoteStore(settings: settings)
    private let hotkeyManager = HotkeyManager()
    private var cancellables = Set<AnyCancellable>()
    private var outsideClickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBarItem()
        setupPopover()

        hotkeyManager.onActivate = { [weak self] in self?.togglePopoverFromHotkey() }
        applyGlobalHotkey(enabled: settings.globalHotkeyEnabled)
        // @Published fires on willSet, so settings.globalHotkeyEnabled isn't
        // written yet when this runs — use the value the publisher hands us.
        settings.$globalHotkeyEnabled
            .dropFirst()
            .sink { [weak self] enabled in self?.applyGlobalHotkey(enabled: enabled) }
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
        if popover.isShown { popover.performClose(button) }
        else { showPopover(from: button) }
    }

    private func showPopover(from button: NSStatusBarButton) {
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
