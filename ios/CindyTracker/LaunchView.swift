import SwiftUI
import CindyCore

/// The launch moment, `LaunchView.kt` for the iPhone.
///
/// It costs nothing. The window behind it is already black, and the time it fills is time the app was
/// spending anyway: the camera is being opened while this draws. It goes when the camera has a frame,
/// so the app is genuinely ready when the arcs go, rather than waiting out a timer: never before
/// `floor` from its start, so a warm start does not read as a glitch, and at the latest `timeout`.
///
/// This is emphatically not a home screen. Nothing here is tappable and nothing is waited on; the app
/// still opens straight to the camera, which is the whole reason it has no landing page.
///
/// The mark is the workout: three arcs at 270°, 180° and 90° of a circle, which is fifteen squats, ten
/// push-ups and five pull-ups at their true proportion. They draw from the inside out, the order the
/// movements come in, and the innermost is brightest because it is the one you start on.
struct LaunchView: View {
    /// Whether the camera has a frame, or there is nothing to wait for.
    let ready: Bool
    /// Keeps it up whatever else is true, for the screenshots of a debug build.
    var hold = false
    let onDone: () -> Void

    private static let floor: TimeInterval = 0.9
    private static let timeout: TimeInterval = 2.5
    private static let fadeOut: TimeInterval = 0.34

    private static let radii: [CGFloat] = [46, 34, 22]
    private static let sweeps: [Double] = [270, 180, 90]
    private static let alphas: [Double] = [0.30, 0.58, 1]
    /// Each arc waits for the one inside it to be under way.
    private static let delays: [Double] = [360, 240, 120]

    @State private var startedAt = Date()
    @State private var leaving = false
    @State private var opacity = 1.0

    var body: some View {
        TimelineView(.animation) { timeline in
            scene(at: timeline.date.timeIntervalSince(startedAt) * 1000)
        }
        .background(Palette.background)
        .opacity(opacity)
        .ignoresSafeArea()
        // One node, so VoiceOver says what the screen is instead of walking the drawing.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cindy. AMRAP twenty minutes. Starting the camera.")
        .accessibilityIdentifier("launchView")
        .task(id: ready) {
            if ready && !hold { await leave() }
        }
        .task {
            guard !hold else { return }
            try? await Task.sleep(nanoseconds: UInt64(Self.timeout * 1_000_000_000))
            await leave()
        }
    }

    @MainActor private func leave() async {
        guard !leaving else { return }
        leaving = true
        let waited = Date().timeIntervalSince(startedAt)
        try? await Task.sleep(nanoseconds: UInt64(max(0, Self.floor - waited) * 1_000_000_000))
        withAnimation(.easeOut(duration: Self.fadeOut)) { opacity = 0 }
        try? await Task.sleep(nanoseconds: UInt64(Self.fadeOut * 1_000_000_000))
        onDone()
    }

    // MARK: the drawing

    private func white(_ alpha: Double) -> Color { Color.white.opacity(max(0, min(1, alpha))) }

    private func easeOut(_ x: Double) -> Double {
        let c = min(max(x, 0), 1)
        return 1 - (1 - c) * (1 - c) * (1 - c)
    }

    /// Symmetric ease, so the sweeping segment slows at both ends rather than only one.
    private func easeInOut(_ x: Double) -> Double {
        let c = min(max(x, 0), 1)
        return c * c * (3 - 2 * c)
    }

    /// The fade and the few points of rise that every element shares, from `at` milliseconds.
    private func rise(_ t: Double, _ at: Double) -> (alpha: Double, dy: CGFloat) {
        let p = easeOut((t - at) / 700)
        return (p, CGFloat(9 * (1 - p)))
    }

    private func scene(at t: Double) -> some View {
        GeometryReader { geo in
            let cx = geo.size.width / 2
            let markCy = geo.size.height * 0.40
            // The block sits a little above centre; dead centre reads as low once the foot line is in.
            let wordY = markCy + 56 + 34
            let ruleY = wordY + 30
            let word = rise(t, 620), rule = rise(t, 740), foot = rise(t, 980)

            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    let r = Self.radii[i]
                    let p = easeOut((t - Self.delays[i]) / 900)
                    Circle().stroke(white(0.06), lineWidth: 5)
                        .frame(width: r * 2, height: r * 2)
                        .position(x: cx, y: markCy)
                    Circle().trim(from: 0, to: CGFloat(Self.sweeps[i] / 360 * p))
                        .rotation(.degrees(-90))
                        .stroke(white(Self.alphas[i]), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .frame(width: r * 2, height: r * 2)
                        .position(x: cx, y: markCy)
                }

                Text("CINDY")
                    .font(Manrope.font(.extrabold, size: 40))
                    .tracking(0.1875 * 40)
                    .foregroundStyle(white(word.alpha))
                    .position(x: cx + 3.75, y: wordY - 14 + word.dy)

                HStack(spacing: 12) {
                    Rectangle().fill(white(rule.alpha * 0.20)).frame(width: 26, height: 0.5)
                    Text("AMRAP 20:00")
                        .font(Manrope.font(.bold, size: 11))
                        .tracking(0.218 * 11)
                        .foregroundStyle(white(rule.alpha * 0.42))
                    Rectangle().fill(white(rule.alpha * 0.20)).frame(width: 26, height: 0.5)
                }
                .position(x: cx, y: ruleY + rule.dy)

                sweepingTrack(t: t, alpha: foot.alpha)
                    .position(x: cx, y: geo.size.height - 76 - 1.5 + foot.dy)
                Text("5 pull-ups · 10 push-ups · 15 squats")
                    .font(Manrope.font(.semibold, size: 11.5))
                    .tracking(0.035 * 11.5)
                    .foregroundStyle(white(foot.alpha * 0.34))
                    .position(x: cx, y: geo.size.height - 40 + foot.dy)
            }
        }
    }

    /// The progress hairline: honest rather than decorative, since real work is happening behind it.
    private func sweepingTrack(t: Double, alpha: Double) -> some View {
        let trackW: CGFloat = 140, segW: CGFloat = 46
        let u = easeInOut(t.truncatingRemainder(dividingBy: 1400) / 1400)
        let left = -segW + CGFloat(u) * (trackW + segW)
        return ZStack(alignment: .leading) {
            Capsule().fill(white(alpha * 0.09))
            Capsule().fill(white(alpha * 0.75)).frame(width: segW).offset(x: left)
        }
        .frame(width: trackW, height: 3)
        .clipShape(Capsule())
    }
}
