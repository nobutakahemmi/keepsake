import AVFoundation
import Foundation

struct ClipSidecar: Codable, Equatable {
    var startTimestampMilliseconds: Int64
    var displayName: String
}

enum ClipMetadataError: LocalizedError {
    case exportUnavailable
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .exportUnavailable:
            return "Could not save the recording's start time."
        case .exportFailed(let message):
            return message
        }
    }
}

/// Reads and writes the wall-clock start time and display name stored in a clip.
enum ClipMetadata {
    static let startIdentifier = AVMetadataIdentifier(rawValue: "mdta/com.keepsake.startTimestamp")
    static let nameIdentifier = AVMetadataIdentifier(rawValue: "mdta/com.keepsake.displayName")

    struct Payload {
        var start: Date?
        var displayName: String?
        var source: StartTimeSource
    }

    static func sidecarURL(for mediaURL: URL) -> URL {
        mediaURL.appendingPathExtension("json")
    }

    static func items(start: Date, displayName: String) -> [AVMetadataItem] {
        let milliseconds = TimestampCodec.milliseconds(from: start)
        let iso = TimestampCodec.iso8601(from: start)

        let startItem = AVMutableMetadataItem()
        startItem.identifier = startIdentifier
        startItem.dataType = kCMMetadataBaseDataType_UTF8 as String
        startItem.value = String(milliseconds) as NSString

        let nameItem = AVMutableMetadataItem()
        nameItem.identifier = nameIdentifier
        nameItem.dataType = kCMMetadataBaseDataType_UTF8 as String
        nameItem.value = displayName as NSString

        let titleItem = AVMutableMetadataItem()
        titleItem.identifier = .commonIdentifierTitle
        titleItem.value = displayName as NSString

        let creationItem = AVMutableMetadataItem()
        creationItem.identifier = .commonIdentifierCreationDate
        creationItem.value = iso as NSString

        let quickTimeCreation = AVMutableMetadataItem()
        quickTimeCreation.identifier = .quickTimeMetadataCreationDate
        quickTimeCreation.value = iso as NSString

        return [startItem, nameItem, titleItem, creationItem, quickTimeCreation]
    }

    static func writeSidecar(start: Date, displayName: String, beside mediaURL: URL) throws {
        let sidecar = ClipSidecar(
            startTimestampMilliseconds: TimestampCodec.milliseconds(from: start),
            displayName: displayName
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(sidecar)
        try data.write(to: sidecarURL(for: mediaURL), options: .atomic)
    }

    static func readSidecar(beside mediaURL: URL) -> ClipSidecar? {
        let url = sidecarURL(for: mediaURL)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ClipSidecar.self, from: data)
    }

    /// Copies `source` to a new movie and stores the start time and name inside it.
    static func embed(source: URL, start: Date, displayName: String) async throws -> URL {
        let asset = AVURLAsset(url: source, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw ClipMetadataError.exportUnavailable
        }
        let fileType: AVFileType = session.supportedFileTypes.contains(.mov) ? .mov : .mp4
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileType == .mov ? "mov" : "mp4")
        session.outputURL = destination
        session.outputFileType = fileType
        session.metadata = items(start: start, displayName: displayName)
        do {
            try await ExportSessionRunner.run(session)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw ClipMetadataError.exportFailed(error.localizedDescription)
        }
        try writeSidecar(start: start, displayName: displayName, beside: destination)
        return destination
    }

    static func read(from url: URL) async -> Payload {
        var payload = Payload(start: nil, displayName: nil, source: .importedAt)
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])

        if let metadata = try? await asset.load(.metadata) {
            for item in metadata {
                guard let identifier = try? await item.load(.identifier) else { continue }
                let stringValue = try? await item.load(.stringValue)
                if matches(identifier, startIdentifier) {
                    if let stringValue, let date = TimestampCodec.date(fromStored: stringValue) {
                        payload.start = date
                        payload.source = .keepsakeMetadata
                    }
                } else if matches(identifier, nameIdentifier) {
                    if let stringValue, !stringValue.isEmpty {
                        payload.displayName = stringValue
                    }
                } else if payload.start == nil && isCreationIdentifier(identifier) {
                    if let date = try? await item.load(.dateValue) {
                        payload.start = date
                        payload.source = .creationDate
                    } else if let stringValue, let date = TimestampCodec.date(fromStored: stringValue) {
                        payload.start = date
                        payload.source = .creationDate
                    }
                } else if payload.displayName == nil && identifier == .commonIdentifierTitle {
                    if let stringValue, !stringValue.isEmpty {
                        payload.displayName = stringValue
                    }
                }
            }
        }

        if payload.source != .keepsakeMetadata, let sidecar = readSidecar(beside: url) {
            payload.start = TimestampCodec.date(fromMilliseconds: sidecar.startTimestampMilliseconds)
            payload.source = .sidecar
            if payload.displayName == nil, !sidecar.displayName.isEmpty {
                payload.displayName = sidecar.displayName
            }
        }

        if payload.start == nil {
            if let creation = try? await asset.load(.creationDate),
               let date = try? await creation.load(.dateValue) {
                payload.start = date
                payload.source = .creationDate
            }
        }

        if payload.start == nil {
            let values = try? url.resourceValues(forKeys: [.creationDateKey])
            if let date = values?.creationDate {
                payload.start = date
                payload.source = .creationDate
            }
        }

        return payload
    }

    static func durationMilliseconds(of url: URL) async -> Int64 {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        guard let tracks = try? await asset.loadTracks(withMediaType: .video),
              let track = tracks.first,
              let range = try? await track.load(.timeRange) else {
            if let duration = try? await asset.load(.duration) {
                return Sync.milliseconds(duration)
            }
            return 0
        }
        return Sync.milliseconds(range.duration)
    }

    private static func matches(_ identifier: AVMetadataIdentifier, _ expected: AVMetadataIdentifier) -> Bool {
        identifier == expected || identifier.rawValue == expected.rawValue
    }

    private static func isCreationIdentifier(_ identifier: AVMetadataIdentifier) -> Bool {
        identifier == .commonIdentifierCreationDate || identifier == .quickTimeMetadataCreationDate
    }
}

enum ExportSessionRunner {
    static func run(_ session: AVAssetExportSession) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            session.exportAsynchronously {
                switch session.status {
                case .completed:
                    continuation.resume()
                case .cancelled:
                    continuation.resume(throwing: ClipMetadataError.exportFailed("Saving was cancelled."))
                default:
                    let message = session.error?.localizedDescription ?? "Saving the video failed."
                    continuation.resume(throwing: ClipMetadataError.exportFailed(message))
                }
            }
        }
    }
}
