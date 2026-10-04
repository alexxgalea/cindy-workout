#if canImport(Vision)
import Foundation
import Vision
import CindyCore

/// Turns Vision's body-pose observation into the same 17-point layout the Android build uses.
///
/// iOS needs no bundled model: `VNDetectHumanBodyPoseRequest` is part of the system, and its
/// joints map one-for-one onto COCO-17. That is the one place the two platforms genuinely differ
/// — everything downstream of this file is the shared logic in `CindyCore`.
enum VisionPose {

    /// Vision joints in COCO-17 order.
    private static let order: [VNHumanBodyPoseObservation.JointName] = [
        .nose, .leftEye, .rightEye, .leftEar, .rightEar,
        .leftShoulder, .rightShoulder, .leftElbow, .rightElbow,
        .leftWrist, .rightWrist, .leftHip, .rightHip,
        .leftKnee, .rightKnee, .leftAnkle, .rightAnkle
    ]

    /// - Parameters:
    ///   - size: pixel size of the upright frame the observation came from.
    ///   - roi: the region the request was restricted to. Points come back relative to it, so
    ///     they need mapping out again, and Vision's bottom-left origin flipped to top-left;
    ///     `VisionGeometry` does both and is tested.
    static func keypoints(from observation: VNHumanBodyPoseObservation,
                          size: CGSize,
                          roi: NormalisedRect = .full) -> [Keypoint] {
        let recognised = (try? observation.recognizedPoints(.all)) ?? [:]
        return order.map { name in
            guard let p = recognised[name], p.confidence > 0 else { return .missing }
            let point = VisionGeometry.pixel(
                x: Double(p.location.x), y: Double(p.location.y), roi: roi,
                frameWidth: Int(size.width), frameHeight: Int(size.height))
            return Keypoint(x: point.x, y: point.y, score: Float(p.confidence))
        }
    }
}
#endif
