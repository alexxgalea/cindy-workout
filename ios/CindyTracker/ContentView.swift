import AVFoundation
import SwiftUI
import UIKit
import CindyCore

/// The live camera feed behind the HUD.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.layer.session = session
        view.layer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        override var layer: AVCaptureVideoPreviewLayer { super.layer as! AVCaptureVideoPreviewLayer }
    }
}

/// The detected skeleton, mapped the same way the preview fills the screen.
///
/// The map is `OverlayTransform.build`, the one the recording uses and the tests pin, with the
/// preview's `resizeAspectFill` as its fit. Bones are 0.45% of the frame's height thick and joints
/// 0.55% in radius, so they keep their proportions whatever the screen.
struct SkeletonOverlay: View {
    let keypoints: [Keypoint]
    let frameSize: CGSize

    private static let minScore: Float = 0.3
    private static let boneWidth: CGFloat = 0.0045
    private static let jointRadius: CGFloat = 0.0055

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                guard frameSize.width > 0, frameSize.height > 0, keypoints.count == KP.count else { return }
                let map = OverlayTransform.build(
                    srcWidth: Int(frameSize.width), srcHeight: Int(frameSize.height),
                    bufferWidth: Int(size.width.rounded()), bufferHeight: Int(size.height.rounded()),
                    rotationDegrees: 0, mirror: false)
                // The fit is a uniform scale, so one number carries the frame's units to points.
                let unit = CGFloat(map.a) * frameSize.height
                func point(_ k: Keypoint) -> CGPoint {
                    CGPoint(x: CGFloat(map.mapX(k.x, k.y)), y: CGFloat(map.mapY(k.x, k.y)))
                }

                for (a, b) in KP.skeleton {
                    let pa = keypoints[a], pb = keypoints[b]
                    guard pa.score >= Self.minScore, pb.score >= Self.minScore else { continue }
                    var path = Path()
                    path.move(to: point(pa))
                    path.addLine(to: point(pb))
                    context.stroke(path, with: .color(.accent), lineWidth: unit * Self.boneWidth)
                }
                let r = unit * Self.jointRadius
                for k in keypoints where k.score >= Self.minScore {
                    let p = point(k)
                    context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                                 with: .color(.white))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

struct ContentView: View {

    @StateObject private var camera = CameraModel()
    @StateObject private var workout = WorkoutViewModel()
    @State private var showStopConfirm = false
    @State private var showSkipConfirm = false
    @State private var showPlacement = false
    @State private var showDebug = false
    /// Kept across launches: "Don't show this again" on the placement guide.
    @AppStorage("placementGuideSeen") private var placementSeen = false

    var body: some View {
        ZStack {
            CameraPreview(session: camera.session).ignoresSafeArea()
            SkeletonOverlay(keypoints: camera.keypoints, frameSize: camera.frameSize)
                .ignoresSafeArea()
            hud
        }
        .background(Color.appBackground)
        .onAppear {
            camera.onPoseFrame = { workout.onFrame($0) }
            workout.onResetCrop = { camera.resetRoi() }
            camera.start()
            // The athlete is across the room mid-set, not touching the phone, so the display
            // must not sleep. Scoped to this view rather than set globally, so it lifts again
            // when the app is backgrounded.
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            camera.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: showDebug) { _, on in workout.debugReadout = on }
        .sheet(item: $workout.finished) { ResultsView(attempt: $0) }
        .sheet(isPresented: $showPlacement) {
            PlacementGuideView(dontShowAgain: $placementSeen) {
                showPlacement = false
                workout.enterSetup()
            }
        }
        .confirmationDialog("End the workout?", isPresented: $showStopConfirm) {
            Button("End", role: .destructive) { workout.stopEarly() }
            Button("Keep going", role: .cancel) { workout.cancelStop() }
        } message: {
            Text("Your score so far will be saved.")
        }
        // Dismissing the question any other way is also "keep going", with the clock let go again.
        .onChange(of: showStopConfirm) { _, shown in if !shown { workout.cancelStop() } }
        .confirmationDialog("Skip the setup check?", isPresented: $showSkipConfirm) {
            Button("SKIP", role: .destructive) { workout.skipSetup() }
            Button("KEEP CHECKING", role: .cancel) {}
        } message: {
            Text("Cindy will start counting straight away, without calibrating to your bar. Reps may be missed or counted twice.")
        }
    }

