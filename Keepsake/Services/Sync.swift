import CoreMedia
import Foundation

/// Core Media adapters for the millisecond timeline in `SyncMath`.
enum Sync {
    static let timescale: CMTimeScale = 1_000

    static func cmTime(milliseconds: Int64) -> CMTime {
        CMTime(value: CMTimeValue(max(0, milliseconds)), timescale: timescale)
    }

    static func milliseconds(_ time: CMTime) -> Int64 {
        guard time.isValid, !time.isIndefinite, !time.isPositiveInfinity, !time.isNegativeInfinity else {
            return 0
        }
        let converted = CMTimeConvertScale(time, timescale: timescale, method: .roundHalfAwayFromZero)
        guard converted.isValid else { return 0 }
        return max(0, converted.value)
    }

    /// Instruction ranges that share endpoints and end exactly on `total`.
    static func instructionRanges(segments: [TimelineSegment], total: CMTime) -> [CMTimeRange] {
        guard CMTimeCompare(total, .zero) > 0 else { return [] }
        guard !segments.isEmpty else {
            return [CMTimeRange(start: .zero, duration: total)]
        }

        var ranges: [CMTimeRange] = []
        var cursor = CMTime.zero
        for (index, segment) in segments.enumerated() {
            if CMTimeCompare(cursor, total) >= 0 {
                break
            }
            let isLast = index == segments.count - 1
            let proposed = isLast ? total : CMTimeMinimum(cmTime(milliseconds: segment.end.milliseconds), total)
            let end = CMTimeMaximum(proposed, cursor)
            let duration = CMTimeSubtract(end, cursor)
            if CMTimeCompare(duration, .zero) <= 0 {
                continue
            }
            ranges.append(CMTimeRange(start: cursor, duration: duration))
            cursor = end
        }

        if ranges.isEmpty {
            return [CMTimeRange(start: .zero, duration: total)]
        }
        if CMTimeCompare(cursor, total) < 0, let lastIndex = ranges.indices.last {
            let start = ranges[lastIndex].start
            ranges[lastIndex] = CMTimeRange(start: start, duration: CMTimeSubtract(total, start))
        }
        return ranges
    }
}
