import AVFoundation
import Combine
import CindyCore

/// What the screens watch: the latest skeleton and the state of filming, from whichever
/// `PoseSource` is feeding it.
///
/// Publishes keypoints in frame-pixel space; what they mean is `CindyCore`'s problem.
final class CameraModel: ObservableObject {

    @Published private(set) var keypoints: [Keypoint] = []
    @Published private(set) var frameSize: CGSize = .zero
    @Published private(set) var isRecording = false
    @Published private(set) var tracking = false
    @Published private(set) var lastInferenceMs: Int = 0
    @Published private(set) var sourceName = "Vision"
    @Published private(set) var captureAgeMs: Int?
    @Published private(set) var latencyLine = ""

    /// What the preview layer shows. Empty, and so black, when the source has no camera.
    let session: AVCaptureSession

    private let source: PoseSource

    /// Called with every analysed frame, whole: the skeleton, whether its crop was a tracked one,
    /// and how it was timed. The workout reads this rather than watching `keypoints`, because a
    /// separate watch on each published value would see them one at a time and out of step.
    var onPoseFrame: ((PoseFrame) -> Void)?

    /// Called with the saved file's URL, or nil if filming failed.
    var onRecordingFinished: ((URL?) -> Void)? {
        get { source.onRecordingFinished }
        set { source.onRecordingFinished = newValue }
    }

    init(source: PoseSource = CameraModel.defaultSource()) {
        self.source = source
        session = source.previewSession ?? AVCaptureSession()
        source.onFrame = { [weak self] frame in
            guard let self else { return }
            keypoints = frame.keypoints
            frameSize = frame.frameSize
            lastInferenceMs = frame.inferenceMs
            tracking = frame.tracking
            sourceName = frame.source
            captureAgeMs = frame.captureAgeMs
            latencyLine = frame.latencyLine
            onPoseFrame?(frame)
        }
        source.onRecordingChanged = { [weak self] recording in self?.isRecording = recording }
    }

    func start() { source.start() }
    func stop() { source.stop() }

    func flip() {
        source.flip()
        resetRoi()
    }

    /// Forgets the tracked crop: call when the camera changes or a workout restarts.
    func resetRoi() {
        source.resetRoi()
        tracking = false
    }

    func toggleRecording() { source.toggleRecording() }

    /// The camera, unless a debug build was launched with `-CindyReplay <script>`.
    private static func defaultSource() -> PoseSource {
        #if DEBUG
        let arguments = CommandLine.arguments
        if let flag = arguments.firstIndex(of: "-CindyReplay"), flag + 1 < arguments.count,
           let script = ReplayPoseSource.script(named: arguments[flag + 1]) {
            return ReplayPoseSource(script: script)
        }
        #endif
        return VisionPoseSource()
    }
}
