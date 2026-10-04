import Foundation
import CindyCore

/// One analysed frame of a clip: what a pose source made of it, and what the engine is told.
public struct ClipFrame: Equatable, Sendable {
    public var timestampMs: Int64
    public var width: Int
    public var height: Int
    /// Whether the crop was being followed for this frame. The engine takes it as `identityStable`.
    public var trackingStable: Bool
    public var keypoints: [Keypoint]
    /// What the source had to brighten the frame by. Vision has no such step, so it is always 1.
    public var softGain: Float

    public init(timestampMs: Int64, width: Int, height: Int, trackingStable: Bool,
                keypoints: [Keypoint], softGain: Float = 1) {
        self.timestampMs = timestampMs
        self.width = width
        self.height = height
        self.trackingStable = trackingStable
        self.keypoints = keypoints
        self.softGain = softGain
    }
}

/// Why a clip could not be scored here, which is not the same as a clip scoring badly.
public struct ClipUnavailable: Error, Equatable {
    public let reason: String
    public init(_ reason: String) { self.reason = reason }
}

/// A clip that is there and could not be read.
public struct ClipUnreadable: Error, Equatable {
    public let reason: String
    public init(_ reason: String) { self.reason = reason }
}

/// Turns a video file into frames. Every frame, at the file's own rate, as `run_batch.py` and the
/// Android job both do: a clip is not thinned to every second frame for this comparison.
public protocol ClipFrameSource {
    /// Throws `ClipUnavailable` when this source cannot do the job at all (so the scenario is
    /// skipped), and `ClipUnreadable` when it can and the file is broken (so it fails).
    func frames(of video: URL, light: Light?) async throws -> [ClipFrame]
}
