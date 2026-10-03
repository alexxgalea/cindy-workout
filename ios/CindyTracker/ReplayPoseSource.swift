#if DEBUG
import AVFoundation
import Foundation
import CindyCore
import CindyFixtures

/// A scripted body, played back at ten frames a second.
///
/// The simulator has no camera, so nothing would ever be counted there. This feeds the same
/// synthetic poses the tests use (`CindyFixtures`) through the real view model and engine, which
/// is what the UI tests drive. It is compiled into debug builds only, and is picked with the
/// launch argument `-CindyReplay <script>`, so a release build can never be told to ignore its
/// camera.
final class ReplayPoseSource: PoseSource {

    /// A lead-in played once, then a cycle played for as long as the app runs.
    struct Script {
        let lead: [[Keypoint]]
        let cycle: [[Keypoint]]
    }

    /// A phone frame, portrait. The fixtures are drawn around the origin, so they are moved to
    /// the middle of it; nothing in the engine cares where in the frame a body is, only how big
    /// it is next to itself.
    static let frameSize = CGSize(width: 720, height: 1280)
    private static let interval: TimeInterval = 0.1

    /// Hanging, then pull-ups for ever: bottom, top, bottom, top. The first two cycles are what
    /// the setup check reads as its calibration reps.
    static func script(named name: String) -> Script? {
        switch name {
        case "pullups":
            return Script(
                lead: held(PoseFixtures.pullup(170), 10),
                cycle: held(PoseFixtures.pullup(170), 20)
            )
        default:
            return nil
        }
    }

    private static func held(_ pose: [Keypoint], _ frames: Int) -> [[Keypoint]] {
        let moved = pose.map { k in
            k.score <= 0 ? k : Keypoint(x: k.x + Float(frameSize.width / 2),
                                        y: k.y + Float(frameSize.height / 2),
                                        score: k.score)
        }
        return Array(repeating: moved, count: frames)
    }

    var onFrame: ((PoseFrame) -> Void)?
    var onRecordingChanged: ((Bool) -> Void)?
    var onRecordingFinished: ((URL?) -> Void)?
    var previewSession: AVCaptureSession? { nil }

    private let script: Script
    private var index = 0
    private var timer: Timer?

    init(script: Script) {
        self.script = script
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            self?.step()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func flip() {}
    func resetRoi() {}
    func toggleRecording() {}

    private func step() {
        let keypoints: [Keypoint]
        if index < script.lead.count {
            keypoints = script.lead[index]
        } else {
            keypoints = script.cycle[(index - script.lead.count) % script.cycle.count]
        }
        index += 1
        onFrame?(PoseFrame(keypoints: keypoints, frameSize: Self.frameSize, inferenceMs: 0, tracking: true))
    }
}
#endif
