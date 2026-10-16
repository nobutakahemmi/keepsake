import Foundation

/// A finished keepsake made from two clips.
struct TapeRecord: Codable, Identifiable, Equatable {
    var id: UUID
    var nameA: String
    var nameB: String
    /// Earlier of the two adjusted start times, in milliseconds since 1970-01-01 UTC.
    var originMilliseconds: Int64
    /// File name inside the Tapes folder.
    var fileName: String
    var layout: LayoutKind
    var nudgeMilliseconds: Int64
    var includesTitleCard: Bool

    var title: String {
        "\(nameA) & \(nameB)"
    }

    var date: Date {
        TimestampCodec.date(fromMilliseconds: originMilliseconds)
    }
}
