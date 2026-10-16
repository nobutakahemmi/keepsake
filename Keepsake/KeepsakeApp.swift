import SwiftUI

@main
struct KeepsakeApp: App {
    @StateObject private var library = LibraryStore()

    var body: some Scene {
        WindowGroup {
            ContentView(library: library)
        }
    }
}
