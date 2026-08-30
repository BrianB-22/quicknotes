import SwiftUI

struct ContentView: View {
    @EnvironmentObject var noteStore: NoteStore
    @EnvironmentObject var settings: SettingsStore
    @State private var showingSettings = false
    var isDetached: Bool = false

    var body: some View {
        HSplitView {
            NoteListView(showingSettings: $showingSettings, isDetached: isDetached)
                .frame(minWidth: 200, idealWidth: 220, maxWidth: isDetached ? .infinity : 300)
            NoteDetailView()
                .frame(minWidth: 340)
        }
        .frame(
            minWidth: isDetached ? 560 : 640, idealWidth: 640, maxWidth: isDetached ? .infinity : 640,
            minHeight: isDetached ? 360 : 480, idealHeight: 480, maxHeight: isDetached ? .infinity : 480
        )
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        // See NoteStore.popoverCloseTick: force any sheet still marked
        // "presented" closed if the popover itself was just force-closed
        // (e.g. tray-icon click) without going through this sheet's own
        // dismiss action first.
        .onChange(of: noteStore.popoverCloseTick) { _, _ in
            showingSettings = false
        }
    }
}
