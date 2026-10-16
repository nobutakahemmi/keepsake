import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ClipsView: View {
    @ObservedObject var library: LibraryStore
    @State private var showImporter = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showSync = false
    @State private var shareItem: ShareURL?
    @State private var renameTarget: ClipRecord?
    @State private var pendingDelete: ClipRecord?

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                VStack(spacing: 8) {
                    Button("Import from Files") {
                        showImporter = true
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                    .accessibilityHint("Choose a video that was AirDropped to this iPhone.")

                    PhotosPicker(selection: $photoItem, matching: .videos) {
                        Text("Import from Photos")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Import a video from Photos")
                }
                .padding(.horizontal)

                if library.clips.isEmpty {
                    ContentUnavailableView {
                        Label("No clips yet", systemImage: "film")
                    } description: {
                        Text("Record on the Record tab, or import a video from the other iPhone.")
                    }
                } else {
                    List {
                        Section {
                            ForEach(library.clips) { clip in
                                clipRow(clip)
                            }
                        } footer: {
                            Text("To add the other phone’s video, open that clip, tap Share, and AirDrop it here. Then import it from Files.")
                        }
                    }
                }
            }
            .navigationTitle("Clips")
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    if library.clips.count < 2 {
                        Text("You need two clips to make a keepsake.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    Button("Make a Keepsake") {
                        showSync = true
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(library.clips.count < 2)
                    .frame(maxWidth: .infinity)
                    .accessibilityHint("Lines up two clips and saves a side-by-side video.")
                }
                .padding()
                .background(.bar)
            }
            .navigationDestination(isPresented: $showSync) {
                SyncStitchView(library: library)
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    Task { await importFile(url) }
                case .failure(let error):
                    library.notice = error.localizedDescription
                }
            }
            .onChange(of: photoItem) { _, newValue in
                guard let newValue else { return }
                Task {
                    await importPhoto(newValue)
                    photoItem = nil
                }
            }
            .sheet(item: $shareItem) { item in
                ShareSheet(url: item.url)
            }
            .sheet(item: $renameTarget) { clip in
                RenameClipSheet(initialName: clip.displayName) { newName in
                    library.renameClip(clip, to: newName)
                }
            }
            .confirmationDialog(
                "Delete this clip?",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let pendingDelete {
                        library.deleteClip(pendingDelete)
                    }
                    pendingDelete = nil
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the video from this iPhone.")
            }
        }
    }

    private func clipRow(_ clip: ClipRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(clip.displayName)
                    .font(.headline)
                Text(TimeFormat.dateTime(milliseconds: clip.startMilliseconds))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Length \(TimeFormat.clock(clip.duration))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if clip.startTimeSource == .importedAt {
                    Text("Start time was not in the file. Sync will use the time you imported it.")
                        .font(.footnote)
                }
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: 16) {
                Button("Share") {
                    shareItem = ShareURL(url: library.clipURL(clip))
                }
                .accessibilityLabel("Share \(clip.displayName)")
                .accessibilityHint("AirDrop this video to the other iPhone.")

                Button("Rename") {
                    renameTarget = clip
                }
                .accessibilityLabel("Rename \(clip.displayName)")

                Button("Delete", role: .destructive) {
                    pendingDelete = clip
                }
                .accessibilityLabel("Delete \(clip.displayName)")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    private func importFile(_ url: URL) async {
        do {
            try await library.importVideo(from: url)
        } catch {
            library.notice = error.localizedDescription
        }
    }

    private func importPhoto(_ item: PhotosPickerItem) async {
        do {
            guard let video = try await item.loadTransferable(type: ImportedVideo.self) else {
                library.notice = LibraryError.unreadable.localizedDescription
                return
            }
            defer { try? FileManager.default.removeItem(at: video.url) }
            try await library.importVideo(from: video.url)
        } catch {
            library.notice = error.localizedDescription
        }
    }
}

private struct RenameClipSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    let onSave: (String) -> Void

    init(initialName: String, onSave: @escaping (String) -> Void) {
        _name = State(initialValue: initialName)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.words)
                    .accessibilityLabel("Clip name")
            }
            .navigationTitle("Rename")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(name)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct ImportedVideo: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(ext)
            try FileManager.default.copyItem(at: received.file, to: destination)
            return ImportedVideo(url: destination)
        }
    }
}
