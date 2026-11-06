import AVFoundation
import CoreGraphics
import CoreImage
import CoreText
import CoreVideo
import Foundation
import ImageIO

struct TitleCardContent: Equatable {
    var names: String
    var date: String
}

/// Carries per-segment layout into the custom compositor.
final class KeepsakeInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    let timeRange: CMTimeRange
    let enablePostProcessing: Bool
    let containsTweening: Bool
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID: CMPersistentTrackID

    let trackA: CMPersistentTrackID?
    let trackB: CMPersistentTrackID?
    let rectA: CGRect
    let rectB: CGRect
    let orientationA: CGImagePropertyOrientation
    let orientationB: CGImagePropertyOrientation
    let title: TitleCardContent?

    init(
        timeRange: CMTimeRange,
        trackA: CMPersistentTrackID?,
        trackB: CMPersistentTrackID?,
        rectA: CGRect,
        rectB: CGRect,
        orientationA: CGImagePropertyOrientation,
        orientationB: CGImagePropertyOrientation,
        title: TitleCardContent?
    ) {
        self.timeRange = timeRange
        self.enablePostProcessing = false
        self.containsTweening = false
        self.passthroughTrackID = kCMPersistentTrackID_Invalid
        self.trackA = trackA
        self.trackB = trackB
        self.rectA = rectA
        self.rectB = rectB
        self.orientationA = orientationA
        self.orientationB = orientationB
        self.title = title
        var ids: [NSValue] = []
        if let trackA {
            ids.append(NSNumber(value: trackA))
        }
        if let trackB {
            ids.append(NSNumber(value: trackB))
        }
        self.requiredSourceTrackIDs = ids
        super.init()
    }
}

/// Draws each clip aspect-filled into its half, and an optional title card at the start.
final class KeepsakeCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    private let lock = NSLock()
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private var renderContext: AVVideoCompositionRenderContext?
    private var isCancelled = false
    private var cachedTitle: (key: String, image: CGImage)?

    #if compiler(>=6.0)
    var sourcePixelBufferAttributes: [String: any Sendable]? {
        pixelBufferAttributes
    }

    var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] {
        pixelBufferAttributes
    }

    private var pixelBufferAttributes: [String: any Sendable] {
        [
            kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_32BGRA),
            kCVPixelBufferMetalCompatibilityKey as String: NSNumber(value: true)
        ]
    }
    #else
    var sourcePixelBufferAttributes: [String: Any]? {
        pixelBufferAttributes
    }

    var requiredPixelBufferAttributesForRenderContext: [String: Any] {
        pixelBufferAttributes
    }

    private var pixelBufferAttributes: [String: Any] {
        [
            kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_32BGRA),
            kCVPixelBufferMetalCompatibilityKey as String: NSNumber(value: true)
        ]
    }
    #endif

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        lock.lock()
        renderContext = newRenderContext
        isCancelled = false
        lock.unlock()
    }

    func cancelAllPendingVideoCompositionRequests() {
        lock.lock()
        isCancelled = true
        lock.unlock()
    }

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        let cancelled = locked { isCancelled }
        if cancelled {
            request.finishCancelledRequest()
            return
        }
        guard let instruction = request.videoCompositionInstruction as? KeepsakeInstruction else {
            request.finish(with: CompositorError.badInstruction)
            return
        }
        let context = locked { renderContext }
        guard let context, let output = context.newPixelBuffer() else {
            request.finish(with: CompositorError.noBuffer)
            return
        }

        let width = CGFloat(CVPixelBufferGetWidth(output))
        let height = CGFloat(CVPixelBufferGetHeight(output))
        let canvas = CGRect(x: 0, y: 0, width: width, height: height)
        var image = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 1)).cropped(to: canvas)

        let seconds = CMTimeGetSeconds(request.compositionTime)
        let milliseconds = seconds.isFinite ? Int64((seconds * 1000).rounded()) : 0
        let showingTitle = instruction.title != nil && SyncMath.showsTitleCard(atMilliseconds: milliseconds, enabled: true)

        if showingTitle, let title = instruction.title,
           let card = titleCard(width: Int(width), height: Int(height), title: title) {
            var titleImage = CIImage(cgImage: card)
            let extent = titleImage.extent
            titleImage = titleImage.transformed(by: CGAffineTransform(translationX: -extent.origin.x, y: -extent.origin.y))
            image = titleImage.composited(over: image)
        } else {
            if let trackA = instruction.trackA,
               let frame = request.sourceFrame(byTrackID: trackA),
               let placed = place(frame: frame, orientation: instruction.orientationA, into: instruction.rectA, canvasHeight: height) {
                image = placed.composited(over: image)
            }
            if let trackB = instruction.trackB,
               let frame = request.sourceFrame(byTrackID: trackB),
               let placed = place(frame: frame, orientation: instruction.orientationB, into: instruction.rectB, canvasHeight: height) {
                image = placed.composited(over: image)
            }
        }

        ciContext.render(image, to: output)
        request.finish(withComposedVideoFrame: output)
    }

    private func titleCard(width: Int, height: Int, title: TitleCardContent) -> CGImage? {
        let key = "\(width)x\(height)|\(title.names)|\(title.date)"
        if let cached = locked({ cachedTitle }), cached.key == key {
            return cached.image
        }
        guard let image = TitleCardRenderer.image(width: width, height: height, names: title.names, date: title.date) else {
            return nil
        }
        locked { cachedTitle = (key, image) }
        return image
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    /// Source frames are raw encoded pixels. `orientation` turns them upright, then aspect-fill crops to the half.
    private func place(
        frame: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        into targetTopLeft: CGRect,
        canvasHeight: CGFloat
    ) -> CIImage? {
        let oriented = CIImage(cvPixelBuffer: frame).oriented(orientation)
        let extent = oriented.extent
        guard extent.width > 1, extent.height > 1, canvasHeight > 0 else { return nil }

        let target = KRect(
            x: Double(targetTopLeft.origin.x),
            y: Double(targetTopLeft.origin.y),
            width: Double(targetTopLeft.width),
            height: Double(targetTopLeft.height)
        )
        let fitted = FrameGeometry.aspectFill(
            videoSize: KSize(width: Double(extent.width), height: Double(extent.height)),
            into: target
        )
        let fittedCI = FrameGeometry.coreImageRect(fromTopLeft: fitted, canvasHeight: Double(canvasHeight))
        let cropCI = FrameGeometry.coreImageRect(fromTopLeft: target, canvasHeight: Double(canvasHeight))
        guard fittedCI.width > 0, fittedCI.height > 0 else { return nil }

        let scaleX = fittedCI.width / Double(extent.width)
        let scaleY = fittedCI.height / Double(extent.height)
        var image = oriented.transformed(by: CGAffineTransform(translationX: -extent.origin.x, y: -extent.origin.y))
        image = image.transformed(by: CGAffineTransform(scaleX: CGFloat(scaleX), y: CGFloat(scaleY)))
        image = image.transformed(by: CGAffineTransform(translationX: CGFloat(fittedCI.x), y: CGFloat(fittedCI.y)))
        return image.cropped(to: CGRect(x: cropCI.x, y: cropCI.y, width: cropCI.width, height: cropCI.height))
    }
}

