import Foundation

/// Where a clip's start time came from. Keepsake's own metadata is the one we trust for sync.
enum StartTimeSource: String, Codable, Equatable {
    case keepsakeMetadata
    case sidecar
    case creationDate
    case importedAt
}

/// A recording that lives on this iPhone.
struct ClipRecord: Codable, Identifiable, Equatable {
    var id: UUID
    var displayName: String
    /// Wall-clock start, milliseconds since 1970-01-01 UTC.
    var startMilliseconds: Int64
    var durationMilliseconds: Int64
    /// File name inside the Clips folder.
    var fileName: String
    var imported: Bool
    var startTimeSource: StartTimeSource

    var startDate: Date {
        TimestampCodec.date(fromMilliseconds: startMilliseconds)
    }

    var duration: TimeInterval {
        TimeInterval(durationMilliseconds) / 1000
    }

    var timing: ClipTiming {
        ClipTiming(startMilliseconds: startMilliseconds, durationMilliseconds: durationMilliseconds)
    }
}
