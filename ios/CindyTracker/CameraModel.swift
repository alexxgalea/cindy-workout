import AVFoundation
import Combine
import Vision
import CindyCore

/// Camera capture, pose detection and optional filming.
///
/// Publishes keypoints in frame-pixel space; what they mean is `CindyCore`'s problem.
final class CameraModel: NSObject, ObservableObject {

    @Published private(set) var keypoints: [Keypoint] = []
    @Published private(set) var frameSize: CGSize = .zero
    @Published private(set) var isRecording = false
    @Published private(set) var tracking = false
    @Published private(set) var lastInferenceMs: Int = 0

    let session = AVCaptureSession()

    private let videoOutput = AVCaptureVideoDataOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let queue = DispatchQueue(label: "cindy.camera")
    private let request = VNDetectHumanBodyPoseRequest()

    private var position: AVCaptureDevice.Position = .back
    private var roi: CGRect?
    private var misses = 0

    /// Called with the saved file's URL, or nil if filming failed.
    var onRecordingFinished: ((URL?) -> Void)?

    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            self.configure()
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.session.stopRunning()
        }
    }

    func flip() {
        position = position == .back ? .front : .back
        resetRoi()
        queue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.inputs.forEach { self.session.removeInput($0) }
            self.addInput()
            self.session.commitConfiguration()
        }
    }

    /// Forgets the tracked crop — call when the camera changes or a workout restarts.
    func resetRoi() {
        roi = nil
        misses = 0
        DispatchQueue.main.async { self.tracking = false }
    }

    private func configure() {
        guard session.inputs.isEmpty else { return }
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720
        addInput()

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
        if session.canAddOutput(movieOutput) { session.addOutput(movieOutput) }
        session.commitConfiguration()
    }

    private func addInput() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)
    }

    // MARK: - filming

    func toggleRecording() {
        if movieOutput.isRecording {
            movieOutput.stopRecording()
            return
        }
        let name = "cindy-\(Int(Date().timeIntervalSince1970)).mov"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        movieOutput.startRecording(to: url, recordingDelegate: self)
        DispatchQueue.main.async { self.isRecording = true }
    }
}

extension CameraModel: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let size = CGSize(
            width: CVPixelBufferGetWidth(buffer),
            height: CVPixelBufferGetHeight(buffer)
        )

        let region = roi
        request.regionOfInterest = region ?? CGRect(x: 0, y: 0, width: 1, height: 1)

        let started = CFAbsoluteTimeGetCurrent()
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:])
        try? handler.perform([request])
        let elapsed = Int((CFAbsoluteTimeGetCurrent() - started) * 1000)

        let points: [Keypoint]
        if let observation = request.results?.first {
            points = VisionPose.keypoints(
                from: observation,
                size: size,
                roi: region ?? CGRect(x: 0, y: 0, width: 1, height: 1)
            )
        } else {
            points = Array(repeating: .missing, count: KP.count)
        }

        // Follow the body, and give up on the crop if it is lost for a few frames running.
        if let next = VisionPose.regionOfInterest(around: points, size: size) {
            roi = next
            misses = 0
        } else {
            misses += 1
            if misses >= 5 { roi = nil }
        }

        let isTracking = roi != nil
        DispatchQueue.main.async {
            self.keypoints = points
            self.frameSize = size
            self.lastInferenceMs = elapsed
            self.tracking = isTracking
        }
    }
}

extension CameraModel: AVCaptureFileOutputRecordingDelegate {

    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection],
                    error: Error?) {
        DispatchQueue.main.async {
            self.isRecording = false
            self.onRecordingFinished?(error == nil ? outputFileURL : nil)
        }
    }
}
