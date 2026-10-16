import Foundation

/// A moment or a length stored as whole milliseconds so sync stays exact.
struct KeepsakeTime: Equatable, Hashable, Comparable {
    var milliseconds: Int64

    static func < (lhs: KeepsakeTime, rhs: KeepsakeTime) -> Bool {
        lhs.milliseconds < rhs.milliseconds
    }

    var seconds: TimeInterval {
        TimeInterval(milliseconds) / 1000
    }

    var date: Date {
        Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
    }

    static let zero = KeepsakeTime(milliseconds: 0)
}

/// Start wall-clock and length for one recording.
struct ClipTiming: Equatable {
    var start: KeepsakeTime
    var duration: KeepsakeTime

    init(start: Date, duration: TimeInterval) {
        self.start = KeepsakeTime(milliseconds: TimestampCodec.milliseconds(from: start))
        let ms = Int64((max(0, duration) * 1000).rounded())
        self.duration = KeepsakeTime(milliseconds: max(0, ms))
    }

    init(startMilliseconds: Int64, durationMilliseconds: Int64) {
        self.start = KeepsakeTime(milliseconds: startMilliseconds)
        self.duration = KeepsakeTime(milliseconds: max(0, durationMilliseconds))
    }
}

/// Where each clip sits on a shared timeline. Time zero is the earlier adjusted start.
struct SyncPlan: Equatable {
    var origin: KeepsakeTime
    var offsetA: KeepsakeTime
    var offsetB: KeepsakeTime
    var endA: KeepsakeTime
    var endB: KeepsakeTime
    var duration: KeepsakeTime
    /// Nudge applied to clip B after snapping to 0.05 s and clamping to ±2 s.
    var nudge: KeepsakeTime

    var overlapStart: KeepsakeTime {
        KeepsakeTime(milliseconds: max(offsetA.milliseconds, offsetB.milliseconds))
    }

    var overlapEnd: KeepsakeTime {
        KeepsakeTime(milliseconds: min(endA.milliseconds, endB.milliseconds))
    }

    var overlapDuration: KeepsakeTime {
        KeepsakeTime(milliseconds: max(0, overlapEnd.milliseconds - overlapStart.milliseconds))
    }
}

/// One slice of the stitched timeline. Slices meet at the edges and cover the whole plan.
struct TimelineSegment: Equatable {
    var start: KeepsakeTime
    var end: KeepsakeTime
    var includesA: Bool
    var includesB: Bool

    var duration: KeepsakeTime {
        KeepsakeTime(milliseconds: end.milliseconds - start.milliseconds)
    }
}

enum SyncMath {
    static let maxNudgeMilliseconds: Int64 = 2_000
    static let nudgeStepMilliseconds: Int64 = 50
    static let titleCardMilliseconds: Int64 = 3_000

    /// Positive means clip B starts later than clip A on the shared timeline.
    static func otherClipLeadMilliseconds(_ plan: SyncPlan) -> Int64 {
        plan.offsetB.milliseconds - plan.offsetA.milliseconds
    }

    static func showsTitleCard(atMilliseconds time: Int64, enabled: Bool) -> Bool {
        enabled && time >= 0 && time < titleCardMilliseconds
    }

    static func snappedNudge(milliseconds raw: Int64) -> Int64 {
        let clamped = min(maxNudgeMilliseconds, max(-maxNudgeMilliseconds, raw))
        let steps = (Double(clamped) / Double(nudgeStepMilliseconds)).rounded()
        let snapped = Int64(steps) * nudgeStepMilliseconds
        return min(maxNudgeMilliseconds, max(-maxNudgeMilliseconds, snapped))
    }

    static func snappedNudge(seconds raw: Double) -> TimeInterval {
        let ms = Int64((raw * 1000).rounded())
        return TimeInterval(snappedNudge(milliseconds: ms)) / 1000
    }

    /// Builds a timeline. `nudgeMilliseconds` moves clip B later when positive.
    static func plan(clipA: ClipTiming, clipB: ClipTiming, nudgeMilliseconds: Int64) -> SyncPlan {
        let nudge = snappedNudge(milliseconds: nudgeMilliseconds)
        let startA = clipA.start.milliseconds
        let startB = clipB.start.milliseconds + nudge
        let origin = min(startA, startB)
        let offsetA = startA - origin
        let offsetB = startB - origin
        let endA = offsetA + clipA.duration.milliseconds
        let endB = offsetB + clipB.duration.milliseconds
        return SyncPlan(
            origin: KeepsakeTime(milliseconds: origin),
            offsetA: KeepsakeTime(milliseconds: offsetA),
            offsetB: KeepsakeTime(milliseconds: offsetB),
            endA: KeepsakeTime(milliseconds: endA),
            endB: KeepsakeTime(milliseconds: endB),
            duration: KeepsakeTime(milliseconds: max(endA, endB)),
            nudge: KeepsakeTime(milliseconds: nudge)
        )
    }

    static func plan(clipA: ClipTiming, clipB: ClipTiming, nudgeSeconds: TimeInterval) -> SyncPlan {
        let ms = Int64((nudgeSeconds * 1000).rounded())
        return plan(clipA: clipA, clipB: clipB, nudgeMilliseconds: ms)
    }

    static func signedSeconds(milliseconds: Int64) -> String {
        let value = Double(milliseconds) / 1000
        let number = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
        if milliseconds > 0 {
            return "+\(number) s"
        }
        return "\(number) s"
    }
}

