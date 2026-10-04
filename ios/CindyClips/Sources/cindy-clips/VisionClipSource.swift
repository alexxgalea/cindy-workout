#if canImport(Vision) && canImport(AVFoundation)
import AVFoundation
import CoreVideo
import CindyCore
import CindyVision
import ClipScoring

/// Decodes a clip and runs `VisionFrameAnalyser` over every frame of it, in order, as the camera
/// would deliver them.
struct VisionClipSource: ClipFrameSource {

    func frames(of video: URL, light: Light?) async throws -> [ClipFrame] {
        let asset = AVURLAsset(url: video)
        let track: AVAssetTrack
        let fps: Double
        do {
            guard let first = try await asset.loadTracks(withMediaType: .video).first else {
                throw ClipUnreadable("cannot open video: \(video.path)")
            }
            track = first
            fps = Double(try await track.load(.nominalFrameRate))
        } catch let unreadable as ClipUnreadable {
            throw unreadable
        } catch {
            throw ClipUnreadable("cannot open video: \(video.path) (\(error.localizedDescription))")
        }
        guard fps > 0 else { throw ClipUnreadable("video has no usable FPS metadata: \(video.path)") }

        let reader: AVAssetReader
        do { reader = try AVAssetReader(asset: asset) } catch {
            throw ClipUnreadable("cannot read video: \(video.path) (\(error.localizedDescription))")
        }
        // The composition carries the track's rotation, so a clip filmed in portrait comes out
        // upright, as the camera's frames do, and nothing downstream has to know about it.
        let output = AVAssetReaderVideoCompositionOutput(
            videoTracks: [track],
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        output.videoComposition = AVMutableVideoComposition(propertiesOf: asset)
        guard reader.canAdd(output) else { throw ClipUnreadable("cannot decode video: \(video.path)") }
        reader.add(output)
        guard reader.startReading() else {
            throw ClipUnreadable("cannot decode video: \(video.path) (\(reader.error?.localizedDescription ?? "unknown"))")
        }

        let analyser = VisionFrameAnalyser()
        // Seeded, so a fixture that adds sensor noise still fails and passes for the same reasons.
        var noise = SeededNormal(seed: 7)
        var frames: [ClipFrame] = []
        while let sample = output.copyNextSampleBuffer() {
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            if let light { dim(buffer, light, &noise) }
            let result = analyser.analyse(buffer)
            frames.append(ClipFrame(
                timestampMs: Int64(Double(frames.count) * 1000.0 / fps),
                width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer),
                trackingStable: result.tracking, keypoints: result.keypoints))
        }
        if reader.status == .failed {
            throw ClipUnreadable("video stopped decoding: \(video.path) (\(reader.error?.localizedDescription ?? "unknown"))")
        }
        return frames
    }

    private func dim(_ buffer: CVPixelBuffer, _ light: Light, _ noise: inout SeededNormal) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }
        let bytes = UnsafeMutableBufferPointer(start: base.assumingMemoryBound(to: UInt8.self),
                                               count: CVPixelBufferGetBytesPerRow(buffer) * CVPixelBufferGetHeight(buffer))
        LightModel.apply(light, to: bytes, noise: &noise)
    }
}
#endif
