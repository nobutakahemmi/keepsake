import CoreMedia
import XCTest
@testable import Keepsake

final class CompositionTimingTests: XCTestCase {
    func testMillisecondTimeIsExactAtTheNudgeStep() {
        let time = Sync.cmTime(milliseconds: 1_050)
        XCTAssertEqual(time.value, 1_050)
        XCTAssertEqual(time.timescale, 1_000)
        XCTAssertEqual(Sync.milliseconds(time), 1_050)

        let step = Sync.cmTime(milliseconds: SyncMath.nudgeStepMilliseconds)
        XCTAssertEqual(step.value, 50)
        XCTAssertEqual(CMTimeGetSeconds(step), 0.05, accuracy: 0.000_000_1)
    }

    func testInvalidTimesBecomeZero() {
        XCTAssertEqual(Sync.milliseconds(.zero), 0)
        XCTAssertEqual(Sync.milliseconds(.invalid), 0)
        XCTAssertEqual(Sync.milliseconds(.positiveInfinity), 0)
    }

    func testInstructionRangesCoverTheCompositionWithoutGaps() {
        let plan = SyncMath.plan(
            clipA: ClipTiming(startMilliseconds: 0, durationMilliseconds: 5_000),
            clipB: ClipTiming(startMilliseconds: 1_250, durationMilliseconds: 5_000),
            nudgeMilliseconds: 0
        )
        let segments = CompositionTiming.segments(plan: plan)
        let total = Sync.cmTime(milliseconds: plan.duration.milliseconds)
        let ranges = Sync.instructionRanges(segments: segments, total: total)

        XCTAssertEqual(ranges.count, segments.count)
        XCTAssertSameTime(ranges[0].start, .zero)
        XCTAssertSameTime(CMTimeRangeGetEnd(ranges[ranges.count - 1]), total)

        for index in 0..<(ranges.count - 1) {
            XCTAssertSameTime(CMTimeRangeGetEnd(ranges[index]), ranges[index + 1].start)
            XCTAssertGreaterThan(CMTimeCompare(ranges[index].duration, .zero), 0)
        }

        var sum = CMTime.zero
        for range in ranges {
            sum = CMTimeAdd(sum, range.duration)
        }
        XCTAssertSameTime(sum, total)
    }

    func testInstructionRangesFollowAGapBetweenClips() {
        let plan = SyncMath.plan(
            clipA: ClipTiming(startMilliseconds: 0, durationMilliseconds: 1_000),
            clipB: ClipTiming(startMilliseconds: 3_000, durationMilliseconds: 1_000),
            nudgeMilliseconds: 0
        )
        let segments = CompositionTiming.segments(plan: plan)
        let total = CMTime(value: 120, timescale: 30)
        XCTAssertEqual(CMTimeGetSeconds(total), 4, accuracy: 0.000_000_1)
        let ranges = Sync.instructionRanges(segments: segments, total: total)
        XCTAssertEqual(ranges.count, 3)
        XCTAssertSameTime(ranges[0].start, .zero)
        XCTAssertSameTime(CMTimeRangeGetEnd(ranges[2]), total)
        XCTAssertSameTime(CMTimeRangeGetEnd(ranges[0]), ranges[1].start)
        XCTAssertSameTime(CMTimeRangeGetEnd(ranges[1]), ranges[2].start)
        XCTAssertEqual(segments[1].includesA, false)
        XCTAssertEqual(segments[1].includesB, false)
    }

    func testEmptySegmentsStillCoverTheRequestedDuration() {
        let total = Sync.cmTime(milliseconds: 2_000)
        let ranges = Sync.instructionRanges(segments: [], total: total)
        XCTAssertEqual(ranges.count, 1)
        XCTAssertSameTime(ranges[0].start, .zero)
        XCTAssertSameTime(ranges[0].duration, total)
    }

    func testZeroDurationProducesNoInstructions() {
        let ranges = Sync.instructionRanges(segments: [], total: .zero)
        XCTAssertTrue(ranges.isEmpty)
    }

    func testNudgeStepLandsOnInstructionBoundaries() {
        let plan = SyncMath.plan(
            clipA: ClipTiming(startMilliseconds: 0, durationMilliseconds: 4_000),
            clipB: ClipTiming(startMilliseconds: 0, durationMilliseconds: 4_000),
            nudgeMilliseconds: 50
        )
        XCTAssertEqual(plan.offsetB.milliseconds, 50)
        let segments = CompositionTiming.segments(plan: plan)
        let total = Sync.cmTime(milliseconds: plan.duration.milliseconds)
        let ranges = Sync.instructionRanges(segments: segments, total: total)
        XCTAssertSameTime(ranges[0].duration, Sync.cmTime(milliseconds: 50))
        XCTAssertTrue(segments[0].includesA)
        XCTAssertFalse(segments[0].includesB)
        XCTAssertTrue(segments[1].includesA)
        XCTAssertTrue(segments[1].includesB)
    }

    private func XCTAssertSameTime(_ lhs: CMTime, _ rhs: CMTime, file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(CMTimeCompare(lhs, rhs), 0, "\(CMTimeGetSeconds(lhs)) != \(CMTimeGetSeconds(rhs))", file: file, line: line)
    }
}
