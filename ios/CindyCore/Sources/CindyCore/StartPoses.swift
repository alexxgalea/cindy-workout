import Foundation

/// The start position of each movement, as poses rather than as a sentence.
///
/// The athlete is told "Hang from the bar" or "Get set on the floor" already; what the words cannot
/// carry is what that looks like, which is exactly the thing someone unsure of the app needs. So
/// each movement gets a short loop that walks into its own starting position and holds there.
///
/// ### Why this and not a video
///
/// These are joints, not frames: thirteen of them, the same thirteen the skeleton overlay already
/// draws, three keyframes per movement. The whole table below is about two kilobytes, it takes the
/// theme's colours like anything else drawn, and it is rendered by code that already exists — so
/// the demonstrator and the athlete's own skeleton are drawn in one visual language and "match
/// this" needs no caption.
///
/// Coordinates are in each movement's own box, y down, and carry a **z** so the figure can be
/// turned: the view rotates about the vertical axis and projects, which is what gives it depth
/// without a mesh. Left-hand joints sit at negative z, right-hand at positive.
///
/// If motion capture is ever wanted, this table is the format to fill: run a clip through the
/// Python harness in `tools/video_regression` and keep the keypoints it emits.
///
/// The numbers are Kotlin's `StartPoses`, copied by script and checked against it, so the two
/// platforms show the same figure.
public enum StartPoses {

    /// Indices into a pose's flat `x, y, z` triples.
    public static let nose = 0
    public static let lShoulder = 1
    public static let rShoulder = 2
    public static let lElbow = 3
    public static let rElbow = 4
    public static let lWrist = 5
    public static let rWrist = 6
    public static let lHip = 7
    public static let rHip = 8
    public static let lKnee = 9
    public static let rKnee = 10
    public static let lAnkle = 11
    public static let rAnkle = 12

    public static let joints = 13

    /// Pairs of joint indices to stroke, in back-to-front order within each side.
    public static let bones: [[Int]] = [
        [lShoulder, lElbow], [lElbow, lWrist],
        [rShoulder, rElbow], [rElbow, rWrist],
        [lShoulder, rShoulder], [lHip, rHip],
        [lShoulder, lHip], [rShoulder, rHip],
        [lHip, lKnee], [lKnee, lAnkle],
        [rHip, rKnee], [rKnee, rAnkle]
    ]

    /// One movement's loop.
    ///
    /// `frames` runs approach, approach, and then the position itself, which is the one held.
    /// `barY` is drawn only where there is a bar to hang from.
    public struct Loop: Sendable {
        public let boxWidth: Float
        public let boxHeight: Float
        public let groundY: Float
        public let barY: Float?
        public let headRadius: Float
        public let frames: [[Float]]
    }

    public static func of(_ exercise: Exercise) -> Loop {
        switch exercise {
        case .pullup: return pullUp
        case .pushup: return pushUp
        case .squat: return squat
        }
    }

    public static let pullUp = Loop(
        boxWidth: 180, boxHeight: 210, groundY: 202, barY: 20, headRadius: 11,
        frames: [
            [
                90, 86, 2,
                81, 104, -8,
                99, 104, 8,
                78, 74, -8,
                102, 74, 8,
                81, 44, -8,
                99, 44, 8,
                84, 142, -8,
                96, 142, 8,
                83, 172, -8,
                97, 172, 8,
                82, 202, -8,
                98, 202, 8
            ],
            [
                90, 80, 2,
                81, 92, -8,
                99, 92, 8,
                78, 54, -8,
                102, 54, 8,
                80, 20, -8,
                100, 20, 8,
                84, 134, -8,
                96, 134, 8,
                83, 168, -8,
                97, 168, 8,
                82, 202, -8,
                98, 202, 8
            ],
            [
                90, 74, 2,
                81, 86, -8,
                99, 86, 8,
                78, 52, -8,
                102, 52, 8,
                80, 20, -8,
                100, 20, 8,
                84, 130, -8,
                96, 130, 8,
                83, 164, -8,
                97, 164, 8,
                86, 188, -8,
                94, 188, 8
            ]
        ]
    )

    public static let pushUp = Loop(
        boxWidth: 210, boxHeight: 150, groundY: 132, barY: nil, headRadius: 10,
        frames: [
            [
                44, 72, 2,
                60, 82, -7,
                58, 84, 7,
                58, 106, -7,
                56, 108, 7,
                56, 132, -7,
                54, 132, 7,
                110, 88, -7,
                108, 90, 7,
                140, 132, -7,
                138, 132, 7,
                164, 120, -7,
                162, 122, 7
            ],
            [
                44, 78, 2,
                60, 88, -7,
                58, 90, 7,
                58, 110, -7,
                56, 112, 7,
                56, 132, -7,
                54, 132, 7,
                108, 96, -7,
                106, 98, 7,
                138, 118, -7,
                136, 120, 7,
                164, 132, -7,
                162, 132, 7
            ],
            [
                42, 84, 2,
                58, 94, -7,
                56, 96, 7,
                56, 113, -7,
                54, 115, 7,
                54, 132, -7,
                52, 132, 7,
                106, 104, -7,
                104, 106, 7,
                136, 118, -7,
                134, 120, 7,
                164, 132, -7,
                162, 132, 7
            ]
        ]
    )

    public static let squat = Loop(
        boxWidth: 180, boxHeight: 190, groundY: 170, barY: nil, headRadius: 11,
        frames: [
            [
                90, 60, 2,
                80, 80, -8,
                100, 81, 8,
                70, 98, -8,
                110, 98, 8,
                72, 114, -8,
                108, 114, 8,
                84, 120, -8,
                96, 120, 8,
                77, 144, -8,
                103, 144, 8,
                81, 170, -8,
                99, 170, 8
            ],
            [
                90, 47, 2,
                80, 67, -8,
                100, 68, 8,
                72, 89, -8,
                108, 89, 8,
                72, 109, -8,
                108, 109, 8,
                83, 110, -8,
                97, 110, 8,
                79, 139, -8,
                101, 139, 8,
                81, 170, -8,
                99, 170, 8
            ],
            [
                90, 34, 2,
                80, 54, -8,
                100, 55, 8,
                75, 80, -8,
                105, 80, 8,
                73, 104, -8,
                107, 104, 8,
                83, 100, -8,
                97, 100, 8,
                82, 135, -8,
                98, 135, 8,
                81, 170, -8,
                99, 170, 8
            ]
        ]
    )
}
