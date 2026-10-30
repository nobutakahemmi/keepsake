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
    /// True when the movie file itself contains the start time, so Share can AirDrop it.
    var metadataEmbedded: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case startMilliseconds
        case durationMilliseconds
        case fileName
        case imported
        case startTimeSource
        case metadataEmbedded
    }

    init(
        id: UUID,
        displayName: String,
        startMilliseconds: Int64,
        durationMilliseconds: Int64,
        fileName: String,
        imported: Bool,
        startTimeSource: StartTimeSource,
        metadataEmbedded: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.startMilliseconds = startMilliseconds
        self.durationMilliseconds = durationMilliseconds
        self.fileName = fileName
        self.imported = imported
        self.startTimeSource = startTimeSource
        self.metadataEmbedded = metadataEmbedded
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        startMilliseconds = try container.decode(Int64.self, forKey: .startMilliseconds)
        durationMilliseconds = try container.decode(Int64.self, forKey: .durationMilliseconds)
        fileName = try container.decode(String.self, forKey: .fileName)
        imported = try container.decode(Bool.self, forKey: .imported)
        startTimeSource = try container.decode(StartTimeSource.self, forKey: .startTimeSource)
        metadataEmbedded = try container.decodeIfPresent(Bool.self, forKey: .metadataEmbedded) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(startMilliseconds, forKey: .startMilliseconds)
        try container.encode(durationMilliseconds, forKey: .durationMilliseconds)
        try container.encode(fileName, forKey: .fileName)
        try container.encode(imported, forKey: .imported)
        try container.encode(startTimeSource, forKey: .startTimeSource)
        try container.encode(metadataEmbedded, forKey: .metadataEmbedded)
    }

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
