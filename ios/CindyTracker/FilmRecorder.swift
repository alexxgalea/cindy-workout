import AVFoundation
import CoreImage
import UIKit
import CindyCore

/// What the film shows over the picture, handed from the main thread to the camera's queue.
final class FilmOverlayFeed: @unchecked Sendable {
    private let lock = NSLock()
    private var hud = RecordedHudText(clock: "20:00", round: "ROUND 1", label: "", count: "0 / 5")

    func set(_ next: RecordedHudText) {
        lock.lock()
        hud = next
        lock.unlock()
    }

    func current() -> RecordedHudText {
        lock.lock()
        defer { lock.unlock() }
        return hud
    }
}

/// Films the workout, with the skeleton, the clock, the round, the movement, the count and the
/// CINDY watermark burned into every frame. Video only: no audio, so no microphone permission, and
/// nothing to record the app's own voice counting back at the athlete.
///
/// Every method is called on the camera's queue, which is also where frames arrive.
///
/// ### Coordinates
///
/// Android draws in the analysis frame's upright space and maps it onto a recorded buffer that may
/// differ in size, crop, rotation and mirroring. Here the same buffer feeds the analysis and the
/// film, upright and mirrored for the selfie camera exactly as the preview is, so the keypoints are
/// already in the film's own pixels and the map is the identity. `OverlayTransform` is still the one
/// that says so, so a recording that is ever scaled or cropped has a place to say that too.
///
/// Text is laid out by `RecordingLayout` in `OverlayTransform.visibleSource`, never in the frame.
final class FilmRecorder {

    private let url: URL
    private let feed: FilmOverlayFeed
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var failed = false
    private var lastTime = CMTime.invalid
    /// Draws the camera's frame into a buffer the overlay can be painted on, whatever the camera's
    /// own pixel format is. Only a filming session pays for it.
    private let context = CIContext()

    init(url: URL, feed: FilmOverlayFeed) {
        self.url = url
        self.feed = feed
    }

