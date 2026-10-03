import AVFoundation
import Vision
import CindyCore

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
    private let request = VNDetectHumanBodyPoseRequest()

    private var position: AVCaptureDevice.Position = .back
    private var roi: CGRect?
    private var misses = 0

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

    func resetRoi() {
        roi = nil
        misses = 0
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
        DispatchQueue.main.async { self.onRecordingChanged?(true) }
    }
}

extension VisionPoseSource: AVCaptureVideoDataOutputSampleBufferDelegate {

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

        let frame = PoseFrame(keypoints: points, frameSize: size, inferenceMs: elapsed, tracking: roi != nil)
        DispatchQueue.main.async { self.onFrame?(frame) }
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
