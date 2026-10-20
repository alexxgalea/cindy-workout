import SwiftUI
import CindyCore

/// The start-position demonstrator: a figure that walks into position and holds there. `StartPoseView.kt`
/// for the iPhone, drawn from `StartPoseMotion`, which holds the loop, the turn, the projection and
/// the depth cues.
///
/// Shown when the athlete is in frame but the movement's own gate is shut. Depth is the only cue: each
/// bone's alpha and stroke width follow its rotated z, so a limb swinging behind the body dims and
/// thins on its own. The loop is time-based, so a dropped frame changes nothing about where it is, and
/// it starts from the top whenever it appears, so it is never seen mid-rewind.
struct StartPoseView: View {
    let exercise: Exercise
    @State private var startedAt = Date()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let elapsed = Float(timeline.date.timeIntervalSince(startedAt) * 1000)
                Self.draw(in: &context, size: size, loop: StartPoses.of(exercise), elapsed: elapsed)
            }
        }
        .id(exercise)
        .accessibilityHidden(true)
    }

    private static func white(_ alpha: Float) -> Color {
        Color.white.opacity(Double(max(0, min(1, alpha))))
    }

    private static func draw(in context: inout GraphicsContext, size: CGSize, loop: StartPoses.Loop,
                             elapsed: Float) {
        guard size.width > 0, size.height > 0 else { return }
        let width = Float(size.width), height = Float(size.height)
        let pose = StartPoseMotion.pose(of: loop, atMs: elapsed)
        let projected = StartPoseMotion.project(pose.joints, loop: loop,
                                                yawDegrees: StartPoseMotion.yaw(atMs: elapsed),
                                                width: width, height: height)
        let scale = min(width / loop.boxWidth, height / loop.boxHeight)
        let offsetX = (width - loop.boxWidth * scale) / 2
        let offsetY = (height - loop.boxHeight * scale) / 2
        let alpha = pose.alpha

        func point(_ j: Int) -> CGPoint { CGPoint(x: CGFloat(projected.x[j]), y: CGFloat(projected.y[j])) }
        func line(from a: CGPoint, to b: CGPoint) -> Path {
            var path = Path()
            path.move(to: a)
            path.addLine(to: b)
            return path
        }

        // The bar, where there is one to hang from.
        if let barY = loop.barY {
            let y = CGFloat(offsetY + barY * scale)
            context.stroke(line(from: CGPoint(x: CGFloat(offsetX + 14 * scale), y: y),
                                to: CGPoint(x: CGFloat(offsetX + (loop.boxWidth - 14) * scale), y: y)),
                           with: .color(white(0.34 * alpha)),
                           style: StrokeStyle(lineWidth: CGFloat(5 * scale), lineCap: .round))
        }

        // A soft contact shadow, so the figure stands on something.
        let footX = (projected.x[StartPoses.lAnkle] + projected.x[StartPoses.rAnkle]) / 2
        context.fill(Path(ellipseIn: CGRect(x: CGFloat(footX - 26 * scale),
                                            y: CGFloat(offsetY + (loop.groundY - 2) * scale),
                                            width: CGFloat(52 * scale), height: CGFloat(7 * scale))),
                     with: .color(white(0.07 * alpha)))

        // The torso as a quad, so the body has a mass rather than being four sticks.
        var torso = Path()
        torso.move(to: point(StartPoses.lShoulder))
        torso.addLine(to: point(StartPoses.rShoulder))
        torso.addLine(to: point(StartPoses.rHip))
        torso.addLine(to: point(StartPoses.lHip))
        torso.closeSubpath()
        context.fill(torso, with: .color(white(0.09 * alpha)))

        // Back to front, so a near limb crosses over a far one rather than under it.
        for i in StartPoseMotion.boneOrder(projected) {
            let bone = StartPoses.bones[i]
            let depth = (projected.z[bone[0]] + projected.z[bone[1]]) / 2
            context.stroke(line(from: point(bone[0]), to: point(bone[1])),
                           with: .color(white(StartPoseMotion.depthAlpha(depth) * alpha)),
                           style: StrokeStyle(lineWidth: CGFloat((2.4 + 0.9 * StartPoseMotion.depthUnit(depth)) * scale),
                                              lineCap: .round))
        }

        // Joints on the near side only: dotting all thirteen turns the figure into a constellation.
        let radius = CGFloat(2.6 * scale)
        for j in [StartPoses.rShoulder, StartPoses.rElbow, StartPoses.rWrist,
                  StartPoses.rHip, StartPoses.rKnee, StartPoses.rAnkle] {
            let c = point(j)
            context.fill(Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius,
                                                width: radius * 2, height: radius * 2)),
                         with: .color(white(0.95 * alpha)))
        }

        let head = point(StartPoses.nose)
        let headRadius = CGFloat(loop.headRadius * scale)
        context.stroke(Path(ellipseIn: CGRect(x: head.x - headRadius, y: head.y - headRadius,
                                              width: headRadius * 2, height: headRadius * 2)),
                       with: .color(white(0.98 * alpha)),
                       style: StrokeStyle(lineWidth: CGFloat(3 * scale)))
    }
}

/// The card the figure stands on: `coachCard` of `activity_main.xml`. 132 wide, the figure 126 high, a
/// hairline, and the cue under it with a red dot. It has no caption: a figure walking into a hang,
/// over the words "Hang from the bar", does not also need to be labelled "start position".
struct CoachPanel: View {
    let exercise: Exercise
    @ScaledMetric(relativeTo: .footnote) private var cueSize: CGFloat = 12.5

    var body: some View {
        VStack(spacing: 0) {
            StartPoseView(exercise: exercise).frame(height: 126)
            Rectangle().fill(Palette.hairline).frame(height: 1).padding(.top, 10)
                .accessibilityHidden(true)
            HStack(spacing: 7) {
                Circle().fill(Palette.stateAlert).frame(width: 6, height: 6).accessibilityHidden(true)
                Text(exercise.startCue)
                    .font(Manrope.font(.semibold, size: cueSize))
                    .tracking(-0.0125 * cueSize)
                    .foregroundStyle(Palette.label)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 10)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .frame(width: 132)
        .glassCard(radius: Palette.radiusPanel)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(exercise.startCue)
        .accessibilityIdentifier("coachCard")
    }
}