enum CompositionTiming {
    /// Splits the picture into contiguous slices. A title card is drawn on top of the
    /// start of this same timeline, so it does not insert time or move the audio.
    static func segments(plan: SyncPlan) -> [TimelineSegment] {
        let duration = plan.duration.milliseconds
        guard duration > 0 else { return [] }

        let marks = [
            Int64(0),
            plan.offsetA.milliseconds,
            plan.offsetB.milliseconds,
            plan.endA.milliseconds,
            plan.endB.milliseconds,
            duration
        ]
        var boundaries = Set<Int64>()
        for mark in marks where mark >= 0 && mark <= duration {
            boundaries.insert(mark)
        }
        let sorted = boundaries.sorted()
        var segments: [TimelineSegment] = []
        for index in 0..<(sorted.count - 1) {
            let start = sorted[index]
            let end = sorted[index + 1]
            guard end > start else { continue }
            let midpoint = start + (end - start) / 2
            let includesA = plan.endA.milliseconds > plan.offsetA.milliseconds
                && midpoint >= plan.offsetA.milliseconds
                && midpoint < plan.endA.milliseconds
            let includesB = plan.endB.milliseconds > plan.offsetB.milliseconds
                && midpoint >= plan.offsetB.milliseconds
                && midpoint < plan.endB.milliseconds
            segments.append(
                TimelineSegment(
                    start: KeepsakeTime(milliseconds: start),
                    end: KeepsakeTime(milliseconds: end),
                    includesA: includesA,
                    includesB: includesB
                )
            )
        }
        return segments
    }

    /// Segments start at zero, meet at every edge, and end on the plan duration.
    static func covers(_ plan: SyncPlan, segments: [TimelineSegment]) -> Bool {
        guard plan.duration.milliseconds > 0 else { return segments.isEmpty }
        guard let first = segments.first, let last = segments.last else { return false }
        guard first.start.milliseconds == 0 else { return false }
        guard last.end.milliseconds == plan.duration.milliseconds else { return false }
        for index in 0..<(segments.count - 1) where segments[index].end.milliseconds != segments[index + 1].start.milliseconds {
            return false
        }
        let summed = segments.reduce(Int64(0)) { $0 + $1.duration.milliseconds }
        return summed == plan.duration.milliseconds
    }
}

struct KSize: Equatable {
    var width: Double
    var height: Double
}

/// A rectangle in a top-left origin coordinate space (y grows downward).
struct KRect: Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    var midX: Double { x + width / 2 }
    var midY: Double { y + height / 2 }
    var maxX: Double { x + width }
    var maxY: Double { y + height }
}

enum FrameGeometry {
    static func renderSize(for layout: LayoutKind) -> KSize {
        switch layout {
        case .sideBySide:
            return KSize(width: 1920, height: 1080)
        case .stacked:
            return KSize(width: 1080, height: 1920)
        }
    }

    /// Clip A is on the left or the top. Clip B is on the right or the bottom.
    static func halves(for layout: LayoutKind) -> (a: KRect, b: KRect) {
        switch layout {
        case .sideBySide:
            return (
                KRect(x: 0, y: 0, width: 960, height: 1080),
                KRect(x: 960, y: 0, width: 960, height: 1080)
            )
        case .stacked:
            return (
                KRect(x: 0, y: 0, width: 1080, height: 960),
                KRect(x: 0, y: 960, width: 1080, height: 960)
            )
        }
    }

    /// Scales `videoSize` so it covers `target` without changing shape, then centers it.
    /// The result may extend past `target`; the compositor crops to the target.
    static func aspectFill(videoSize: KSize, into target: KRect) -> KRect {
        guard videoSize.width > 0, videoSize.height > 0, target.width > 0, target.height > 0 else {
            return target
        }
        let scale = max(target.width / videoSize.width, target.height / videoSize.height)
        let width = videoSize.width * scale
        let height = videoSize.height * scale
        return KRect(
            x: target.midX - width / 2,
            y: target.midY - height / 2,
            width: width,
            height: height
        )
    }

    /// Core Image uses a bottom-left origin. Layout rects in this file use a top-left origin.
    static func coreImageRect(fromTopLeft rect: KRect, canvasHeight: Double) -> KRect {
        KRect(
            x: rect.x,
            y: canvasHeight - rect.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }
}

enum TimestampCodec {
    static func milliseconds(from date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    static func date(fromMilliseconds milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
    }

    static func iso8601(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    /// Reads a Keepsake millisecond timestamp or an ISO-8601 creation date.
    static func date(fromStored string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let ms = Int64(trimmed), ms >= 1_000_000_000_000, ms < 10_000_000_000_000 {
            return date(fromMilliseconds: ms)
        }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: trimmed) {
            return date
        }

        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        return basic.date(from: trimmed)
    }
}

/// Maps an AVAssetTrack preferred-transform's 2×2 part to a CGImagePropertyOrientation raw value.
enum VideoOrientationMath {
    static func rawOrientation(a: Double, b: Double, c: Double, d: Double) -> Int {
        func near(_ value: Double, _ target: Double) -> Bool {
            abs(value - target) < 0.02
        }
        if near(a, 0), near(b, 1), near(c, -1), near(d, 0) { return 6 }
        if near(a, 0), near(b, -1), near(c, 1), near(d, 0) { return 8 }
        if near(a, 0), near(b, -1), near(c, -1), near(d, 0) { return 7 }
        if near(a, 0), near(b, 1), near(c, 1), near(d, 0) { return 5 }
        if near(a, -1), near(b, 0), near(c, 0), near(d, -1) { return 3 }
        if near(a, -1), near(b, 0), near(c, 0), near(d, 1) { return 4 }
        if near(a, 1), near(b, 0), near(c, 0), near(d, -1) { return 2 }
        return 1
    }
}
