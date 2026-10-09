import SwiftUI
import UIKit
import CindyCore

/// REC on the camera screen: the countdown, the film, and where the film goes. `FilmFlow` decides
/// what a tap does and what is said; this carries it out, with the camera, Photos, the voice and the
/// toast.
@MainActor
final class FilmModel: ObservableObject {

    @Published private(set) var state: FilmState = .idle
    /// The digit being counted down, or nil when no count is running.
    @Published private(set) var digit: Int?
    /// How far through that digit's second it is, 0 to 1.
    @Published private(set) var into: Float = 0

    /// What a screen reader says of the count.
    var countLabel: String { countdown.accessibilityLabel }

    private let countdown = Countdown()
    private weak var camera: CameraModel?
    private weak var workout: WorkoutViewModel?
    /// The display's rhythm, while there is a count to draw or a film to feed.
    private var driver: Timer?

    private var now: Int64 { Int64(ProcessInfo.processInfo.systemUptime * 1000) }

    func bind(camera: CameraModel, workout: WorkoutViewModel) {
        self.camera = camera
        self.workout = workout
        camera.onRecordingFinished = { [weak self] url in
            MainActor.assumeIsolated { self?.finished(url) }
        }
    }

    // MARK: - a tap

    func tap() {
        guard let camera else { return }
        switch FilmFlow.tap(state: state, canFilm: camera.canRecord, access: FilmLibrary.access()) {
        case .askAccess:
            FilmLibrary.requestAccess { [weak self] access in
                // Decided now: asking again cannot ask a second time, so this does not loop.
                if access == .undecided { self?.workout?.show(FilmFlow.refusedText) } else { self?.tap() }
            }
        case .say(let toast):
            workout?.show(toast)
        case .countdown(let seconds, let voice):
            state = .counting
            countdown.start(fromSeconds: seconds, now: now) { [weak self] in self?.begin() }
            digit = countdown.digit(now: now)
            into = countdown.into(now: now) ?? 0
            workout?.announceRecording(voice)
            UIAccessibility.post(notification: .announcement, argument: countdown.announcement)
            drive()
        case .cancelCountdown(let toast):
            callOff()
            workout?.show(toast)
        case .stopFilming:
            stopFilming()
        }
    }

    /// The athlete left the screen: a count is dropped without a word, and a film is stopped so that
    /// what it caught is kept.
    func interrupt() {
        switch FilmFlow.interrupted(state) {
        case .cancelCountdown: callOff()
        case .stopFilming: stopFilming()
        default: break
        }
    }

    // MARK: - the far side of the count

    private func begin() {
        guard let camera else { return }
        let ok = camera.startRecording()
        let start = FilmFlow.started(ok)
        state = ok ? .filming : .idle
        digit = nil
        if ok { camera.updateOverlay(workout?.recordedHud(now: now) ?? Self.blank) }
        if let toast = start.toast { workout?.show(toast) }
        workout?.announceRecording(start.voice)
        workout?.buzz(FilmFlow.startBuzzMs)
        drive()
    }

    private func callOff() {
        countdown.cancel()
        state = .idle
        digit = nil
        drive()
    }

    private func stopFilming() {
        // The chip is unlit at once, as on Android; the camera says when the file is whole.
        state = .idle
        camera?.stopRecording()
        drive()
    }

    /// The camera has closed the file, or failed to.
    private func finished(_ url: URL?) {
        if state == .filming { state = .idle }
        guard let url else { end(saved: false); return }
        FilmLibrary.save(url) { [weak self] saved in self?.end(saved: saved) }
    }

    private func end(saved: Bool) {
        let end = FilmFlow.ended(saved: saved)
        workout?.show(end.toast)
        if let voice = end.voice { workout?.announceRecording(voice) }
        drive()
    }

    // MARK: - the display's rhythm

    private static let blank = RecordedHudText(clock: "20:00", round: "ROUND 1", label: "", count: "0 / 5")

    /// Runs while there is a count to draw or a film to feed, and not otherwise.
    private func drive() {
        guard state != .idle else {
            driver?.invalidate()
            driver = nil
            return
        }
        guard driver == nil else { return }
        driver = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.frame() }
        }
    }

    private func frame() {
        let t = now
        if state == .counting {
            countdown.tick(now: t)
            digit = countdown.digit(now: t)
            into = countdown.into(now: t) ?? 0
        }
        if state == .filming, let hud = workout?.recordedHud(now: t) { camera?.updateOverlay(hud) }
        if state == .idle { drive() }
    }
}

/// The three seconds between tapping REC and the camera rolling: a ring that drains, the digit, and
/// the word RECORDING.
///
/// It draws over the picture and does not dim it. The bright middle is the framing zone, and an
/// athlete who cannot see themselves while they get placed is worse off than one reading a
/// slightly lower-contrast digit; the legibility comes from a vignette behind the ring, which
/// darkens the middle of the picture and leaves its edges, where the body is being judged, alone.
struct CountdownOverlay: View {
    let digit: Int
    /// 0 on the digit's first moment, 1 on its last.
    let into: Float
    let label: String

    private let ring: CGFloat = 58

    var body: some View {
        ZStack {
            RadialGradient(stops: [.init(color: Color(argb: 0xC4000000), location: 0),
                                   .init(color: Color(argb: 0x8A000000), location: 0.45),
                                   .init(color: .clear, location: 1)],
                           center: .center, startRadius: 0, endRadius: ring * 2.6)
            Circle().stroke(Palette.hairlineStrong, lineWidth: 3.5).frame(width: ring * 2, height: ring * 2)
            // Drains clockwise from twelve o'clock, so what is left of the ring is what is left of
            // the second.
            Circle()
                .trim(from: 0, to: CGFloat(1 - into))
                .stroke(Palette.stateAlert, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: ring * 2, height: ring * 2)
            // Each digit arrives a little oversized and settles, which reads as a beat rather than a
            // number being replaced.
            Text("\(digit)")
                .font(.system(size: 64, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(Palette.label)
                .opacity(Double(min(1, 0.35 + into * 6)))
                .scaleEffect(1 + 0.16 * CGFloat(1 - min(1, into * 5)))
            HStack(spacing: 7) {
                Circle().fill(Palette.stateAlert).frame(width: 7, height: 7)
                Text("RECORDING").font(.system(size: 11, weight: .heavy)).tracking(1.5)
                    .foregroundStyle(Palette.stateAlert)
            }
            .offset(y: ring + 30)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}
