import Foundation

/// A single COCO keypoint, in the coordinate space of the source frame (pixels, y downward).
public struct Keypoint: Equatable, Sendable {
    public let x: Float
    public let y: Float
    public let score: Float

    public init(x: Float, y: Float, score: Float) {
        self.x = x
        self.y = y
        self.score = score
    }

    public static let missing = Keypoint(x: 0, y: 0, score: 0)
}

/// COCO-17 keypoint indices, matching the order the Android build uses so the two stay comparable.
public enum KP {
    public static let nose = 0
    public static let leftEye = 1
    public static let rightEye = 2
    public static let leftEar = 3
    public static let rightEar = 4
    public static let leftShoulder = 5
    public static let rightShoulder = 6
    public static let leftElbow = 7
    public static let rightElbow = 8
    public static let leftWrist = 9
    public static let rightWrist = 10
    public static let leftHip = 11
    public static let rightHip = 12
    public static let leftKnee = 13
    public static let rightKnee = 14
    public static let leftAnkle = 15
    public static let rightAnkle = 16
    public static let count = 17

    /// Bone list used to draw the skeleton.
    public static let skeleton: [(Int, Int)] = [
        (leftShoulder, rightShoulder),
        (leftShoulder, leftElbow), (leftElbow, leftWrist),
        (rightShoulder, rightElbow), (rightElbow, rightWrist),
        (leftShoulder, leftHip), (rightShoulder, rightHip),
        (leftHip, rightHip),
        (leftHip, leftKnee), (leftKnee, leftAnkle),
        (rightHip, rightKnee), (rightKnee, rightAnkle)
    ]
}
