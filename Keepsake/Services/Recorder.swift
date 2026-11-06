import AVFoundation
import Foundation
import UIKit

struct RecordedClip {
    var url: URL
    var start: Date
    var displayName: String
    var duration: TimeInterval
    /// False when the start time exists only in the sidecar, so Share would drop it.
    var metadataEmbedded: Bool
    var endedByInterruption: Bool
}

enum RecorderError: LocalizedError {
    case notReady
    case noCamera
    case noMicrophone
    case permissionDenied
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .notReady:
            return "The camera is not ready yet."
        case .noCamera:
            return "This iPhone does not have a front camera Keepsake can use."
        case .noMicrophone:
            return "Keepsake could not use the microphone."
        case .permissionDenied:
            return "Allow camera and microphone access to record. You can turn them on in Settings."
        case .failed(let message):
            return message
        }
    }
}

/// Records the front camera and microphone, and remembers the wall-clock time recording began.
@MainActor
final class Recorder: NSObject, ObservableObject {
    enum Phase: Equatable {
        case idle
        case preparing
        case ready
        case recording
        case saving
        case failed
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var recordingStartedAt: Date?
    @Published var failureMessage: String?
    @Published var displayName: String

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "com.keepsake.capture")
    private let movieOutput = AVCaptureMovieFileOutput()
    private var isConfigured = false
    private var isPreparing = false
    private var isObserving = false
    private var recordingName = ""
    private var endedByInterruption = false
    private var interruptionObservers: [NSObjectProtocol] = []
    private var finishContinuation: CheckedContinuation<RecordedClip, Error>?

    override init() {
        let deviceName = UIDevice.current.name.trimmingCharacters(in: .whitespacesAndNewlines)
        displayName = deviceName.isEmpty ? "Me" : deviceName
        super.init()
    }

    deinit {
        for observer in interruptionObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func prepare() {
        guard !isPreparing, phase != .recording, phase != .saving else { return }
        if isConfigured, phase == .ready {
            Task { await self.startRunning() }
            return
        }
        isPreparing = true
        phase = .preparing
        failureMessage = nil
        Task {
            await self.prepareIfNeeded()
            self.isPreparing = false
        }
    }

    func pauseIfIdle() {
        guard phase != .recording, phase != .saving else { return }
        let captureSession = session
        sessionQueue.async {
            if captureSession.isRunning {
                captureSession.stopRunning()
            }
        }
    }

    func record() async throws -> RecordedClip {
        guard phase == .ready else { throw RecorderError.notReady }
        guard finishContinuation == nil else { throw RecorderError.notReady }
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        recordingName = name.isEmpty ? "Me" : name
        recordingStartedAt = nil
        phase = .recording
        UIApplication.shared.isIdleTimerDisabled = true

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        let output = movieOutput

        return try await withCheckedThrowingContinuation { continuation in
            self.finishContinuation = continuation
            self.sessionQueue.async {
                if output.isRecording {
                    output.stopRecording()
                }
                output.startRecording(to: url, recordingDelegate: self)
            }
        }
    }

    func stop() {
        let output = movieOutput
        sessionQueue.async {
            if output.isRecording {
                output.stopRecording()
            }
        }
    }

    private func prepareIfNeeded() async {
        do {
            let videoAllowed = await AVCaptureDevice.requestAccess(for: .video)
            let audioAllowed = await AVCaptureDevice.requestAccess(for: .audio)
            guard videoAllowed, audioAllowed else {
                phase = .failed
                failureMessage = RecorderError.permissionDenied.localizedDescription
                return
            }
            if !isConfigured {
                try await configureSession()
                isConfigured = true
            }
            startObserving()
            await startRunning()
            if phase != .recording && phase != .saving {
                phase = .ready
                failureMessage = nil
            }
        } catch {
            phase = .failed
            failureMessage = error.localizedDescription
        }
    }

    private func configureSession() async throws {
        let captureSession = session
        let output = movieOutput
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                captureSession.beginConfiguration()
                for input in captureSession.inputs {
                    captureSession.removeInput(input)
                }
                for existing in captureSession.outputs {
                    captureSession.removeOutput(existing)
                }
                if captureSession.canSetSessionPreset(.hd1920x1080) {
                    captureSession.sessionPreset = .hd1920x1080
                } else if captureSession.canSetSessionPreset(.high) {
                    captureSession.sessionPreset = .high
                }

                do {
                    guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
                        captureSession.commitConfiguration()
                        continuation.resume(throwing: RecorderError.noCamera)
                        return
                    }
                    let cameraInput = try AVCaptureDeviceInput(device: camera)
                    guard captureSession.canAddInput(cameraInput) else {
                        captureSession.commitConfiguration()
                        continuation.resume(throwing: RecorderError.noCamera)
                        return
                    }
                    captureSession.addInput(cameraInput)

                    guard let microphone = AVCaptureDevice.default(for: .audio) else {
                        captureSession.commitConfiguration()
                        continuation.resume(throwing: RecorderError.noMicrophone)
                        return
                    }
                    let microphoneInput = try AVCaptureDeviceInput(device: microphone)
                    guard captureSession.canAddInput(microphoneInput) else {
                        captureSession.commitConfiguration()
                        continuation.resume(throwing: RecorderError.noMicrophone)
                        return
                    }
                    captureSession.addInput(microphoneInput)

                    guard captureSession.canAddOutput(output) else {
                        captureSession.commitConfiguration()
                        continuation.resume(throwing: RecorderError.failed("Could not start recording."))
                        return
                    }
                    captureSession.addOutput(output)
                    if let connection = output.connection(with: .video) {
                        let portrait: CGFloat = 90
                        if connection.isVideoRotationAngleSupported(portrait) {
                            connection.videoRotationAngle = portrait
                        }
                        if connection.isVideoMirroringSupported {
                            connection.automaticallyAdjustsVideoMirroring = false
                            connection.isVideoMirrored = false
                        }
                        if connection.isVideoStabilizationSupported {
                            connection.preferredVideoStabilizationMode = .auto
                        }
                    }
                    captureSession.commitConfiguration()
                    continuation.resume()
                } catch {
                    captureSession.commitConfiguration()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func startRunning() async {
        let captureSession = session
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async {
                if !captureSession.isRunning {
                    captureSession.startRunning()
                }
                continuation.resume()
            }
        }
    }

    private func finishRecording(url: URL, error: Error?) {
        UIApplication.shared.isIdleTimerDisabled = false
        let start = recordingStartedAt ?? Date()
        let name = recordingName
        let interrupted = endedByInterruption
        endedByInterruption = false
        recordingStartedAt = nil

        let nsError = error as NSError?
        let producedFile = (nsError?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool) ?? (error == nil)
        guard producedFile, FileManager.default.fileExists(atPath: url.path) else {
            phase = interrupted ? .failed : .ready
            let message = error?.localizedDescription ?? "The recording was not saved."
            failureMessage = interrupted ? interruptionMessage(fallback: message) : message
            complete(.failure(RecorderError.failed(failureMessage ?? message)))
            return
        }

        phase = .saving
        Task {
            let embedded: URL
            let metadataEmbedded: Bool
            do {
                embedded = try await ClipMetadata.embed(source: url, start: start, displayName: name)
                try? FileManager.default.removeItem(at: url)
                metadataEmbedded = true
            } catch {
                embedded = url
                metadataEmbedded = false
            }
            let durationMs = await ClipMetadata.durationMilliseconds(of: embedded)
            let clip = RecordedClip(
                url: embedded,
                start: start,
                displayName: name,
                duration: TimeInterval(durationMs) / 1000,
                metadataEmbedded: metadataEmbedded,
                endedByInterruption: interrupted
            )
            if interrupted {
                self.phase = .failed
                self.failureMessage = self.interruptionMessage(fallback: "The camera was interrupted.")
            } else {
                self.phase = .ready
                self.failureMessage = nil
            }
            self.complete(.success(clip))
        }
    }

    private func startObserving() {
        guard !isObserving else { return }
        isObserving = true
        let center = NotificationCenter.default
        let captureSession = session
        interruptionObservers.append(
            center.addObserver(forName: .AVCaptureSessionWasInterrupted, object: captureSession, queue: .main) { [weak self] notification in
                Task { @MainActor in
                    self?.handleInterruption(notification)
                }
            }
        )
        interruptionObservers.append(
            center.addObserver(forName: .AVCaptureSessionInterruptionEnded, object: captureSession, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.handleInterruptionEnded()
                }
            }
        )
        interruptionObservers.append(
            center.addObserver(forName: .AVCaptureSessionRuntimeError, object: captureSession, queue: .main) { [weak self] notification in
                Task { @MainActor in
                    self?.handleRuntimeError(notification)
                }
            }
        )
    }

