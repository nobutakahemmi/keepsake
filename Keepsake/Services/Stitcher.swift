import AVFoundation
import AudioToolbox
import CoreMedia
import CoreVideo
import Foundation

struct StitchRequest {
    var urlA: URL
    var urlB: URL
    var nameA: String
    var nameB: String
    var startA: Date
    var startB: Date
    var nudgeSeconds: TimeInterval
    var layout: LayoutKind
    var includeTitleCard: Bool
}

struct StitchBuild {
    var composition: AVMutableComposition
    var videoComposition: AVMutableVideoComposition
    var plan: SyncPlan
    var displayTitle: String
}

enum StitchError: LocalizedError {
    case missingVideo(String)
    case nothingToExport
    case exportFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .missingVideo(let name):
            return "\(name) has no video to stitch."
        case .nothingToExport:
            return "These clips are empty, so there is nothing to stitch."
        case .exportFailed(let message):
            return message
        case .cancelled:
            return "Stitching was cancelled."
        }
    }
}

enum Stitcher {
    static func build(_ request: StitchRequest) async throws -> StitchBuild {
        let loadedA = try await loadClip(url: request.urlA, name: request.nameA)
        let loadedB = try await loadClip(url: request.urlB, name: request.nameB)
        let timingA = ClipTiming(
            startMilliseconds: TimestampCodec.milliseconds(from: request.startA),
            durationMilliseconds: loadedA.durationMilliseconds
        )
        let timingB = ClipTiming(
            startMilliseconds: TimestampCodec.milliseconds(from: request.startB),
            durationMilliseconds: loadedB.durationMilliseconds
        )
        let plan = SyncMath.plan(clipA: timingA, clipB: timingB, nudgeSeconds: request.nudgeSeconds)
        guard plan.duration.milliseconds > 0 else { throw StitchError.nothingToExport }

        let composition = AVMutableComposition()
        let videoA = try addVideoTrack(to: composition)
        let videoB = try addVideoTrack(to: composition)
        try videoA.insertTimeRange(loadedA.videoRange, of: loadedA.videoTrack, at: Sync.cmTime(milliseconds: plan.offsetA.milliseconds))
        try videoB.insertTimeRange(loadedB.videoRange, of: loadedB.videoTrack, at: Sync.cmTime(milliseconds: plan.offsetB.milliseconds))

        if let audioTrack = loadedA.audioTrack {
            let audio = try addAudioTrack(to: composition)
            try insertAudio(audioTrack, range: loadedA.audioRange, into: audio, at: plan.offsetA.milliseconds, limit: loadedA.videoRange.duration)
        }
        if let audioTrack = loadedB.audioTrack {
            let audio = try addAudioTrack(to: composition)
            try insertAudio(audioTrack, range: loadedB.audioRange, into: audio, at: plan.offsetB.milliseconds, limit: loadedB.videoRange.duration)
        }

        let duration = try await composition.load(.duration)
        guard CMTimeCompare(duration, .zero) > 0 else { throw StitchError.nothingToExport }

        let render = FrameGeometry.renderSize(for: request.layout)
        let halves = FrameGeometry.halves(for: request.layout)
        let rectA = CGRect(x: halves.a.x, y: halves.a.y, width: halves.a.width, height: halves.a.height)
        let rectB = CGRect(x: halves.b.x, y: halves.b.y, width: halves.b.width, height: halves.b.height)
        let title: TitleCardContent? = request.includeTitleCard
            ? TitleCardContent(names: "\(request.nameA) & \(request.nameB)", date: TimeFormat.day(plan.origin.date))
            : nil

        let segments = CompositionTiming.segments(plan: plan)
        let instructions = makeInstructions(
            segments: segments,
            total: duration,
            videoA: videoA.trackID,
            videoB: videoB.trackID,
            rectA: rectA,
            rectB: rectB,
            orientationA: loadedA.orientation,
            orientationB: loadedB.orientation,
            title: title
        )
        guard !instructions.isEmpty else { throw StitchError.nothingToExport }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.customVideoCompositorClass = KeepsakeCompositor.self
        videoComposition.renderSize = CGSize(width: render.width, height: render.height)
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = instructions.map { $0 as any AVVideoCompositionInstructionProtocol }

        let displayTitle = "\(request.nameA) & \(request.nameB)"
        return StitchBuild(
            composition: composition,
            videoComposition: videoComposition,
            plan: plan,
            displayTitle: displayTitle
        )
    }

