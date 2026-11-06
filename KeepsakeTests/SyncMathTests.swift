import XCTest
@testable import Keepsake

final class SyncMathTests: XCTestCase {
    func testSameStartLinesBothClipsUpAtZero() {
        let plan = SyncMath.plan(
            clipA: ClipTiming(startMilliseconds: 1_000, durationMilliseconds: 4_000),
            clipB: ClipTiming(startMilliseconds: 1_000, durationMilliseconds: 2_500),
            nudgeMilliseconds: 0
        )
        XCTAssertEqual(plan.origin.milliseconds, 1_000)
        XCTAssertEqual(plan.offsetA.milliseconds, 0)
        XCTAssertEqual(plan.offsetB.milliseconds, 0)
        XCTAssertEqual(plan.endA.milliseconds, 4_000)
        XCTAssertEqual(plan.endB.milliseconds, 2_500)
        XCTAssertEqual(plan.duration.milliseconds, 4_000)
        XCTAssertEqual(plan.nudge.milliseconds, 0)
        XCTAssertEqual(SyncMath.otherClipLeadMilliseconds(plan), 0)
        XCTAssertEqual(plan.overlapDuration.milliseconds, 2_500)
    }

    func testLaterClipIsPlacedAfterTheEarlierOne() {
        let plan = SyncMath.plan(
            clipA: ClipTiming(startMilliseconds: 5_000, durationMilliseconds: 10_000),
            clipB: ClipTiming(startMilliseconds: 6_250, durationMilliseconds: 8_000),
            nudgeMilliseconds: 0
        )
        XCTAssertEqual(plan.offsetA.milliseconds, 0)
        XCTAssertEqual(plan.offsetB.milliseconds, 1_250)
        XCTAssertEqual(plan.endA.milliseconds, 10_000)
        XCTAssertEqual(plan.endB.milliseconds, 9_250)
        XCTAssertEqual(plan.duration.milliseconds, 10_000)
        XCTAssertEqual(plan.overlapStart.milliseconds, 1_250)
        XCTAssertEqual(plan.overlapEnd.milliseconds, 9_250)
        XCTAssertEqual(plan.overlapDuration.milliseconds, 8_000)
        XCTAssertEqual(SyncMath.otherClipLeadMilliseconds(plan), 1_250)
    }

    func testEarlierSecondClipBecomesTheTimelineOrigin() {
        let plan = SyncMath.plan(
            clipA: ClipTiming(startMilliseconds: 8_000, durationMilliseconds: 3_000),
            clipB: ClipTiming(startMilliseconds: 7_400, durationMilliseconds: 2_000),
            nudgeMilliseconds: 0
        )
        XCTAssertEqual(plan.origin.milliseconds, 7_400)
        XCTAssertEqual(plan.offsetA.milliseconds, 600)
        XCTAssertEqual(plan.offsetB.milliseconds, 0)
        XCTAssertEqual(plan.endA.milliseconds, 3_600)
        XCTAssertEqual(plan.endB.milliseconds, 2_000)
        XCTAssertEqual(plan.duration.milliseconds, 3_600)
        XCTAssertEqual(SyncMath.otherClipLeadMilliseconds(plan), -600)
    }

    func testPositiveNudgeDelaysClipB() {
        let plan = SyncMath.plan(
            clipA: ClipTiming(startMilliseconds: 5_000, durationMilliseconds: 10_000),
            clipB: ClipTiming(startMilliseconds: 6_250, durationMilliseconds: 8_000),
            nudgeMilliseconds: 200
        )
        XCTAssertEqual(plan.nudge.milliseconds, 200)
        XCTAssertEqual(plan.offsetA.milliseconds, 0)
        XCTAssertEqual(plan.offsetB.milliseconds, 1_450)
        XCTAssertEqual(plan.endB.milliseconds, 9_450)
    }

    func testNegativeNudgeCanMoveClipBAheadOfClipA() {
        let plan = SyncMath.plan(
            clipA: ClipTiming(startMilliseconds: 5_000, durationMilliseconds: 10_000),
            clipB: ClipTiming(startMilliseconds: 6_250, durationMilliseconds: 8_000),
            nudgeMilliseconds: -6_000
        )
        XCTAssertEqual(plan.nudge.milliseconds, -2_000)
        XCTAssertEqual(plan.origin.milliseconds, 4_250)
        XCTAssertEqual(plan.offsetA.milliseconds, 750)
        XCTAssertEqual(plan.offsetB.milliseconds, 0)
        XCTAssertEqual(plan.endA.milliseconds, 10_750)
        XCTAssertEqual(plan.endB.milliseconds, 8_000)
        XCTAssertEqual(plan.duration.milliseconds, 10_750)
    }

