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

    // The film draws the same skeleton at the same weight, from the same numbers.
    private static let minScore = RecordingLayout.minScore
    private static let boneWidth = CGFloat(RecordingLayout.boneWidthFraction)
    private static let jointRadius = CGFloat(RecordingLayout.jointRadiusFraction)

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
                    context.stroke(path, with: .color(Palette.label), lineWidth: unit * Self.boneWidth)
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
    @StateObject private var film = FilmModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showStopConfirm = false
    @State private var showSkipConfirm = false
    @State private var showPlacement = false
    @State private var showDebug = false
    @State private var showMenu = false
    /// Set when the menu's cover took this view off the screen, so that its return is not a fresh arrival.
    @State private var coveredByMenu = false
    /// Kept across launches: "Don't show this again" on the placement guide. It is also evidence
    /// that the athlete has used the app before, which is why `Onboarding` owns the key.
    @AppStorage(Onboarding.keyPlacementSeen) private var placementSeen = false
    /// The first-launch pages, shown before the camera is asked for. Decided when the screen is
    /// made, so the pages are there from the first frame and the camera never gets the chance to
    /// ask first.
    @State private var showTutorial = false
    /// The pages are owed, and come when the launch view has gone, as Android sends for them once its
    /// arcs have played out: `showTutorial` is what is on screen, this is what is due.
    @State private var tutorialDue: Bool
    /// The launch view stands over everything until the camera has a frame, or the pages are due.
    @State private var launching = true
    /// Whether the camera's permission has been answered, either way. The tour of the controls
    /// waits behind it, so the athlete is not shown a dimmed screen with a system dialog on top.
    @State private var cameraAnswered = false
    @State private var tour = SpotlightTour()
    @State private var tourFrames: [HudTour.Target: CGRect] = [:]
    private let firstRun = FirstRun()
    /// A debug build can be told to keep the launch view up, for its screenshot.
    private var holdLaunch: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "CindyHoldLaunch")
        #else
        return false
        #endif
    }

    init() {
        let flags = FirstRun()
        _tutorialDue = State(initialValue: flags.shouldShowTutorial(hasHistory: !RecordStore().all().isEmpty,
                                                                    cameraGranted: CameraModel.permissionHeld))
    }

    /// Whether to be listening for a knocked phone. Not once the app is in the background, nor while
    /// the menu or the results are open over the camera: Android's `onPause` stops it for both (they
    /// are activities there), and picking the phone up to use either is not a knock. Only
    /// `.background`, not `.inactive`: Control Centre or a banner pulled over the screen is not the
    /// app leaving, and stopping would lose a knock still waiting to settle.
    private var wantsMotion: Bool { scenePhase != .background && !showMenu && workout.finished == nil }

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
            // A view that sets this itself keeps its own value whatever its parent says, so the
            // questions, whose sheet hides everything it is attached to, are named here as well.
            .accessibilityHidden(screenIsCovered)
            if tour.isShowing {
                SpotlightOverlay(tour: tour, frames: tourFrames, advance: advanceTour, skip: skipTour)
            }
            // Over everything, and gone as soon as the camera has a frame.
            if launching {
                LaunchView(ready: camera.frameSize.width > 0 || tutorialDue, hold: holdLaunch) {
                    launching = false
                    if tutorialDue {
                        tutorialDue = false
                        showTutorial = true
                    }
                }
            }
        }
        // The camera screen is a camera: no status bar over the picture and no home indicator under it.
        .persistentSystemOverlays(.hidden)
        .coordinateSpace(.named(TourSpace.name))
        .onPreferenceChange(TourFramesKey.self) { tourFrames = $0 }
        .onChange(of: tourFrames) { _, _ in maybeStartTour() }
        // A tour that was waiting for the clock to be idle starts when it is.
        .onChange(of: workout.phase) { _, _ in maybeStartTour() }
        .background(Color.appBackground)
        .onAppear {
            // Back from the menu's cover: nothing was torn down, so there is nothing to set up again.
            if coveredByMenu { coveredByMenu = false; return }
            camera.onPoseFrame = { workout.onFrame($0) }
            film.bind(camera: camera, workout: workout)
            workout.onResetCrop = { camera.resetRoi() }
            beginFirstRun()
            workout.syncHeartRate()
            workout.startWatchingPhone()
            // The athlete is across the room mid-set, not touching the phone, so the display
            // must not sleep. Scoped to this view rather than set globally, so it lifts again
            // when the app is backgrounded.
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            // The menu is a full-screen cover, which takes this view off the screen where a sheet did
            // not. It is not the camera screen going away: a film, the count, the heart rate and the
            // music carry on under it, as they did under the sheet.
            if showMenu { coveredByMenu = true; return }
            film.interrupt()
            workout.pauseMusic()
            camera.stop()
            workout.stopHeartRate()
            workout.stopWatchingPhone()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: wantsMotion) { _, wanted in
            if wanted { workout.startWatchingPhone() } else { workout.stopWatchingPhone() }
        }
        .onChange(of: showDebug) { _, on in workout.debugReadout = on }
        // Leaving the app ends a film, with what it caught kept, and drops a count: the camera stops
        // with it, and a film that outlived the picture would be a blank one.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                film.interrupt()
                workout.pauseMusic()
            } else {
                // Back in front: the track carries on if the clock is still running.
                workout.syncMusic()
            }
        }
        .fullScreenCover(item: $workout.finished) { request in
            ResultsView(request, onDiscarded: { workout.sessionDiscarded() })
        }
        .fullScreenCover(isPresented: $showMenu, onDismiss: { workout.applyProfile(); maybeStartTour() }) {
            MenuScreen(workout: workout, workoutLive: workout.inWorkout, onReturnToCamera: { showMenu = false })
        }
        // However the pages end, finished or skipped, the camera comes next, after the movements
        // chosen on the second page have reached the session that START will run.
        .fullScreenCover(isPresented: $showTutorial, onDismiss: { workout.applyProfile(); openCamera() }) {
            TutorialScreen(replay: false, profile: workout.settings, stravaAvailable: StravaBuild.available) { _ in showTutorial = false }
        }
        .sheet(isPresented: $showPlacement) {
            PlacementGuideView(dontShowAgain: $placementSeen) {
                showPlacement = false
                workout.enterSetup()
            }
        }
        // Dismissing the question any other way (the dim, a swipe down, the escape gesture) is also
        // "keep going", with the clock let go again.
        .cindySheet(isPresented: $showStopConfirm,
                    title: "End the workout?",
                    subtitle: "Your score so far will be saved.",
                    primary: SheetButton(title: "END") { workout.stopEarly() },
                    secondary: SheetButton(title: "KEEP GOING") {},
                    onDismiss: { workout.cancelStop() })
        .cindySheet(isPresented: $showSkipConfirm,
                    title: "Skip the setup check?",
                    subtitle: "Cindy will start counting straight away, without calibrating to your bar. Reps may be missed or counted twice.",
                    primary: SheetButton(title: "SKIP") { workout.skipSetup() },
                    secondary: SheetButton(title: "KEEP CHECKING") {})
    }

    /// Something stands over the camera screen and takes the touches: the tour, a question, or the
    /// launch view. A screen reader is kept off what is beneath.
    private var screenIsCovered: Bool {
        tour.hidesScreenBeneath || showStopConfirm || showSkipConfirm || launching
    }

    private var hud: some View {
        CameraHud(workout: workout, film: film,
                  onMenu: { showMenu = true },
                  onFlip: { camera.flip(); workout.recalibrate() },
                  onStop: { workout.requestStop(); showStopConfirm = true },
                  onStart: start,
                  onSkip: skip,
                  onToggleDebug: { showDebug.toggle() },
                  hiddenBeneath: screenIsCovered) {
            middle
        }
    }

    /// The room between the bands, which is for what stands on the picture: the countdown, the debug
    /// readout, a toast and the start-position coach.
    private var middle: some View {
        ZStack(alignment: .top) {
            if film.state == .counting, let digit = film.digit {
                CountdownOverlay(digit: digit, into: film.into, label: film.countLabel)
            }
            VStack(spacing: 8) {
                if showDebug { debugReadout }
                if let toast = workout.toast {
                    Text(toast).cindy(.headline)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Palette.bandTop, in: Capsule())
                        .accessibilityIdentifier("toast")
                }
            }
            .padding(.top, 8)
            if let coaching = workout.coachShowing {
                CoachPanel(exercise: coaching)
                    .padding(.leading, 16).padding(.top, 20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    /// START asks the placement guide first, until the athlete has turned it off; the rest of the
    /// shutter's jobs are the workout's. It is inert during the setup check, where SKIP is the way out.
    private func start() {
        switch workout.phase {
        case .idle: if placementSeen { workout.enterSetup() } else { showPlacement = true }
        default: workout.primaryAction()
        }
    }

    /// SKIP means the same thing everywhere, leave this movement, but leaving it during the check
    /// means starting Cindy with no calibration at all, which is worth a question first.
    private func skip() {
        if workout.phase == .setup { showSkipConfirm = true } else { workout.skipExercise() }
    }

    // MARK: first run

    /// Someone who has already used the app is never shown the pages, and is marked as having seen
    /// them so that clearing their records later does not make them look new. A new install waits
    /// behind the pages: the camera opens when they end (`openCamera`, from the cover's dismissal).
    private func beginFirstRun() {
        guard !showTutorial, !tutorialDue else { return }
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
        guard !tour.isShowing, cameraAnswered, !showMenu, !showTutorial, !tutorialDue, !showPlacement,
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

    /// Where the skeleton comes from and what it cost: source, inference time, whether the crop is
    /// following the body, the counter's signal, range and phase, and the latency probe's lines.
    private var debugReadout: some View {
        VStack(spacing: 2) {
            Text("\(camera.sourceName) · inf \(camera.lastInferenceMs) ms · crop \(camera.tracking ? "tracked" : "full frame")")
            Text(workout.counterReadout)
            Text(workout.lookLine.isEmpty ? "look: not listening" : workout.lookLine)
            if !camera.latencyLine.isEmpty { Text(camera.latencyLine) }
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(Color.dim)
        .multilineTextAlignment(.center)
        .chip()
        .accessibilityIdentifier("debugReadout")
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