    /// Writes a 1080p H.264 MP4. Both audio tracks are mixed.
    static func export(
        _ build: StitchBuild,
        to url: URL,
        progress: @escaping (Double) -> Void
    ) async throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        var succeeded = false
        defer {
            if !succeeded {
                try? FileManager.default.removeItem(at: url)
            }
        }

        let composition = build.composition
        let reader = try AVAssetReader(asset: composition)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let renderSize = build.videoComposition.renderSize
        let width = Int(renderSize.width.rounded())
        let height = Int(renderSize.height.rounded())
        guard width > 0, height > 0, width.isMultiple(of: 2), height.isMultiple(of: 2) else {
            throw StitchError.exportFailed("The keepsake size is not valid.")
        }

        let videoTracks = try await composition.loadTracks(withMediaType: .video)
        guard !videoTracks.isEmpty else { throw StitchError.nothingToExport }
        let videoOutput = AVAssetReaderVideoCompositionOutput(
            videoTracks: videoTracks,
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_32BGRA)]
        )
        videoOutput.videoComposition = build.videoComposition
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else {
            throw StitchError.exportFailed("Could not read the stitched picture.")
        }
        reader.add(videoOutput)

        let audioTracks = try await composition.loadTracks(withMediaType: .audio)
        var audioOutput: AVAssetReaderAudioMixOutput?
        var audioInput: AVAssetWriterInput?
        if !audioTracks.isEmpty {
            let output = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: pcmSettings)
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else {
                throw StitchError.exportFailed("Could not mix the audio.")
            }
            reader.add(output)
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: aacSettings)
            input.expectsMediaDataInRealTime = false
            guard writer.canAdd(input) else {
                throw StitchError.exportFailed("Could not save the audio.")
            }
            writer.add(input)
            audioOutput = output
            audioInput = input
        }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: NSNumber(value: width),
            AVVideoHeightKey: NSNumber(value: height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: NSNumber(value: 8_000_000),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: NSNumber(value: 30)
            ],
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
            ]
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput) else {
            throw StitchError.exportFailed("Could not save the picture.")
        }
        writer.add(videoInput)

        writer.metadata = ClipMetadata.items(start: build.plan.origin.date, displayName: build.displayTitle)
        writer.shouldOptimizeForNetworkUse = true

        guard writer.startWriting() else {
            throw StitchError.exportFailed(writer.error?.localizedDescription ?? "Could not start saving.")
        }
        writer.startSession(atSourceTime: .zero)
        guard reader.startReading() else {
            writer.cancelWriting()
            throw StitchError.exportFailed(reader.error?.localizedDescription ?? "Could not read the clips.")
        }

        let duration = try await composition.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        try await pump(
            reader: reader,
            writer: writer,
            videoOutput: videoOutput,
            videoInput: videoInput,
            audioOutput: audioOutput,
            audioInput: audioInput,
            durationSeconds: durationSeconds,
            progress: progress
        )
        succeeded = true
        progress(1)
    }

    private static var pcmSettings: [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2
        ]
    }

    private static var aacSettings: [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128_000
        ]
    }

    private struct LoadedClip {
        var videoTrack: AVAssetTrack
        var audioTrack: AVAssetTrack?
        var videoRange: CMTimeRange
        var audioRange: CMTimeRange
        var orientation: CGImagePropertyOrientation
        var durationMilliseconds: Int64
    }

    private static func loadClip(url: URL, name: String) async throws -> LoadedClip {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw StitchError.exportFailed("\(name) is missing from this iPhone.")
        }
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let videoTracks: [AVAssetTrack]
        do {
            videoTracks = try await asset.loadTracks(withMediaType: .video)
        } catch {
            throw StitchError.exportFailed("Could not open \(name). \(error.localizedDescription)")
        }
        guard let videoTrack = videoTracks.first else { throw StitchError.missingVideo(name) }
        let range = try await videoTrack.load(.timeRange)
        let durationMs = Sync.milliseconds(range.duration)
        guard durationMs > 0 else { throw StitchError.missingVideo(name) }
        let transform = try await videoTrack.load(.preferredTransform)
        let raw = VideoOrientationMath.rawOrientation(
            a: Double(transform.a),
            b: Double(transform.b),
            c: Double(transform.c),
            d: Double(transform.d)
        )
        let orientation = CGImagePropertyOrientation(rawValue: UInt32(raw)) ?? .up
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let audioTrack = audioTracks.first
        let audioRange: CMTimeRange
        if let audioTrack {
            audioRange = try await audioTrack.load(.timeRange)
        } else {
            audioRange = .zero
        }
        return LoadedClip(
            videoTrack: videoTrack,
            audioTrack: audioTrack,
            videoRange: range,
            audioRange: audioRange,
            orientation: orientation,
            durationMilliseconds: durationMs
        )
    }

    private static func makeInstructions(
        segments: [TimelineSegment],
        total: CMTime,
        videoA: CMPersistentTrackID,
        videoB: CMPersistentTrackID,
        rectA: CGRect,
        rectB: CGRect,
        orientationA: CGImagePropertyOrientation,
        orientationB: CGImagePropertyOrientation,
        title: TitleCardContent?
    ) -> [KeepsakeInstruction] {
        var instructions: [KeepsakeInstruction] = []
        var cursor = CMTime.zero
        for (index, segment) in segments.enumerated() {
            if CMTimeCompare(cursor, total) >= 0 { break }
            let isLast = index == segments.count - 1
            let proposed = isLast ? total : CMTimeMinimum(Sync.cmTime(milliseconds: segment.end.milliseconds), total)
            let end = CMTimeMaximum(proposed, cursor)
            let span = CMTimeSubtract(end, cursor)
            if CMTimeCompare(span, .zero) <= 0 { continue }
            instructions.append(
                KeepsakeInstruction(
                    timeRange: CMTimeRange(start: cursor, duration: span),
                    trackA: segment.includesA ? videoA : nil,
                    trackB: segment.includesB ? videoB : nil,
                    rectA: rectA,
                    rectB: rectB,
                    orientationA: orientationA,
                    orientationB: orientationB,
                    title: title
                )
            )
            cursor = end
        }
        if instructions.isEmpty, CMTimeCompare(total, .zero) > 0 {
            instructions.append(
                KeepsakeInstruction(
                    timeRange: CMTimeRange(start: .zero, duration: total),
                    trackA: videoA,
                    trackB: videoB,
                    rectA: rectA,
                    rectB: rectB,
                    orientationA: orientationA,
                    orientationB: orientationB,
                    title: title
                )
            )
        }
        return instructions
    }

    private static func addVideoTrack(to composition: AVMutableComposition) throws -> AVMutableCompositionTrack {
        guard let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw StitchError.exportFailed("Could not prepare the picture.")
        }
        return track
    }

    private static func addAudioTrack(to composition: AVMutableComposition) throws -> AVMutableCompositionTrack {
        guard let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw StitchError.exportFailed("Could not prepare the audio.")
        }
        return track
    }

    private static func insertAudio(
        _ source: AVAssetTrack,
        range: CMTimeRange,
        into destination: AVMutableCompositionTrack,
        at offsetMilliseconds: Int64,
        limit: CMTime
    ) throws {
        let used = CMTimeMinimum(range.duration, limit)
        guard CMTimeCompare(used, .zero) > 0 else { return }
        let insertRange = CMTimeRange(start: range.start, duration: used)
        try destination.insertTimeRange(insertRange, of: source, at: Sync.cmTime(milliseconds: offsetMilliseconds))
    }

    private static func pump(
        reader: AVAssetReader,
        writer: AVAssetWriter,
        videoOutput: AVAssetReaderOutput,
        videoInput: AVAssetWriterInput,
        audioOutput: AVAssetReaderOutput?,
        audioInput: AVAssetWriterInput?,
        durationSeconds: Double,
        progress: @escaping (Double) -> Void
    ) async throws {
        let state = ExportState()
        let group = DispatchGroup()
        let videoPump = PumpGate()
        let audioPump = PumpGate()
        let includeAudio = audioOutput != nil && audioInput != nil
        group.enter()
        if includeAudio {
            group.enter()
        }

        let videoQueue = DispatchQueue(label: "com.keepsake.export.video")
        videoInput.requestMediaDataWhenReady(on: videoQueue) {
            while videoInput.isReadyForMoreMediaData {
                if state.hasFailed {
                    videoInput.markAsFinished()
                    videoPump.leaveOnce(group)
                    return
                }
                let sample: CMSampleBuffer? = autoreleasepool { videoOutput.copyNextSampleBuffer() }
                if let sample {
                    if !videoInput.append(sample) {
                        state.fail(writer.error ?? StitchError.exportFailed("Could not write the video."))
                        reader.cancelReading()
                        videoInput.markAsFinished()
                        audioInput?.markAsFinished()
                        videoPump.leaveOnce(group)
                        if includeAudio {
                            audioPump.leaveOnce(group)
                        }
                        return
                    }
                    let timestamp = CMSampleBufferGetPresentationTimeStamp(sample)
                    let seconds = CMTimeGetSeconds(timestamp)
                    if seconds.isFinite, durationSeconds > 0 {
                        progress(min(0.99, max(0, seconds / durationSeconds)))
                    }
                } else {
                    if reader.status == .failed, let error = reader.error {
                        state.fail(error)
                        reader.cancelReading()
                        audioInput?.markAsFinished()
                        if includeAudio {
                            audioPump.leaveOnce(group)
                        }
                    }
                    videoInput.markAsFinished()
                    videoPump.leaveOnce(group)
                    return
                }
            }
        }

        if includeAudio, let audioOutput, let audioInput {
            let audioQueue = DispatchQueue(label: "com.keepsake.export.audio")
            audioInput.requestMediaDataWhenReady(on: audioQueue) {
                while audioInput.isReadyForMoreMediaData {
                    if state.hasFailed {
                        audioInput.markAsFinished()
                        audioPump.leaveOnce(group)
                        return
                    }
                    let sample: CMSampleBuffer? = autoreleasepool { audioOutput.copyNextSampleBuffer() }
                    if let sample {
                        if !audioInput.append(sample) {
                            state.fail(writer.error ?? StitchError.exportFailed("Could not write the audio."))
                            reader.cancelReading()
                            audioInput.markAsFinished()
                            videoInput.markAsFinished()
                            audioPump.leaveOnce(group)
                            videoPump.leaveOnce(group)
                            return
                        }
                    } else {
                        if reader.status == .failed, let error = reader.error {
                            state.fail(error)
                        }
                        audioInput.markAsFinished()
                        audioPump.leaveOnce(group)
                        return
                    }
                }
            }
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            group.notify(queue: DispatchQueue(label: "com.keepsake.export.finish")) {
                writer.finishWriting {
                    if let error = state.error {
                        continuation.resume(throwing: error)
                    } else if writer.status == .completed {
                        continuation.resume()
                    } else if writer.status == .cancelled {
                        continuation.resume(throwing: StitchError.cancelled)
                    } else {
                        let message = writer.error?.localizedDescription ?? "Could not save the keepsake."
                        continuation.resume(throwing: StitchError.exportFailed(message))
                    }
                }
            }
        }
    }
}

private final class ExportState: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Error?
    var error: Error? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
    var hasFailed: Bool { error != nil }
    func fail(_ error: Error) {
        lock.lock()
        if stored == nil { stored = error }
        lock.unlock()
    }
}

private final class PumpGate: @unchecked Sendable {
    private let lock = NSLock()
    private var left = false
    func leaveOnce(_ group: DispatchGroup) {
        lock.lock()
        let shouldLeave = !left
        left = true
        lock.unlock()
        if shouldLeave {
            group.leave()
        }
    }
}

@MainActor
final class StitchSession: ObservableObject {
    @Published var progress: Double = 0
    @Published var isRunning = false

    func begin() {
        isRunning = true
        progress = 0
    }

    func end() {
        isRunning = false
    }
}