    /// Adds one frame with its skeleton. A frame that cannot be written is dropped, and a writer that
    /// has failed stays failed: counting carries on, as Android's recorder degrades.
    func append(_ sample: CMSampleBuffer, keypoints: [Keypoint]) {
        guard !failed, let source = CMSampleBufferGetImageBuffer(sample) else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sample)
        if writer == nil, !open(like: source, at: time) {
            failed = true
            return
        }
        guard let writer, let input, let adaptor, writer.status == .writing else {
            failed = true
            return
        }
        guard input.isReadyForMoreMediaData, !lastTime.isValid || time > lastTime,
              let pool = adaptor.pixelBufferPool else { return }
        var made: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &made)
        guard let target = made else { return }

        context.render(CIImage(cvPixelBuffer: source), to: target)
        paint(on: target, keypoints: keypoints)
        if adaptor.append(target, withPresentationTime: time) {
            lastTime = time
        } else {
            failed = true
        }
    }

    /// Ends the film and says where it is, or `nil` if there is nothing worth keeping: no frame ever
    /// arrived, or the writer failed on the way.
    func finish(_ done: @escaping (URL?) -> Void) {
        guard let writer, let input, !failed, writer.status == .writing else {
            writer?.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            done(nil)
            return
        }
        input.markAsFinished()
        writer.finishWriting { [url] in
            if writer.status == .completed {
                done(url)
            } else {
                try? FileManager.default.removeItem(at: url)
                done(nil)
            }
        }
    }

    // MARK: - the file

    /// Sizes the file to the first frame: that is the first moment the camera has said how big it is.
    private func open(like buffer: CVPixelBuffer, at time: CMTime) -> Bool {
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        try? FileManager.default.removeItem(at: url)
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return false }
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: max(4_000_000, width * height * 5),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoExpectedSourceFrameRateKey: 30,
            ] as [String: Any],
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ])
        guard writer.canAdd(input) else { return false }
        writer.add(input)
        guard writer.startWriting() else { return false }
        writer.startSession(atSourceTime: time)
        self.writer = writer
        self.input = input
        self.adaptor = adaptor
        return true
    }

    // MARK: - the overlay

    private static let accent = UIColor(white: 1, alpha: 168 / 255)
    private static let faint = UIColor(white: 1, alpha: 150 / 255)
    private static let panel = UIColor(white: 0, alpha: 150 / 255)

    private func paint(on buffer: CVPixelBuffer, keypoints: [Keypoint]) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        guard let cg = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return }
        // The top left is the origin, as in the frame the keypoints are in.
        cg.translateBy(x: 0, y: CGFloat(height))
        cg.scaleBy(x: 1, y: -1)

        let map = OverlayTransform.build(srcWidth: width, srcHeight: height, bufferWidth: width,
                                         bufferHeight: height, rotationDegrees: 0, mirror: false)
        drawSkeleton(cg, keypoints, map: map, height: CGFloat(height))

        let safe = OverlayTransform.visibleSource(srcWidth: width, srcHeight: height, bufferWidth: width,
                                                  bufferHeight: height, rotationDegrees: 0)
        // UIKit draws text the right way up only in a UIKit-flipped context, which this is.
        UIGraphicsPushContext(cg)
        drawWords(cg, RecordingLayout.make(hud: feed.current(), safe: safe, measure: Self.measure))
        UIGraphicsPopContext()
    }

    private func drawSkeleton(_ cg: CGContext, _ keypoints: [Keypoint], map: Affine, height: CGFloat) {
        guard keypoints.count == KP.count else { return }
        func point(_ k: Keypoint) -> CGPoint {
            CGPoint(x: CGFloat(map.mapX(k.x, k.y)), y: CGFloat(map.mapY(k.x, k.y)))
        }
        cg.setLineCap(.round)
        cg.setLineWidth(height * CGFloat(RecordingLayout.boneWidthFraction))
        cg.setStrokeColor(Self.accent.cgColor)
        for (a, b) in KP.skeleton {
            let pa = keypoints[a], pb = keypoints[b]
            guard pa.score >= RecordingLayout.minScore, pb.score >= RecordingLayout.minScore else { continue }
            cg.move(to: point(pa))
            cg.addLine(to: point(pb))
            cg.strokePath()
        }
        let r = height * CGFloat(RecordingLayout.jointRadiusFraction)
        cg.setFillColor(UIColor.white.cgColor)
        for k in keypoints where k.score >= RecordingLayout.minScore {
            let p = point(k)
            cg.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        }
    }

    private func drawWords(_ cg: CGContext, _ layout: RecordingLayout) {
        for panel in layout.panels {
            let rect = CGRect(x: CGFloat(panel.rect.left), y: CGFloat(panel.rect.top),
                              width: CGFloat(panel.rect.width), height: CGFloat(panel.rect.height))
            Self.panel.setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: rect.height * CGFloat(panel.radius)).fill()
        }
        for word in layout.texts {
            let font = Self.font(word.size)
            let colour: UIColor
            switch word.tone {
            case .white: colour = .white
            case .accent: colour = Self.accent
            case .faint: colour = Self.faint
            }
            let text = word.text as NSString
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: colour]
            let width = text.size(withAttributes: attributes).width
            var x = CGFloat(word.x)
            switch word.align {
            case .left: break
            case .right: x -= width
            case .center: x -= width / 2
            }
            // `baseline` is where the letters sit; UIKit places the top of the line.
            text.draw(at: CGPoint(x: x, y: CGFloat(word.baseline) - font.ascender), withAttributes: attributes)
        }
    }

    /// Figures the same width, so a clock that ticks does not shiver.
    private static func font(_ size: Float) -> UIFont {
        UIFont.monospacedDigitSystemFont(ofSize: CGFloat(size), weight: .bold)
    }

    private static let measure: RecordingLayout.Measure = { text, size in
        Float((text as NSString).size(withAttributes: [.font: font(size)]).width)
    }
}
