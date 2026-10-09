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
    @State private var showMenu = false
    /// Kept across launches: "Don't show this again" on the placement guide. It is also evidence
    /// that the athlete has used the app before, which is why `Onboarding` owns the key.
    @AppStorage(Onboarding.keyPlacementSeen) private var placementSeen = false
    /// The first-launch pages, shown before the camera is asked for. Decided when the screen is
    /// made, so the pages are there from the first frame and the camera never gets the chance to
    /// ask first.
    @State private var showTutorial: Bool
    /// Whether the camera's permission has been answered, either way. The tour of the controls
    /// waits behind it, so the athlete is not shown a dimmed screen with a system dialog on top.
    @State private var cameraAnswered = false
    @State private var tour = SpotlightTour()
    @State private var tourFrames: [HudTour.Target: CGRect] = [:]
    private let firstRun = FirstRun()

    init() {
        let flags = FirstRun()
        _showTutorial = State(initialValue: flags.shouldShowTutorial(hasHistory: !RecordStore().all().isEmpty,
                                                                    cameraGranted: CameraModel.permissionHeld))
    }

    var body: some View {
        ZStack {
            Group {
                CameraPreview(session: camera.session).ignoresSafeArea()
                SkeletonOverlay(keypoints: camera.keypoints, frameSize: camera.frameSize)
                    .ignoresSafeArea()
                hud
            }
            // While the tour is showing the screen under it is for nobody: the dim keeps it from
            // sight and from touch, and this keeps it from a screen reader.
            .accessibilityHidden(tour.hidesScreenBeneath)
            if tour.isShowing {
                SpotlightOverlay(tour: tour, frames: tourFrames, advance: advanceTour, skip: skipTour)
            }
        }
        .coordinateSpace(.named(TourSpace.name))
        .onPreferenceChange(TourFramesKey.self) { tourFrames = $0 }
        .onChange(of: tourFrames) { _, _ in maybeStartTour() }
        // A tour that was waiting for the clock to be idle starts when it is.
        .onChange(of: workout.phase) { _, _ in maybeStartTour() }
        .background(Color.appBackground)
        .onAppear {
            camera.onPoseFrame = { workout.onFrame($0) }
            workout.onResetCrop = { camera.resetRoi() }
            beginFirstRun()
            workout.syncHeartRate()
            // The athlete is across the room mid-set, not touching the phone, so the display
            // must not sleep. Scoped to this view rather than set globally, so it lifts again
            // when the app is backgrounded.
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            camera.stop()
            workout.stopHeartRate()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: showDebug) { _, on in workout.debugReadout = on }
        .sheet(item: $workout.finished) { ResultsView($0) }
        .sheet(isPresented: $showMenu, onDismiss: { workout.applyProfile(); maybeStartTour() }) {
            MenuScreen(workout: workout, workoutLive: workout.inWorkout, onReturnToCamera: { showMenu = false })
        }
        // However the pages end, finished or skipped, the camera comes next, after the movements
        // chosen on the second page have reached the session that START will run.
        .fullScreenCover(isPresented: $showTutorial, onDismiss: { workout.applyProfile(); openCamera() }) {
            TutorialScreen(replay: false, profile: workout.settings) { _ in showTutorial = false }
        }
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
                        // What changes state mid-set stays here; navigation and configuration are
                        // things you settle before the clock starts, and they live in the menu.
                        chipButton("MENU", on: false) { showMenu = true }
                            .tourTarget(.menu)
                        chipButton(camera.isRecording ? "● REC" : "REC", on: camera.isRecording) {
                            camera.toggleRecording()
                        }
                        .tourTarget(.record)
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
            .tourTarget(.status)
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
            .tourTarget(.reps)

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
                .tourTarget(.flip)

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
                .tourTarget(.start)

                Button("−1") { workout.undoRep() }.buttonStyle(GhostButton(tint: .white))
                Button("+1") { workout.manualRep() }
                    .buttonStyle(GhostButton(tint: .white))
                    .simultaneousGesture(LongPressGesture().onEnded { _ in workout.skipExercise() })
            }
            .padding(.bottom, 8)
        }
        .padding(16)
    }

    // MARK: first run

    /// Someone who has already used the app is never shown the pages, and is marked as having seen
    /// them so that clearing their records later does not make them look new. A new install waits
    /// behind the pages: the camera opens when they end (`openCamera`, from the cover's dismissal).
    private func beginFirstRun() {
        guard !showTutorial else { return }
        if !firstRun.tutorialSeen { firstRun.tutorialSeen = true }
        openCamera()
    }

    /// Opens the camera, asking for its permission first if the athlete has not yet given it.
    private func openCamera() {
        camera.ensureAccess { _ in
            camera.start()
            cameraAnswered = true
            maybeStartTour()
        }
    }

    /// Starts the tour of the controls if one is waiting and nothing is in its way.
    ///
    /// Called from every place it could become possible: the camera's answer, the screen being laid
    /// out, and the menu closing, which is how a replay from Help arrives. It is guarded rather than
    /// scheduled, so that however many of them fire, it starts once, and never mid-workout: it stays
    /// pending until the clock is idle. It waits for a layout before lighting anything, because the
    /// hole is cut from where the controls actually are.
    private func maybeStartTour() {
        guard !tour.isShowing, cameraAnswered, !showMenu, !showTutorial, !showPlacement,
              workout.phase == .idle, workout.finished == nil,
              firstRun.hudTourPending, !tourFrames.isEmpty else { return }
        // Nothing lit yet is not the same as nothing to light: it stays pending, and the next layout
        // or the next time the screen is free asks again.
        _ = tour.start(HudTour.steps, frame: { tourFrames[$0].map(spotlightRect) })
    }

    private func spotlightRect(_ rect: CGRect) -> SpotlightRect {
        SpotlightRect(x: Float(rect.minX), y: Float(rect.minY), width: Float(rect.width), height: Float(rect.height))
    }

    private func advanceTour() { if tour.advance() { endTour() } }

    private func skipTour() { if tour.skip() { endTour() } }

    /// Done or skipped: it is taken, and does not come back until Help asks for it.
    private func endTour() { firstRun.hudTourPending = false }

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