    func testNudgeSnapsToTwentiethsOfASecondAndClamps() {
        XCTAssertEqual(SyncMath.snappedNudge(milliseconds: 0), 0)
        XCTAssertEqual(SyncMath.snappedNudge(milliseconds: 2_000), 2_000)
        XCTAssertEqual(SyncMath.snappedNudge(milliseconds: -2_000), -2_000)
        XCTAssertEqual(SyncMath.snappedNudge(milliseconds: 2_001), 2_000)
        XCTAssertEqual(SyncMath.snappedNudge(milliseconds: -2_001), -2_000)
        XCTAssertEqual(SyncMath.snappedNudge(milliseconds: 149), 150)
        XCTAssertEqual(SyncMath.snappedNudge(milliseconds: 174), 150)
        XCTAssertEqual(SyncMath.snappedNudge(milliseconds: 175), 200)
        XCTAssertEqual(SyncMath.snappedNudge(milliseconds: -175), -200)
        XCTAssertEqual(SyncMath.snappedNudge(milliseconds: 25), 50)
        XCTAssertEqual(SyncMath.snappedNudge(milliseconds: -25), -50)
        XCTAssertEqual(SyncMath.snappedNudge(seconds: 0.06), 0.05, accuracy: 0.000_000_1)
        XCTAssertEqual(SyncMath.snappedNudge(seconds: 0.15), 0.15, accuracy: 0.000_000_1)
    }

    func testSignedSecondsFormatting() {
        XCTAssertEqual(SyncMath.signedSeconds(milliseconds: 150), "+0.15 s")
        XCTAssertEqual(SyncMath.signedSeconds(milliseconds: -50), "-0.05 s")
        XCTAssertEqual(SyncMath.signedSeconds(milliseconds: 0), "0.00 s")
    }

    func testNoOverlapProducesAGapBetweenTheClips() {
        let plan = SyncMath.plan(
            clipA: ClipTiming(startMilliseconds: 0, durationMilliseconds: 1_000),
            clipB: ClipTiming(startMilliseconds: 3_000, durationMilliseconds: 1_000),
            nudgeMilliseconds: 0
        )
        let segments = CompositionTiming.segments(plan: plan)
        XCTAssertEqual(segments.count, 3)
        XCTAssertEqual(segments[0].start.milliseconds, 0)
        XCTAssertEqual(segments[0].end.milliseconds, 1_000)
        XCTAssertTrue(segments[0].includesA)
        XCTAssertFalse(segments[0].includesB)
        XCTAssertEqual(segments[1].start.milliseconds, 1_000)
        XCTAssertEqual(segments[1].end.milliseconds, 3_000)
        XCTAssertFalse(segments[1].includesA)
        XCTAssertFalse(segments[1].includesB)
        XCTAssertEqual(segments[2].start.milliseconds, 3_000)
        XCTAssertEqual(segments[2].end.milliseconds, 4_000)
        XCTAssertFalse(segments[2].includesA)
        XCTAssertTrue(segments[2].includesB)
        XCTAssertTrue(CompositionTiming.covers(plan, segments: segments))
        XCTAssertEqual(plan.overlapDuration.milliseconds, 0)
    }

    func testPartialOverlapSegments() {
        let plan = SyncMath.plan(
            clipA: ClipTiming(startMilliseconds: 1_000, durationMilliseconds: 5_000),
            clipB: ClipTiming(startMilliseconds: 1_500, durationMilliseconds: 2_000),
            nudgeMilliseconds: 0
        )
        let segments = CompositionTiming.segments(plan: plan)
        XCTAssertEqual(segments.map(\.includesA), [true, true, true])
        XCTAssertEqual(segments.map(\.includesB), [false, true, false])
        XCTAssertEqual(segments.map(\.start.milliseconds), [0, 500, 2_500])
        XCTAssertEqual(segments.map(\.end.milliseconds), [500, 2_500, 5_000])
        XCTAssertTrue(CompositionTiming.covers(plan, segments: segments))
    }

