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
struct SkeletonOverlay: View {
    let keypoints: [Keypoint]
    let frameSize: CGSize

    private static let minScore: Float = 0.3

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                guard frameSize.width > 0, frameSize.height > 0, keypoints.count == KP.count else { return }
                // resizeAspectFill: scale until both axes are covered, then centre the overflow.
                let scale = max(size.width / frameSize.width, size.height / frameSize.height)
                let dx = (size.width - frameSize.width * scale) / 2
                let dy = (size.height - frameSize.height * scale) / 2
                func point(_ k: Keypoint) -> CGPoint {
                    CGPoint(x: CGFloat(k.x) * scale + dx, y: CGFloat(k.y) * scale + dy)
                }

                for (a, b) in KP.skeleton {
                    let pa = keypoints[a], pb = keypoints[b]
                    guard pa.score >= Self.minScore, pb.score >= Self.minScore else { continue }
                    var path = Path()
                    path.move(to: point(pa))
                    path.addLine(to: point(pb))
                    context.stroke(path, with: .color(.accent), lineWidth: 4)
                }
                for k in keypoints where k.score >= Self.minScore {
                    let p = point(k)
                    context.fill(
                        Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)),
                        with: .color(.white)
                    )
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

    var body: some View {
        ZStack {
            CameraPreview(session: camera.session).ignoresSafeArea()
            SkeletonOverlay(keypoints: camera.keypoints, frameSize: camera.frameSize)
                .ignoresSafeArea()
            hud
        }
        .background(Color.appBackground)
        .onAppear {
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
        .onReceive(camera.$keypoints) { workout.onFrame($0) }
        .sheet(item: $workout.finished) { ResultsView(attempt: $0) }
        .confirmationDialog("End the workout?", isPresented: $showStopConfirm) {
            Button("End", role: .destructive) { workout.stopEarly() }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("Your score so far will be saved.")
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

            Text(workout.status)
                .font(.system(size: 13))
                .foregroundStyle(workout.statusIsWarning ? Color.warn : Color.dim)
                .chip()

            Spacer()

            VStack(spacing: 2) {
                Text(workout.exercise.label)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Color.accent)
                Text("\(workout.reps) / \(workout.exercise.target)")
                    .font(.system(size: 60, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("repCount")
            }
            .chip()

            HStack(spacing: 8) {
                // The left button is FLIP outside a workout and STOP inside one: flipping the
                // camera mid-Cindy is not a thing anyone does; ending early is.
                Button(workout.inWorkout ? "STOP" : "FLIP") {
                    if workout.inWorkout {
                        showStopConfirm = true
                    } else {
                        camera.flip()
                        workout.recalibrate()
                    }
                }
                .buttonStyle(GhostButton(tint: workout.inWorkout ? .warn : .white))

                Button(workout.startButtonTitle) { workout.primaryAction() }
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
