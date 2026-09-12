/// How much of the athlete the camera is managing to read.
public enum TrackingHealth: String, Sendable {
    /// The movement's joints are as legible as they have been all session.
    case good
    /// Legibility is falling. Measured on darkened footage, the count is still right here.
    case weak
    /// Legibility has collapsed far enough that reps are being missed.
    case lost
}

/// Watches whether the camera can still read the athlete, and says so before the score goes wrong.
///
/// Port of `TrackingHealth.kt`. A tester reported that a workout stopped counting his pull-ups
/// around the tenth round, outdoors, at sunset. Reproducing that by darkening a clip whose ground
/// truth is five reps showed something worse than "stopped": the score *bleeds*, scoring 5, 3, 2,
/// 1, 0 as the light fell, with nothing saying the number had stopped being true.
///
/// The counting gates cannot fix that — they already refuse an unreadable frame, so darkness
/// produces an *absent* rep rather than a wrong one, and no gate recovers a rep the camera never
/// saw. The only honest response is to notice, say so, and stop presenting the total as certain.
///
/// The reading is the share of recent frames in which every joint the current movement scores from
/// was confidently seen, taken against the session's own baseline rather than a fixed percentage:
/// of two clips measured, one sat at 89% legible while counting perfectly and the other at 31%
/// while also counting perfectly, so no absolute threshold separates them, while as a fraction of
/// each clip's own best both lose reps at around half. Baselines are kept per movement because
/// pull-ups need both wrists overhead and fail roughly sixteen times sooner than push-ups.
public final class TrackingHealthMonitor {

    private enum Tune {
        /// How much recent history a reading is taken over.
        static let windowMs: Int64 = 4_000
        /// Samples the window needs before it describes anything.
        static let minSamples = 20
        /// Share of the session's own best legibility below which the camera is falling behind.
        static let fading: Float = 0.70
        /// And below which reps are being missed.
        static let losing: Float = 0.50
        /// Recovery has to beat the warning threshold, so a reading sitting on it cannot flap.
        static let recovered: Float = 0.80
        /// How long a reading must hold before the athlete is told anything.
        static let dwellMs: Int64 = 3_000
        /// Brightness gain past which the picture really was dark, rather than merely unreadable.
        static let darkGain: Float = 2
    }

    private var seen: [Int64] = []
    private var read: [Int64] = []
    private var baseline: [Exercise: Float] = [:]
    private var candidate = TrackingHealth.good
    private var candidateSince: Int64 = 0
    private var lastNow: Int64 = 0
    private var windowSince: Int64 = 0
    private var lastExercise: Exercise?

    public private(set) var health = TrackingHealth.good
    /// What to tell the athlete, or nil while nothing is wrong. Replaces the engine's own hint,
    /// which in this situation says "Step into frame" to someone hanging on the bar in front of it.
    public private(set) var advice: String?
    /// Time spent unable to read the athlete, which is what makes a score a lower bound.
    public private(set) var lostMs: Int64 = 0
    public private(set) var weakMs: Int64 = 0

    public init() {}

    @discardableResult
    public func update(
        exercise: Exercise,
        legible: Bool,
        softGain: Float,
        now: Int64
    ) -> TrackingHealth {
        accrue(now)
        lastNow = now

        // A window spanning a movement change describes neither of them.
        if exercise != lastExercise {
            lastExercise = exercise
            seen.removeAll(keepingCapacity: true)
            read.removeAll(keepingCapacity: true)
            windowSince = 0
            candidateSince = now
        }

        if windowSince == 0 { windowSince = now }
        seen.append(now)
        if legible { read.append(now) }
        let cutoff = now - Tune.windowMs
        while let first = seen.first, first < cutoff { seen.removeFirst() }
        while let first = read.first, first < cutoff { read.removeFirst() }

        if seen.count < Tune.minSamples || now - windowSince < Tune.windowMs { return health }

        let fraction = Float(read.count) / Float(seen.count)
        if let best = baseline[exercise] {
            if fraction > best { baseline[exercise] = fraction }
        } else {
            baseline[exercise] = fraction
        }

        let reference = baseline[exercise] ?? 0
        // A baseline of zero is the absence of one, not a lenient one: the camera has never read
        // this movement at all, which is a failure and not a clean slate.
        let ratio = reference <= 0 ? 0 : fraction / reference
        let reading: TrackingHealth
        if ratio < Tune.losing {
            reading = .lost
        } else if ratio < Tune.fading {
            reading = .weak
        } else if ratio >= Tune.recovered {
            reading = .good
        } else {
            reading = health
        }
        settle(reading, softGain: softGain, now: now)
        return health
    }

    private func settle(_ reading: TrackingHealth, softGain: Float, now: Int64) {
        if reading != candidate {
            candidate = reading
            candidateSince = now
            return
        }
        if reading == health { return }
        // Recovering is allowed to be instant.
        if reading != .good && now - candidateSince < Tune.dwellMs { return }
        health = reading
        switch reading {
        case .good: advice = nil
        case .weak: advice = "Losing you — more light helps"
        case .lost:
            advice = softGain >= Tune.darkGain
                ? "Too dark to count — tap +1"
                : "Can't see you — tap +1"
        }
    }

    private func accrue(_ now: Int64) {
        guard lastNow != 0, now > lastNow else { return }
        let elapsed = now - lastNow
        switch health {
        case .lost: lostMs += elapsed
        case .weak: weakMs += elapsed
        case .good: break
        }
    }

    /// Forgets the learned baselines without clearing what the session has already suffered.
    public func reframe() {
        baseline.removeAll(keepingCapacity: true)
        seen.removeAll(keepingCapacity: true)
        read.removeAll(keepingCapacity: true)
        windowSince = 0
        lastExercise = nil
        candidate = health
        candidateSince = 0
    }

    public func reset() {
        seen.removeAll(keepingCapacity: true)
        read.removeAll(keepingCapacity: true)
        baseline.removeAll(keepingCapacity: true)
        health = .good
        advice = nil
        candidate = .good
        candidateSince = 0
        lastNow = 0
        windowSince = 0
        lastExercise = nil
        lostMs = 0
        weakMs = 0
    }
}