    func testZeroLengthClipDoesNotAppearInASegment() {
        let plan = SyncMath.plan(
            clipA: ClipTiming(startMilliseconds: 0, durationMilliseconds: 2_000),
            clipB: ClipTiming(startMilliseconds: 0, durationMilliseconds: 0),
            nudgeMilliseconds: 0
        )
        let segments = CompositionTiming.segments(plan: plan)
        XCTAssertEqual(segments.count, 1)
        XCTAssertTrue(segments[0].includesA)
        XCTAssertFalse(segments[0].includesB)
        XCTAssertTrue(CompositionTiming.covers(plan, segments: segments))
    }

    func testEmptyPlanHasNoSegments() {
        let plan = SyncMath.plan(
            clipA: ClipTiming(startMilliseconds: 10, durationMilliseconds: 0),
            clipB: ClipTiming(startMilliseconds: 10, durationMilliseconds: 0),
            nudgeMilliseconds: 0
        )
        XCTAssertEqual(plan.duration.milliseconds, 0)
        XCTAssertTrue(CompositionTiming.segments(plan: plan).isEmpty)
        XCTAssertTrue(CompositionTiming.covers(plan, segments: []))
    }

    func testTitleCardWindowDoesNotChangeTheTimeline() {
        let plan = SyncMath.plan(
            clipA: ClipTiming(startMilliseconds: 0, durationMilliseconds: 8_000),
            clipB: ClipTiming(startMilliseconds: 100, durationMilliseconds: 8_000),
            nudgeMilliseconds: 0
        )
        let segments = CompositionTiming.segments(plan: plan)
        XCTAssertEqual(segments.first?.start.milliseconds, 0)
        XCTAssertEqual(segments.last?.end.milliseconds, plan.duration.milliseconds)
        XCTAssertTrue(SyncMath.showsTitleCard(atMilliseconds: 0, enabled: true))
        XCTAssertTrue(SyncMath.showsTitleCard(atMilliseconds: 2_999, enabled: true))
        XCTAssertFalse(SyncMath.showsTitleCard(atMilliseconds: 3_000, enabled: true))
        XCTAssertFalse(SyncMath.showsTitleCard(atMilliseconds: 1_000, enabled: false))
        XCTAssertFalse(SyncMath.showsTitleCard(atMilliseconds: -1, enabled: true))
        XCTAssertEqual(SyncMath.titleCardMilliseconds, 3_000)
    }

    func testMillisecondDatesRoundTrip() {
        let milliseconds: Int64 = 1_760_588_645_123
        let date = TimestampCodec.date(fromMilliseconds: milliseconds)
        XCTAssertEqual(TimestampCodec.milliseconds(from: date), milliseconds)
        let parsed = TimestampCodec.date(fromStored: String(milliseconds))
        XCTAssertEqual(parsed.map(TimestampCodec.milliseconds(from:)), milliseconds)
    }

    func testISO8601RoundTripKeepsMilliseconds() {
        let milliseconds: Int64 = 1_760_588_645_123
        let date = TimestampCodec.date(fromMilliseconds: milliseconds)
        let iso = TimestampCodec.iso8601(from: date)
        let parsed = TimestampCodec.date(fromStored: iso)
        let parsedMilliseconds = parsed.map(TimestampCodec.milliseconds(from:))
        XCTAssertNotNil(parsedMilliseconds)
        if let parsedMilliseconds {
            XCTAssertLessThanOrEqual(abs(parsedMilliseconds - milliseconds), 1)
        }
        let wholeSecond = TimestampCodec.date(fromStored: "2026-10-16T03:04:05Z")
        XCTAssertNotNil(wholeSecond)
    }

    func testGarbageTimestampsAreRejected() {
        XCTAssertNil(TimestampCodec.date(fromStored: ""))
        XCTAssertNil(TimestampCodec.date(fromStored: "   "))
        XCTAssertNil(TimestampCodec.date(fromStored: "not-a-date"))
        XCTAssertNil(TimestampCodec.date(fromStored: "12"))
    }

