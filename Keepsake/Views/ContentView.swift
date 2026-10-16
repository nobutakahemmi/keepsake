import SwiftUI

struct ContentView: View {
    @ObservedObject var library: LibraryStore
    @StateObject private var recorder = Recorder()

    var body: some View {
        TabView {
            RecordView(recorder: recorder, library: library)
                .tabItem {
                    Label("Record", systemImage: "record.circle")
                }
            ClipsView(library: library)
                .tabItem {
                    Label("Clips", systemImage: "film")
                }
            TapesView(library: library)
                .tabItem {
                    Label("Tapes", systemImage: "rectangle.stack")
                }
        }
        .onOpenURL { url in
            Task {
                do {
                    try await library.importVideo(from: url)
                } catch {
                    library.notice = error.localizedDescription
                }
            }
        }
        .alert(
            "Keepsake",
            isPresented: Binding(
                get: { library.notice != nil },
                set: { if !$0 { library.notice = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(library.notice ?? "")
        }
    }
}