    private var hud: some View {
        VStack {
            HStack(alignment: .top) {
                Text(workout.clockText)
                    .font(.system(size: 34, weight: .bold, design: .monospaced))
                    .chip()
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text("ROUND \(workout.rounds + 1)")
                        .font(.system(size: 15, weight: .bold))
                        .chip()
                    HStack(spacing: 6) {
                        chipButton("VOICE", on: workout.voiceEnabled) { workout.voiceEnabled.toggle() }
                        chipButton(camera.isRecording ? "● REC" : "REC", on: camera.isRecording) {
                            camera.toggleRecording()
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                Circle().fill(dotColour).frame(width: 9, height: 9).accessibilityHidden(true)
                Text(workout.status)
                    .font(.system(size: 13))
                    .foregroundStyle(workout.statusIsWarning ? Color.warn : Color.dim)
                    .accessibilityIdentifier("status")
            }
            .chip()
            // A long press on the status line is the way to the debug readout, as on Android.
            .onLongPressGesture { showDebug.toggle() }

            if showDebug { debugReadout }
            if let coaching = workout.coachShowing { CoachCard(exercise: coaching) }
            if let toast = workout.toast {
                Text(toast).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).chip()
                    .accessibilityIdentifier("toast")
            }

            Spacer()

            VStack(spacing: 2) {
                Text(workout.exerciseText)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Color.accent)
                    .accessibilityIdentifier("exerciseLabel")
                Text(repCountLabel)
                    .font(.system(size: 60, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("repCount")
                ProgressView(value: Double(workout.repProgress), total: 100)
                    .tint(.accent)
                    .frame(width: 160)
                    .accessibilityHidden(true)
            }
            .chip()

            HStack(spacing: 8) {
                // The left button is FLIP outside a workout and STOP inside one: flipping the
                // camera mid-Cindy is not a thing anyone does; ending early is.
                Button(workout.inWorkout ? "STOP" : "FLIP") {
                    if workout.inWorkout {
                        workout.requestStop()
                        showStopConfirm = true
                    } else {
                        camera.flip()
                        workout.recalibrate()
                    }
                }
                .buttonStyle(GhostButton(tint: workout.inWorkout ? .warn : .white))

                Button(workout.startButtonTitle) {
                    switch workout.phase {
                    case .idle:
                        if placementSeen { workout.enterSetup() } else { showPlacement = true }
                    case .setup:
                        showSkipConfirm = true
                    default:
                        workout.primaryAction()
                    }
                }
                .buttonStyle(PrimaryButton())

                Button("−1") { workout.undoRep() }.buttonStyle(GhostButton(tint: .white))
                Button("+1") { workout.manualRep() }
                    .buttonStyle(GhostButton(tint: .white))
                    .simultaneousGesture(LongPressGesture().onEnded { _ in workout.skipExercise() })
            }
            .padding(.bottom, 8)
        }
        .padding(16)
    }

    /// "3 / 5", "1 / 2" during the setup check, or just "—" where nothing counts against a target.
    private var repCountLabel: String {
        workout.targetText.isEmpty ? workout.repsText : "\(workout.repsText) / \(workout.targetText.dropFirst())"
    }

    private var dotColour: Color {
        switch workout.dot {
        case .ok: return .accent
        case .neutral: return .dim
        case .alert: return .warn
        }
    }

    /// Where the skeleton comes from and what it cost: source, inference time, whether the crop is
    /// following the body, the counter's signal, range and phase, and the latency probe's lines.
    private var debugReadout: some View {
        VStack(spacing: 2) {
            Text("\(camera.sourceName) · inf \(camera.lastInferenceMs) ms · crop \(camera.tracking ? "tracked" : "full frame")")
            Text(workout.counterReadout)
            if !camera.latencyLine.isEmpty { Text(camera.latencyLine) }
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(Color.dim)
        .multilineTextAlignment(.center)
        .chip()
        .accessibilityIdentifier("debugReadout")
    }

    private func chipButton(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(on ? Color.accent : Color.dim)
        }
        .chip()
    }
}

// MARK: - styling

extension Color {
    static let appBackground = Color(red: 0.043, green: 0.051, blue: 0.063)
    static let accent = Color(red: 0, green: 0.898, blue: 0.627)
    static let warn = Color(red: 1, green: 0.353, blue: 0.373)
    static let dim = Color.white.opacity(0.6)
}

private struct Chip: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.6), in: Capsule())
    }
}

extension View {
    func chip() -> some View { modifier(Chip()) }
}

struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(Color.appBackground)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Color.accent, in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct GhostButton: ButtonStyle {
    let tint: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 16)
            .frame(height: 54)
            .background(Color.black.opacity(0.6), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.25)))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
