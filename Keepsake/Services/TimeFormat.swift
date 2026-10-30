import Foundation

enum TimeFormat {
    static func dateTime(milliseconds: Int64) -> String {
        // Format the truncated second, then append milliseconds. Passing the full
        // date lets medium time style round .600 up to the next second.
        let wholeSeconds = milliseconds / 1000
        var remainder = Int(milliseconds % 1000)
        if remainder < 0 {
            remainder += 1000
        }
        let date = Date(timeIntervalSince1970: TimeInterval(wholeSeconds))
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return String(format: "%@.%03d", formatter.string(from: date), remainder)
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
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
