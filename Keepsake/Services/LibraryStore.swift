import Foundation

struct LibraryIndex: Codable, Equatable {
    var clips: [ClipRecord]
    var tapes: [TapeRecord]
}

enum LibraryError: LocalizedError {
    case unreadable
    case copyFailed

    var errorDescription: String? {
        switch self {
        case .unreadable:
            return "Keepsake could not open that video."
        case .copyFailed:
            return "Keepsake could not copy that video onto this iPhone."
        }
    }
}

/// Saves clips and finished tapes on this iPhone. Nothing is uploaded.
@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var clips: [ClipRecord] = []
    @Published private(set) var tapes: [TapeRecord] = []
    @Published var notice: String?

    private let fileManager = FileManager.default
    private let clipsDirectory: URL
    private let tapesDirectory: URL
    private let indexURL: URL

    convenience init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.init(
            clipsDirectory: documents.appendingPathComponent("Clips", isDirectory: true),
            tapesDirectory: documents.appendingPathComponent("Tapes", isDirectory: true),
            indexURL: support.appendingPathComponent("library.json")
        )
    }

    /// `storageRoot` keeps clips, tapes, and the index together. Tests use a temporary folder.
    convenience init(storageRoot: URL) {
        self.init(
            clipsDirectory: storageRoot.appendingPathComponent("Clips", isDirectory: true),
            tapesDirectory: storageRoot.appendingPathComponent("Tapes", isDirectory: true),
            indexURL: storageRoot.appendingPathComponent("library.json")
        )
    }

    private init(clipsDirectory: URL, tapesDirectory: URL, indexURL: URL) {
        self.clipsDirectory = clipsDirectory
        self.tapesDirectory = tapesDirectory
        self.indexURL = indexURL
        prepareFolders()
        load()
        reconcile()
    }

    func clipURL(_ clip: ClipRecord) -> URL {
        clipsDirectory.appendingPathComponent(clip.fileName)
    }

    func tapeURL(_ tape: TapeRecord) -> URL {
        tapesDirectory.appendingPathComponent(tape.fileName)
    }

    func addRecording(_ recorded: RecordedClip) throws {
        let destination = try place(recorded.url, in: clipsDirectory)
        let durationMilliseconds = Int64((max(0, recorded.duration) * 1000).rounded())
        do {
            try? fileManager.removeItem(at: ClipMetadata.sidecarURL(for: recorded.url))
            try ClipMetadata.writeSidecar(
                start: recorded.start,
                displayName: recorded.displayName,
                beside: destination,
                durationMilliseconds: durationMilliseconds,
                metadataEmbedded: recorded.metadataEmbedded
            )
            excludeFromBackup(destination)
        } catch {
            try? fileManager.removeItem(at: destination)
            try? fileManager.removeItem(at: ClipMetadata.sidecarURL(for: destination))
            throw LibraryError.copyFailed
        }
        let record = ClipRecord(
            id: UUID(),
            displayName: recorded.displayName,
            startMilliseconds: TimestampCodec.milliseconds(from: recorded.start),
            durationMilliseconds: durationMilliseconds,
            fileName: destination.lastPathComponent,
            imported: false,
            startTimeSource: recorded.metadataEmbedded ? .keepsakeMetadata : .sidecar,
            metadataEmbedded: recorded.metadataEmbedded
        )
        clips.append(record)
        sortClips()
        persist()
    }

    func importVideo(from source: URL) async throws {
        let accessed = source.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                source.stopAccessingSecurityScopedResource()
            }
        }
        let destination = try copyInto(source, directory: clipsDirectory)
        let payload = await ClipMetadata.read(from: destination)
        let duration = await ClipMetadata.durationMilliseconds(of: destination)
        guard duration > 0 else {
            try? fileManager.removeItem(at: destination)
            try? fileManager.removeItem(at: ClipMetadata.sidecarURL(for: destination))
            throw LibraryError.unreadable
        }
        let trimmedName = payload.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fallback = source.deletingPathExtension().lastPathComponent
        let displayName = trimmedName.isEmpty ? (fallback.isEmpty ? "Imported clip" : fallback) : trimmedName
        let start: Date
        let sourceKind: StartTimeSource
        if let found = payload.start {
            start = found
            sourceKind = payload.source
        } else {
            start = Date()
            sourceKind = .importedAt
        }
        var metadataEmbedded = sourceKind == .keepsakeMetadata
        if !metadataEmbedded {
            do {
                try await ClipMetadata.embedInPlace(
                    url: destination,
                    start: start,
                    displayName: displayName,
                    durationMilliseconds: duration
                )
                metadataEmbedded = true
            } catch {
                metadataEmbedded = false
            }
        }
        do {
            try ClipMetadata.writeSidecar(
                start: start,
                displayName: displayName,
                beside: destination,
                durationMilliseconds: duration,
                metadataEmbedded: metadataEmbedded
            )
        } catch {
            try? fileManager.removeItem(at: destination)
            try? fileManager.removeItem(at: ClipMetadata.sidecarURL(for: destination))
            throw LibraryError.copyFailed
        }
        excludeFromBackup(destination)
        let record = ClipRecord(
            id: UUID(),
            displayName: displayName,
            startMilliseconds: TimestampCodec.milliseconds(from: start),
            durationMilliseconds: duration,
            fileName: destination.lastPathComponent,
            imported: true,
            startTimeSource: sourceKind,
            metadataEmbedded: metadataEmbedded
        )
        clips.append(record)
        sortClips()
        guard persist() else { return }
        if metadataEmbedded {
            notice = "Imported \(displayName)."
        } else {
            notice = "Imported \(displayName). The start time is not in the video yet, so Share stays off until you tap Repair."
        }
    }

    func renameClip(_ clip: ClipRecord, to newName: String) {
        guard let index = clips.firstIndex(where: { $0.id == clip.id }) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        clips[index].displayName = trimmed
        let updated = clips[index]
        do {
            try ClipMetadata.writeSidecar(
                start: updated.startDate,
                displayName: trimmed,
                beside: clipURL(updated),
                durationMilliseconds: updated.durationMilliseconds,
                metadataEmbedded: updated.metadataEmbedded
            )
        } catch {
            notice = "The name changed in the list, but Keepsake could not update the file beside it."
        }
        persist()
        guard updated.metadataEmbedded else { return }
        let clipID = updated.id
        Task {
            do {
                try await ClipMetadata.embedInPlace(
                    url: clipURL(updated),
                    start: updated.startDate,
                    displayName: trimmed,
                    durationMilliseconds: updated.durationMilliseconds
                )
            } catch {
                if let failedIndex = clips.firstIndex(where: { $0.id == clipID }) {
                    clips[failedIndex].metadataEmbedded = false
                    persist()
                }
                notice = "The name was updated, but it could not be stored in the video. Share stays off until you tap Repair."
            }
        }
    }

    func repairMetadata(_ clip: ClipRecord) async {
        guard let index = clips.firstIndex(where: { $0.id == clip.id }) else { return }
        let current = clips[index]
        do {
            try await ClipMetadata.embedInPlace(
                url: clipURL(current),
                start: current.startDate,
                displayName: current.displayName,
                durationMilliseconds: current.durationMilliseconds
            )
            if let repaired = clips.firstIndex(where: { $0.id == current.id }) {
                clips[repaired].metadataEmbedded = true
                if clips[repaired].startTimeSource == .sidecar {
                    clips[repaired].startTimeSource = .keepsakeMetadata
                }
                persist()
            }
            notice = "Start time saved in the video. You can share it now."
        } catch {
            notice = error.localizedDescription
        }
    }

    func deleteClip(_ clip: ClipRecord) {
        let url = clipURL(clip)
        try? fileManager.removeItem(at: url)
        try? fileManager.removeItem(at: ClipMetadata.sidecarURL(for: url))
        clips.removeAll { $0.id == clip.id }
        persist()
    }

    func addTape(
        from source: URL,
        nameA: String,
        nameB: String,
        originMilliseconds: Int64,
        layout: LayoutKind,
        nudgeMilliseconds: Int64,
        includesTitleCard: Bool
    ) throws -> TapeRecord {
        let destination = try place(source, in: tapesDirectory)
        let record = TapeRecord(
            id: UUID(),
            nameA: nameA,
            nameB: nameB,
            originMilliseconds: originMilliseconds,
            fileName: destination.lastPathComponent,
            layout: layout,
            nudgeMilliseconds: nudgeMilliseconds,
            includesTitleCard: includesTitleCard
        )
        tapes.insert(record, at: 0)
        excludeFromBackup(destination)
        persist()
        return record
    }

    func deleteTape(_ tape: TapeRecord) {
        try? fileManager.removeItem(at: tapeURL(tape))
        tapes.removeAll { $0.id == tape.id }
        persist()
    }

    private func prepareFolders() {
        try? fileManager.createDirectory(at: clipsDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: tapesDirectory, withIntermediateDirectories: true)
        let support = indexURL.deletingLastPathComponent()
        try? fileManager.createDirectory(at: support, withIntermediateDirectories: true)
        excludeFromBackup(clipsDirectory)
        excludeFromBackup(tapesDirectory)
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let index = try? JSONDecoder().decode(LibraryIndex.self, from: data) else {
            return
        }
        clips = index.clips
        tapes = index.tapes
        sortClips()
        tapes.sort { $0.originMilliseconds > $1.originMilliseconds }
        excludeStoredFiles()
    }

    @discardableResult
    private func persist() -> Bool {
        do {
            try save()
            return true
        } catch {
            notice = "Keepsake could not update its library list. The videos are still on this iPhone."
            return false
        }
    }

    private func save() throws {
        let index = LibraryIndex(clips: clips, tapes: tapes)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(index)
        try data.write(to: indexURL, options: .atomic)
    }

    /// Drops missing files and restores clips that have a sidecar but no library row.
    private func reconcile() {
        var changed = false
        clips.removeAll { clip in
            let missing = !fileManager.fileExists(atPath: clipURL(clip).path)
            if missing { changed = true }
            return missing
        }
        let knownClips = Set(clips.map(\.fileName))
        for url in mediaFiles(in: clipsDirectory) where !knownClips.contains(url.lastPathComponent) {
            guard let sidecar = ClipMetadata.readSidecar(beside: url) else { continue }
            let name = sidecar.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            clips.append(
                ClipRecord(
                    id: UUID(),
                    displayName: name.isEmpty ? "Recovered clip" : name,
                    startMilliseconds: sidecar.startTimestampMilliseconds,
                    durationMilliseconds: sidecar.durationMilliseconds ?? 0,
                    fileName: url.lastPathComponent,
                    imported: true,
                    startTimeSource: .sidecar,
                    metadataEmbedded: sidecar.metadataEmbedded ?? false
                )
            )
            changed = true
        }
        let tapeCount = tapes.count
        tapes.removeAll { !fileManager.fileExists(atPath: tapeURL($0).path) }
        if tapes.count != tapeCount { changed = true }
        if changed {
            sortClips()
            try? save()
        }
        excludeStoredFiles()
    }

    private func mediaFiles(in directory: URL) -> [URL] {
        let allowed = Set(["mov", "mp4", "m4v"])
        let urls = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { allowed.contains($0.pathExtension.lowercased()) }
    }

    private func excludeStoredFiles() {
        for clip in clips {
            excludeFromBackup(clipURL(clip))
        }
        for tape in tapes {
            excludeFromBackup(tapeURL(tape))
        }
    }

    private func excludeFromBackup(_ url: URL) {
        var target = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? target.setResourceValues(values)
    }

    private func sortClips() {
        clips.sort { $0.startMilliseconds > $1.startMilliseconds }
    }

    private func copyInto(_ source: URL, directory: URL) throws -> URL {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let ext = source.pathExtension.isEmpty ? "mov" : source.pathExtension
        let destination = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
        do {
            try fileManager.copyItem(at: source, to: destination)
        } catch {
            throw LibraryError.copyFailed
        }
        return destination
    }

    private func place(_ source: URL, in directory: URL) throws -> URL {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let ext = source.pathExtension.isEmpty ? "mov" : source.pathExtension
        let destination = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
        do {
            try fileManager.moveItem(at: source, to: destination)
        } catch {
            do {
                try fileManager.copyItem(at: source, to: destination)
                try? fileManager.removeItem(at: source)
            } catch {
                throw LibraryError.copyFailed
            }
        }
        return destination
    }
}
