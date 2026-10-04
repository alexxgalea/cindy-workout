#if canImport(Vision)
import Foundation
import Vision
import CoreVideo
import CindyCore

/// One frame in, one skeleton out: the crop to look in, Vision, and following the body to the
/// next frame. The camera calls it for every frame it captures and `cindy-clips` calls it for
/// every frame of a recorded clip, so a clip is scored by the code the phone runs.
///
/// Not thread-safe. Give it one queue, which is what frames arrive on anyway.
public final class VisionFrameAnalyser {

    public struct Analysis {
        public let keypoints: [Keypoint]
        /// Whether a crop around the body was being followed for this frame.
        public let tracking: Bool
        /// How long Vision took, in milliseconds.
        public let inferMs: Int64
    }

    private let request = VNDetectHumanBodyPoseRequest()
    private let tracker = RoiTracker()

    public init() {}

    /// Back to looking at the whole frame, as after the camera is flipped.
    public func reset() { tracker.reset() }

    /// - Parameter buffer: an upright frame. Nothing here rotates it, so a source that delivers
    ///   a sensor's landscape frames has to turn them first.
    public func analyse(_ buffer: CVPixelBuffer) -> Analysis {
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let size = CGSize(width: width, height: height)

        // The crop this frame is analysed in, and whether it is a tracked one, are settled before
        // detection and read after it for this same frame.
        let region = tracker.beginFrame(frameWidth: width, frameHeight: height)
        let tracking = tracker.tracking
        let roi = VisionGeometry.regionOfInterest(for: tracking ? region : nil,
                                                  frameWidth: width, frameHeight: height)
        request.regionOfInterest = CGRect(x: roi.x, y: roi.y, width: roi.width, height: roi.height)

        let started = monotonicNanos()
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:])
        // A request that throws leaves the previous frame's results on it, which must not be read
        // as this frame's skeleton.
        let performed: Bool
        do { try handler.perform([request]); performed = true } catch { performed = false }
        let inferMs = (monotonicNanos() - started) / 1_000_000

        let points: [Keypoint]
        if performed, let observation = request.results?.first {
            points = VisionPose.keypoints(from: observation, size: size, roi: roi)
        } else {
            points = Array(repeating: .missing, count: KP.count)
        }

        // Follow the body, and give up on the crop if it is lost for a few frames running.
        tracker.update(points, frameWidth: width, frameHeight: height)
        return Analysis(keypoints: points, tracking: tracking, inferMs: inferMs)
    }
}
#endif
