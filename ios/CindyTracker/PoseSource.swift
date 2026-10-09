import AVFoundation
import CindyCore

/// One analysed frame: where the joints are, in the pixels of the frame they came from.
struct PoseFrame {
    let keypoints: [Keypoint]
    let frameSize: CGSize
    let inferenceMs: Int
    /// Whether the crop this frame was analysed in was a tracked one rather than the whole frame.
    let tracking: Bool
    /// Where the skeleton came from, for the debug readout.
    var source = "Vision"
    /// How old the frame was when the skeleton was ready, or nil when the clock cannot say.
    var captureAgeMs: Int?
    /// The latency probe's two-line summary, for the debug readout.
    var latencyLine = ""
}

/// Where the skeleton comes from. The app does not care whether it is Vision looking at a
/// camera or a script playing a body back: everything downstream sees `PoseFrame`s.
///
/// That is what lets the simulator, which has no camera, run a whole workout.
///
/// Every callback is delivered on the main queue.
protocol PoseSource: AnyObject {
    var onFrame: ((PoseFrame) -> Void)? { get set }
    var onRecordingChanged: ((Bool) -> Void)? { get set }
    /// Called with the saved file's URL, or nil if filming failed.
    var onRecordingFinished: ((URL?) -> Void)? { get set }

    /// What the preview layer shows, or nil when there is no camera to show.
    var previewSession: AVCaptureSession? { get }

    /// Whether this source reads the camera, and so needs the athlete's permission for it. A script
    /// playing a body back does not.
    var needsCameraPermission: Bool { get }

    func start()
    func stop()
    /// Switches between the rear and the selfie camera. Nothing to do without a camera.
    func flip()
    /// Forgets the tracked crop: call when the camera changes or a workout restarts.
    func resetRoi()

    /// Whether there is a camera running to film with.
    var canRecord: Bool { get }
    /// Starts filming to a file of its own, and says whether it did. The file is reported to
    /// `onRecordingFinished` once `stopRecording` has closed it.
    func startRecording() -> Bool
    func stopRecording()
    /// What the film shows over the picture from the next frame on.
    func updateOverlay(_ hud: RecordedHudText)
}

extension PoseSource {
    var needsCameraPermission: Bool { true }

    // A script playing a body back has no picture to film.
    var canRecord: Bool { false }
    func startRecording() -> Bool { false }
    func stopRecording() {}
    func updateOverlay(_ hud: RecordedHudText) {}
}
