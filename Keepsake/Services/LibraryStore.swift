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

    init() {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        clipsDirectory = documents.appendingPathComponent("Clips", isDirectory: true)
        tapesDirectory = documents.appendingPathComponent("Tapes", isDirectory: true)
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        indexURL = support.appendingPathComponent("library.json")
        prepareFolders()
        load()
    }

    func clipURL(_ clip: ClipRecord) -> URL {
        clipsDirectory.appendingPathComponent(clip.fileName)
    }

    func tapeURL(_ tape: TapeRecord) -> URL {
        tapesDirectory.appendingPathComponent(tape.fileName)
    }

    func addRecording(_ recorded: RecordedClip) throws {
        let destination = try place(recorded.url, in: clipsDirectory)
        try? FileManager.default.removeItem(at: ClipMetadata.sidecarURL(for: recorded.url))
        try ClipMetadata.writeSidecar(start: recorded.start, displayName: recorded.displayName, beside: destination)
        let record = ClipRecord(
            id: UUID(),
            displayName: recorded.displayName,
            startMilliseconds: TimestampCodec.milliseconds(from: recorded.start),
            durationMilliseconds: Int64((max(0, recorded.duration) * 1000).rounded()),
            fileName: destination.lastPathComponent,
            imported: false,
            startTimeSource: .keepsakeMetadata
        )
        clips.append(record)
        sortClips()
        save()
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
        try? ClipMetadata.writeSidecar(start: start, displayName: displayName, beside: destination)
        let record = ClipRecord(
            id: UUID(),
            displayName: displayName,
            startMilliseconds: TimestampCodec.milliseconds(from: start),
            durationMilliseconds: duration,
            fileName: destination.lastPathComponent,
            imported: true,
            startTimeSource: sourceKind
        )
        clips.append(record)
        sortClips()
        save()
        notice = "Imported \(displayName)."
    }

    func renameClip(_ clip: ClipRecord, to newName: String) {
        guard let index = clips.firstIndex(where: { $0.id == clip.id }) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        clips[index].displayName = trimmed
        try? ClipMetadata.writeSidecar(
            start: clips[index].startDate,
            displayName: trimmed,
            beside: clipURL(clips[index])
        )
        save()
    }

    func deleteClip(_ clip: ClipRecord) {
        let url = clipURL(clip)
        try? fileManager.removeItem(at: url)
        try? fileManager.removeItem(at: ClipMetadata.sidecarURL(for: url))
        clips.removeAll { $0.id == clip.id }
        save()
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
        save()
        return record
    }

    func deleteTape(_ tape: TapeRecord) {
        try? fileManager.removeItem(at: tapeURL(tape))
        tapes.removeAll { $0.id == tape.id }
        save()
    }

    private func prepareFolders() {
        try? fileManager.createDirectory(at: clipsDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: tapesDirectory, withIntermediateDirectories: true)
        let support = indexURL.deletingLastPathComponent()
        try? fileManager.createDirectory(at: support, withIntermediateDirectories: true)
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
    }

    private func save() {
        let index = LibraryIndex(clips: clips, tapes: tapes)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(index) else { return }
        try? data.write(to: indexURL, options: .atomic)
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
