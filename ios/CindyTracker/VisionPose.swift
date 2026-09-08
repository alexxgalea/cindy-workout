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
    ///   - size: pixel size of the frame the observation came from.
    ///   - roi: the region the request was restricted to, in Vision's normalised bottom-left
    ///     space. Points come back relative to it, so they need mapping out again.
    static func keypoints(from observation: VNHumanBodyPoseObservation,
                          size: CGSize,
                          roi: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)) -> [Keypoint] {
        let recognised = (try? observation.recognizedPoints(.all)) ?? [:]
        return order.map { name in
            guard let p = recognised[name], p.confidence > 0 else { return .missing }
            // Undo the ROI, then flip: Vision's origin is bottom-left, ours is top-left.
            let nx = roi.minX + p.location.x * roi.width
            let ny = roi.minY + p.location.y * roi.height
            return Keypoint(
                x: Float(nx * size.width),
                y: Float((1 - ny) * size.height),
                score: Float(p.confidence)
            )
        }
    }

    /// A square crop around the body, in Vision's normalised bottom-left space.
    ///
    /// Same reasoning as the Android build: a phone standing on the floor leaves the athlete in a
    /// slice of a tall frame, and a detector given the whole frame spends its resolution on
    /// ceiling and carpet.
    static func regionOfInterest(around k: [Keypoint], size: CGSize) -> CGRect? {
        let seen = k.filter { $0.score >= 0.3 }
        guard seen.count >= 5, size.width > 0, size.height > 0 else { return nil }

        let minX = CGFloat(seen.map(\.x).min()!) / size.width
        let maxX = CGFloat(seen.map(\.x).max()!) / size.width
        // Flip back into Vision's space while converting.
        let minY = 1 - CGFloat(seen.map(\.y).max()!) / size.height
        let maxY = 1 - CGFloat(seen.map(\.y).min()!) / size.height

        let margin: CGFloat = 1.45
        let side = min(1, max(maxX - minX, maxY - minY) * margin)
        let cx = (minX + maxX) / 2
        let cy = (minY + maxY) / 2
        let half = side / 2
        return CGRect(
            x: min(max(0, cx - half), 1 - side),
            y: min(max(0, cy - half), 1 - side),
            width: side,
            height: side
        )
    }
}