    func testAspectFillCoversTheTargetAndKeepsShape() {
        let portrait = KSize(width: 1080, height: 1920)
        let leftHalf = KRect(x: 0, y: 0, width: 960, height: 1080)
        let fitted = FrameGeometry.aspectFill(videoSize: portrait, into: leftHalf)
        assertCovers(fitted, leftHalf)
        XCTAssertEqual(fitted.midX, leftHalf.midX, accuracy: 0.01)
        XCTAssertEqual(fitted.midY, leftHalf.midY, accuracy: 0.01)
        XCTAssertEqual(fitted.width / fitted.height, portrait.width / portrait.height, accuracy: 0.001)
        XCTAssertGreaterThan(fitted.height, leftHalf.height)

        let landscape = KSize(width: 1920, height: 1080)
        let wide = FrameGeometry.aspectFill(videoSize: landscape, into: leftHalf)
        assertCovers(wide, leftHalf)
        XCTAssertEqual(wide.height, leftHalf.height, accuracy: 0.01)
        XCTAssertGreaterThan(wide.width, leftHalf.width)
    }

    func testHalvesTileTheFrame() {
        let side = FrameGeometry.renderSize(for: .sideBySide)
        let sideHalves = FrameGeometry.halves(for: .sideBySide)
        XCTAssertEqual(side, KSize(width: 1920, height: 1080))
        XCTAssertEqual(sideHalves.a.maxX, sideHalves.b.x, accuracy: 0.001)
        XCTAssertEqual(sideHalves.a.width + sideHalves.b.width, side.width, accuracy: 0.001)
        XCTAssertEqual(sideHalves.a.height, side.height, accuracy: 0.001)
        XCTAssertEqual(sideHalves.b.height, side.height, accuracy: 0.001)
        XCTAssertEqual(sideHalves.a.y, 0, accuracy: 0.001)

        let stacked = FrameGeometry.renderSize(for: .stacked)
        let stackedHalves = FrameGeometry.halves(for: .stacked)
        XCTAssertEqual(stacked, KSize(width: 1080, height: 1920))
        XCTAssertEqual(stackedHalves.a.maxY, stackedHalves.b.y, accuracy: 0.001)
        XCTAssertEqual(stackedHalves.a.height + stackedHalves.b.height, stacked.height, accuracy: 0.001)
        XCTAssertEqual(stackedHalves.a.width, stacked.width, accuracy: 0.001)
        XCTAssertEqual(stackedHalves.a.x, 0, accuracy: 0.001)
    }

    func testCoreImageFlipPutsTheTopHalfAboveTheBottomHalf() {
        let canvas = 1920.0
        let top = KRect(x: 0, y: 0, width: 1080, height: 960)
        let bottom = KRect(x: 0, y: 960, width: 1080, height: 960)
        let topCI = FrameGeometry.coreImageRect(fromTopLeft: top, canvasHeight: canvas)
        let bottomCI = FrameGeometry.coreImageRect(fromTopLeft: bottom, canvasHeight: canvas)
        XCTAssertEqual(topCI, KRect(x: 0, y: 960, width: 1080, height: 960))
        XCTAssertEqual(bottomCI, KRect(x: 0, y: 0, width: 1080, height: 960))
        XCTAssertGreaterThan(topCI.y, bottomCI.y)
        let roundTrip = FrameGeometry.coreImageRect(fromTopLeft: topCI, canvasHeight: canvas)
        XCTAssertEqual(roundTrip, top)

        let fullSide = KRect(x: 960, y: 0, width: 960, height: 1080)
        let sideCI = FrameGeometry.coreImageRect(fromTopLeft: fullSide, canvasHeight: 1080)
        XCTAssertEqual(sideCI.y, 0, accuracy: 0.001)
        XCTAssertEqual(sideCI.x, 960, accuracy: 0.001)
    }

    func testPreferredTransformMapsToImageOrientation() {
        XCTAssertEqual(VideoOrientationMath.rawOrientation(a: 0, b: 1, c: -1, d: 0), 6)
        XCTAssertEqual(VideoOrientationMath.rawOrientation(a: 0, b: -1, c: 1, d: 0), 8)
        XCTAssertEqual(VideoOrientationMath.rawOrientation(a: 1, b: 0, c: 0, d: 1), 1)
        XCTAssertEqual(VideoOrientationMath.rawOrientation(a: -1, b: 0, c: 0, d: -1), 3)
        XCTAssertEqual(VideoOrientationMath.rawOrientation(a: 0, b: 1, c: 1, d: 0), 5)
        XCTAssertEqual(VideoOrientationMath.rawOrientation(a: 1, b: 0, c: 0, d: -1), 2)
    }

