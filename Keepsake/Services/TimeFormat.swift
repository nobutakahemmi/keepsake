import Foundation

enum TimeFormat {
    static func dateTime(milliseconds: Int64) -> String {
        let date = TimestampCodec.date(fromMilliseconds: milliseconds)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        let remainder = Int(milliseconds % 1000)
        let shown = remainder < 0 ? remainder + 1000 : remainder
        return String(format: "%@.%03d", formatter.string(from: date), shown)
    }

    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    static func dayAndTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func clock(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
