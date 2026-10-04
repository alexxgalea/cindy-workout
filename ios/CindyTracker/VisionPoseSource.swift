import AVFoundation
import CindyCore
import CindyVision

/// Camera capture, Vision, and optional filming: the real source of the skeleton.
///
/// Reports frames in pixel space; what they mean is `CindyCore`'s problem. Vision and the camera
/// callbacks run on `queue`, and everything it reports goes to the main queue.
final class VisionPoseSource: NSObject, PoseSource {

    var onFrame: ((PoseFrame) -> Void)?
    var onRecordingChanged: ((Bool) -> Void)?
    var onRecordingFinished: ((URL?) -> Void)?

    let session = AVCaptureSession()
    var previewSession: AVCaptureSession? { session }

    private let videoOutput = AVCaptureVideoDataOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let queue = DispatchQueue(label: "cindy.camera")

    private var position: AVCaptureDevice.Position = .back

    /// The crop to look in and the skeleton in it, shared with the clip tool. Touched only on
    /// `queue`, which is where frames arrive.
    private let analyser = VisionFrameAnalyser()
    private let probe = LatencyProbe()
    /// Analysed frames wait here for the main thread: events would queue, but every frame is
    /// state, so only the newest is kept and a slow main thread costs frames, not freshness.
    private let handoff = FrameHandoff<PoseFrame>()

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
            self.orientConnection()
            self.probe.reset()
        }
    }

    func resetRoi() {
        queue.async { [weak self] in self?.analyser.reset() }
    }

    /// Frames arrive upright, in portrait, and mirrored for the selfie camera so that they match
    /// what the preview shows. Without this they arrive in the sensor's landscape orientation and
    /// every joint is a quarter turn from where the body is.
    private func orientConnection() {
        guard let connection = videoOutput.connection(with: .video) else { return }
        if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = position == .front
        }
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
        orientConnection()
        // One host clock stamps every frame on an iPhone, so there is nothing to look up.
        probe.clock.resolve()
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
        DispatchQueue.main.async { self.onRecordingChanged?(true) }
    }
}

extension VisionPoseSource: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let size = CGSize(width: width, height: height)

        // The buffer is already upright (see `orientConnection`), so nothing turns it here.
        let result = analyser.analyse(buffer)
        let points = result.keypoints
        let inferMs = result.inferMs

        let stamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let age = probe.clock.sinceCapture(Int64(CMTimeGetSeconds(stamp) * 1_000_000_000))
        probe.analysed(captureAgeMs: age, convertMs: 0, prepMs: 0, inferMs: inferMs)

        var frame = PoseFrame(keypoints: points, frameSize: size, inferenceMs: Int(inferMs), tracking: result.tracking)
        frame.captureAgeMs = age.map(Int.init)
        frame.latencyLine = probe.line(model: "vision", drawnPerSecond: nil)
        let outcome = handoff.submit(frame, isEvent: false)
        probe.posted(replacedUnrendered: outcome == .replacedPending)
        if outcome == .schedule {
            DispatchQueue.main.async { [weak self] in
                self?.handoff.drain { self?.onFrame?($0) }
            }
        }
    }
}

extension VisionPoseSource: AVCaptureFileOutputRecordingDelegate {

    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection],
                    error: Error?) {
        DispatchQueue.main.async {
            self.onRecordingChanged?(false)
            self.onRecordingFinished?(error == nil ? outputFileURL : nil)
        }
    }
}