    private func assertCovers(_ fitted: KRect, _ target: KRect, file: StaticString = #file, line: UInt = #line) {
        XCTAssertLessThanOrEqual(fitted.x, target.x + 0.01, file: file, line: line)
        XCTAssertLessThanOrEqual(fitted.y, target.y + 0.01, file: file, line: line)
        XCTAssertGreaterThanOrEqual(fitted.maxX, target.maxX - 0.01, file: file, line: line)
        XCTAssertGreaterThanOrEqual(fitted.maxY, target.maxY - 0.01, file: file, line: line)
    }
}

final class TimeFormatTests: XCTestCase {
    func testDateTimeDoesNotRoundIntoTheNextSecond() {
        let base: Int64 = 1_700_000_000_000
        let whole = TimeFormat.dateTime(milliseconds: base)
        let plus = TimeFormat.dateTime(milliseconds: base + 600)
        XCTAssertTrue(whole.hasSuffix(".000"))
        XCTAssertTrue(plus.hasSuffix(".600"))
        XCTAssertEqual(whole.dropLast(4), plus.dropLast(4))
    }

    func testClockShowsHoursAfterSixtyMinutes() {
        XCTAssertEqual(TimeFormat.clock(90), "1:30")
        XCTAssertEqual(TimeFormat.clock(3600), "1:00:00")
        XCTAssertEqual(TimeFormat.clock(3661), "1:01:01")
    }
}

@MainActor
final class LibraryStoreTests: XCTestCase {
    func testReconcileRestoresAClipFromItsSidecar() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let clips = root.appendingPathComponent("Clips", isDirectory: true)
        try FileManager.default.createDirectory(at: clips, withIntermediateDirectories: true)
        let movie = clips.appendingPathComponent("orphan.mov")
        try Data("not a movie".utf8).write(to: movie)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        try ClipMetadata.writeSidecar(
            start: start,
            displayName: "Ada",
            beside: movie,
            durationMilliseconds: 4_000,
            metadataEmbedded: false
        )

        let store = LibraryStore(storageRoot: root)
        XCTAssertEqual(store.clips.count, 1)
        XCTAssertEqual(store.clips[0].displayName, "Ada")
        XCTAssertEqual(store.clips[0].durationMilliseconds, 4_000)
        XCTAssertFalse(store.clips[0].metadataEmbedded)
        XCTAssertEqual(store.clips[0].startTimeSource, .sidecar)
    }

    func testMissingFileIsDroppedAndNewFilesSkipBackup() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source.mov")
        try Data("clip".utf8).write(to: source)
        let store = LibraryStore(storageRoot: root)
        let start = Date(timeIntervalSince1970: 1_700_000_100)
        try store.addRecording(
            RecordedClip(
                url: source,
                start: start,
                displayName: "Bea",
                duration: 2,
                metadataEmbedded: true,
                endedByInterruption: false
            )
        )
        XCTAssertEqual(store.clips.count, 1)
        let saved = store.clipURL(store.clips[0])
        let savedValues = try saved.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(savedValues.isExcludedFromBackup, true)
        let folderValues = try saved.deletingLastPathComponent().resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(folderValues.isExcludedFromBackup, true)

        try FileManager.default.removeItem(at: saved)
        let reloaded = LibraryStore(storageRoot: root)
        XCTAssertTrue(reloaded.clips.isEmpty)
    }

    func testOlderLibraryRowsDefaultToEmbeddedMetadata() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        _ = LibraryStore(storageRoot: root)

        let fileName = "old.mov"
        let movie = root.appendingPathComponent("Clips", isDirectory: true).appendingPathComponent(fileName)
        try Data("old".utf8).write(to: movie)
        let id = UUID().uuidString
        let index = """
        {"clips":[{"displayName":"Old","durationMilliseconds":1500,"fileName":"\(fileName)","id":"\(id)","imported":false,"startMilliseconds":1700000000000,"startTimeSource":"keepsakeMetadata"}],"tapes":[]}
        """
        try index.write(to: root.appendingPathComponent("library.json"), atomically: true, encoding: .utf8)

        let reloaded = LibraryStore(storageRoot: root)
        XCTAssertEqual(reloaded.clips.count, 1)
        XCTAssertTrue(reloaded.clips[0].metadataEmbedded)
        XCTAssertEqual(reloaded.clips[0].displayName, "Old")
    }
}