private enum CompositorError: LocalizedError {
    case badInstruction
    case noBuffer

    var errorDescription: String? {
        "Could not draw the keepsake."
    }
}

enum TitleCardRenderer {
    static func image(width: Int, height: Int, names: String, date: String) -> CGImage? {
        guard width > 0, height > 0 else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        let canvas = CGSize(width: width, height: height)
        context.setFillColor(CGColor(red: 0.16, green: 0.11, blue: 0.10, alpha: 1))
        context.fill(CGRect(origin: .zero, size: canvas))

        let cream = CGColor(red: 0.96, green: 0.93, blue: 0.88, alpha: 1)
        let muted = CGColor(red: 0.78, green: 0.70, blue: 0.64, alpha: 1)
        drawCentered(
            "Keepsake",
            baseSize: canvas.width * 0.028,
            color: muted,
            baselineFromBottom: canvas.height * 0.58,
            in: context,
            canvasWidth: canvas.width
        )
        drawCentered(
            names,
            baseSize: canvas.width * 0.046,
            color: cream,
            baselineFromBottom: canvas.height * 0.48,
            in: context,
            canvasWidth: canvas.width
        )
        drawCentered(
            date,
            baseSize: canvas.width * 0.026,
            color: muted,
            baselineFromBottom: canvas.height * 0.40,
            in: context,
            canvasWidth: canvas.width
        )
        return context.makeImage()
    }

    private static func drawCentered(
        _ text: String,
        baseSize: CGFloat,
        color: CGColor,
        baselineFromBottom: CGFloat,
        in context: CGContext,
        canvasWidth: CGFloat
    ) {
        let line = fittingLine(text: text, baseSize: baseSize, color: color, maxWidth: canvasWidth * 0.86)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
        context.textPosition = CGPoint(x: (canvasWidth - width) / 2, y: baselineFromBottom)
        CTLineDraw(line, context)
    }

    private static func fittingLine(text: String, baseSize: CGFloat, color: CGColor, maxWidth: CGFloat) -> CTLine {
        var size = max(baseSize, 12)
        let minimum = max(12, baseSize * 0.45)
        var line = makeLine(text: text, size: size, color: color)
        var width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        while width > maxWidth && size > minimum {
            size *= 0.9
            line = makeLine(text: text, size: size, color: color)
            width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        }
        return line
    }

    private static func makeLine(text: String, size: CGFloat, color: CGColor) -> CTLine {
        let font = CTFontCreateWithName("Georgia" as CFString, size, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(rawValue: String(kCTFontAttributeName)): font,
            NSAttributedString.Key(rawValue: String(kCTForegroundColorAttributeName)): color
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        return CTLineCreateWithAttributedString(attributed)
    }
}
