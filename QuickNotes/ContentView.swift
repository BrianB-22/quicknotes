import SwiftUI

struct ContentView: View {
    @EnvironmentObject var noteStore: NoteStore
    @EnvironmentObject var settings: SettingsStore
    @State private var showingSettings = false

    var body: some View {
        HSplitView {
            NoteListView(showingSettings: $showingSettings)
                .frame(minWidth: 200, idealWidth: 220, maxWidth: 300)
            NoteDetailView()
                .frame(minWidth: 340)
        }
        .frame(width: 640, height: 480)
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }
}