    private func handleInterruption(_ notification: Notification) {
        let raw = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int
        let reason = raw.flatMap(AVCaptureSession.InterruptionReason.init(rawValue:))
        let message = interruptionMessage(for: reason)
        failureMessage = message
        if phase == .recording {
            endedByInterruption = true
            stop()
        } else if phase == .ready || phase == .preparing || phase == .idle {
            phase = .failed
        }
    }

    private func handleInterruptionEnded() {
        guard phase == .failed, finishContinuation == nil else { return }
        prepare()
    }

    private func handleRuntimeError(_ notification: Notification) {
        let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError
        if phase == .recording {
            endedByInterruption = true
            failureMessage = error?.localizedDescription ?? interruptionMessage(fallback: "The camera stopped.")
            stop()
            return
        }
        if error?.code == .mediaServicesWereReset {
            isConfigured = false
            phase = .failed
            failureMessage = "The camera reset. Tap Try Again."
            return
        }
        phase = .failed
        failureMessage = error?.localizedDescription ?? "The camera stopped."
    }

    private func interruptionMessage(for reason: AVCaptureSession.InterruptionReason?) -> String {
        switch reason {
        case .audioDeviceInUseByAnotherClient:
            return "The microphone is being used by another app."
        case .videoDeviceInUseByAnotherClient:
            return "The camera is being used by another app."
        case .videoDeviceNotAvailableInBackground:
            return "The camera stopped because Keepsake was in the background."
        case .videoDeviceNotAvailableDueToSystemPressure:
            return "The camera stopped because this iPhone is too busy."
        default:
            return "The camera was interrupted."
        }
    }

    private func interruptionMessage(fallback: String) -> String {
        let current = failureMessage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return current.isEmpty ? fallback : current
    }

    private func complete(_ result: Result<RecordedClip, Error>) {
        let continuation = finishContinuation
        finishContinuation = nil
        continuation?.resume(with: result)
    }

    private func noteStarted() {
        recordingStartedAt = Date()
        phase = .recording
    }
}

extension Recorder: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(
        _: AVCaptureFileOutput,
        didStartRecordingTo _: URL,
        from _: [AVCaptureConnection]
    ) {
        Task { @MainActor in
            self.noteStarted()
        }
    }

    nonisolated func fileOutput(
        _: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from _: [AVCaptureConnection],
        error: Error?
    ) {
        Task { @MainActor in
            self.finishRecording(url: outputFileURL, error: error)
        }
    }
}
