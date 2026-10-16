import SwiftUI

struct TapesView: View {
    @ObservedObject var library: LibraryStore
    @State private var shareItem: ShareURL?
    @State private var pendingDelete: TapeRecord?

    var body: some View {
        NavigationStack {
            Group {
                if library.tapes.isEmpty {
                    ContentUnavailableView {
                        Label("No tapes yet", systemImage: "rectangle.stack")
                    } description: {
                        Text("A tape is the finished video made from two clips. Make one from the Clips tab.")
                    }
                } else {
                    List {
                        ForEach(library.tapes) { tape in
                            tapeRow(tape)
                        }
                    }
                }
            }
            .navigationTitle("Tapes")
            .sheet(item: $shareItem) { item in
                ShareSheet(url: item.url)
            }
            .confirmationDialog(
                "Delete this tape?",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let pendingDelete {
                        library.deleteTape(pendingDelete)
                    }
                    pendingDelete = nil
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the video from this iPhone.")
            }
        }
    }

    private func tapeRow(_ tape: TapeRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                ThumbnailView(url: library.tapeURL(tape))
                VStack(alignment: .leading, spacing: 4) {
                    Text(tape.title)
                        .font(.headline)
                    Text(TimeFormat.dayAndTime(tape.date))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(tape.layout.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: 16) {
                NavigationLink("Play") {
                    TapePlayerView(url: library.tapeURL(tape), title: tape.title)
                }
                .accessibilityLabel("Play \(tape.title)")

                Button("Share") {
                    shareItem = ShareURL(url: library.tapeURL(tape))
                }
                .accessibilityLabel("Share \(tape.title)")

                Button("Delete", role: .destructive) {
                    pendingDelete = tape
                }
                .accessibilityLabel("Delete \(tape.title)")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}
