import Foundation

/// How much the athlete's own body weight moved in a session, from the reps that were banked.
///
/// A rep is not worth the whole of the athlete's weight: a pull-up leaves the hands and forearms on
/// the bar, and a push-up leaves the feet on the floor. So each movement is a *share* of body mass,
/// and a movement whose share cannot be stated is left out by name rather than guessed at. The
/// answer is an estimate and is only ever shown as one.
///
/// Reps come from `StravaSets.from`, the same bank the Strava upload reads, so a skipped movement
/// contributes what it actually banked and an attempt whose record cannot be trusted contributes
/// nothing. A tally rebuilt from `rounds * 30` would credit work nobody did. Port of `Lifted.kt`.
public struct Lifted: Equatable, Sendable {
    /// What was counted, one entry per movement that banked reps, in the order of a round.
    public let parts: [Part]
    /// What was done but deliberately not counted, so the card can say so.
    public let omitted: [Omitted]
    /// Kilograms moved across `parts`.
    public let totalKg: Double
    /// True when the score is a lower bound: the camera was blind for part of the session.
    public let atLeast: Bool

    public init(parts: [Part], omitted: [Omitted], totalKg: Double, atLeast: Bool) {
        self.parts = parts
        self.omitted = omitted
        self.totalKg = totalKg
        self.atLeast = atLeast
    }

    /// One movement's contribution, at the variant the session was actually done with.
    public struct Part: Equatable, Sendable {
        public let movement: Exercise
        /// The plain name for an unchanged movement, the variant's own plural ("knee push-ups") for a changed one.
        public let label: String
        public let reps: Int
        /// The share of body mass one rep lifts.
        public let share: Double
        public let kg: Double

        public init(movement: Exercise, label: String, reps: Int, share: Double, kg: Double) {
            self.movement = movement
            self.label = label
            self.reps = reps
            self.share = share
            self.kg = kg
        }
    }

    /// A movement that banked reps but has no share the app can stand behind.
    public struct Omitted: Equatable, Sendable {
        public let movement: Exercise
        public let label: String
        public let reps: Int
        public let reason: String

        public init(movement: Exercise, label: String, reps: Int, reason: String) {
            self.movement = movement
            self.label = label
            self.reps = reps
            self.reason = reason
        }
    }

    /// "About" or, for a lower-bound score, "At least": the word that goes before `kgNumber`.
    public var kgPrefix: String { atLeast ? "At least" : "About" }

    /// The kilograms as a grouped number: "12,940".
    ///
    /// Rounded to the nearest 10 kg from 100 kg up: a figure built from a body-segment share is no
    /// more exact than that, and a spurious last digit would claim it was.
    public var kgNumber: String {
        let rounded = totalKg >= 100.0 ? JavaText.roundToLong(totalKg / 10.0) * 10 : JavaText.roundToLong(totalKg)
        return JavaText.grouped(Int(rounded))
    }

    /// "About 12,940 kg", or "At least 12,940 kg" for a lower-bound score.
    public func kgText() -> String { "\(kgPrefix) \(kgNumber) kg" }

    /// The small print: which shares were applied, which movements were left out and why, and what
    /// kind of reps went in.
    ///
    /// Names only the movements that banked reps, so an adaptive session is never told about a
    /// variant it did not do. `tappedIn` says some of the reps were tapped rather than seen, which is
    /// real work but a different claim from camera-seen reps, so it is said rather than folded in.
    public func footnote(tappedIn: Bool) -> String {
        var out = "An estimate from your weight, counting a share of it per rep: "
        out += parts.map { "\($0.label) \(JavaText.roundToInt($0.share * 100))%" }.joined(separator: ", ")
        out += ". "
        for o in omitted {
            out += "\(Self.capitalisingFirst(o.label)) are left out: \(o.reason). "
        }
        if tappedIn { out += "Reps you tapped in count the same as the ones the camera saw. " }
        if atLeast { out += "The camera lost you for part of this session, so this is a floor. " }
        return Self.trimmed(out)
    }

    /// `replaceFirstChar { it.uppercase() }`: the first UTF-16 character in capitals, the rest as it was.
    private static func capitalisingFirst(_ s: String) -> String {
        guard let first = s.unicodeScalars.first else { return s }
        var out = String.UnicodeScalarView()
        out.append(contentsOf: String(Character(first)).uppercased().unicodeScalars)
        out.append(contentsOf: s.unicodeScalars.dropFirst())
        return String(out)
    }

    /// Kotlin's `trim()` on text that only ever ends in a space.
    private static func trimmed(_ s: String) -> String {
        var scalars = Array(s.unicodeScalars)
        while let last = scalars.last, last == " " { scalars.removeLast() }
        var out = String.UnicodeScalarView()
        out.append(contentsOf: scalars)
        return String(out)
    }

    /// The share of body mass one rep lifts, or why there is none.
    private enum Rule {
        case share(Double)
        case leftOut(String)
    }

    /// Everything but the hands and forearms, which stay on the bar: Winter's body-segment table
    /// puts them at about 5% of body mass.
    private static let pullUpShare = 0.95

    /// The share of body weight the hands carry in a push-up, from Ebben et al. (2011), "Kinetic
    /// analysis of several variations of push-ups", J Strength Cond Res 25(10): 64% from the toes,
    /// 49% from the knees.
    private static let standardPushUpShare = 0.64
    private static let kneePushUpShare = 0.49

    /// The body above the knees, which is what a squat raises; the shanks and feet stay where they
    /// are. The same segment table as the pull-up.
    private static let squatShare = 0.88

    // These three are exhaustive on purpose, with no `default`: a variant added later has to be
    // placed here before the app compiles, rather than being counted at some default share nobody chose.
    private static func rule(_ variant: PullVariant) -> Rule {
        switch variant {
        case .strictPullUp: return .share(pullUpShare)
        case .bandAssistedPullUp: return .leftOut("the band's share isn't known")
        case .invertedRow: return .leftOut("how much it lifts depends on the angle")
        case .footAssistedPullUp: return .leftOut("the share your feet take isn't known")
        case .negativePullUp: return .leftOut("a negative is a lowering, not a lift")
        }
    }

    private static func rule(_ variant: PushVariant) -> Rule {
        switch variant {
        case .standardPushUp: return .share(standardPushUpShare)
        case .kneePushUp: return .share(kneePushUpShare)
        case .inclinePushUp: return .leftOut("it depends on the height of the bench, which isn't known")
        }
    }

    private static func rule(_ variant: SquatVariant) -> Rule {
        switch variant {
        case .airSquat, .heelsFlat, .boxSquat: return .share(squatShare)
        case .supportedSquat: return .leftOut("the share the support takes isn't known")
        }
    }

    /// The rule and the label for `movement` as `profile` performed it.
    ///
    /// An unchanged movement keeps its plain name ("pull-ups"), as the rest of the app does; only a
    /// movement the athlete changed is named by its variant ("knee push-ups"), so a standard session
    /// never reads "strict pull-ups" for what it simply called pull-ups.
    private static func ruleFor(_ profile: CindyProfile, _ movement: Exercise) -> (Rule, String) {
        let standard = CindyProfile.standard
        switch movement {
        case .pullup: return (rule(profile.pull), profile.pull == standard.pull ? "pull-ups" : profile.pull.plural)
        case .pushup: return (rule(profile.push), profile.push == standard.push ? "push-ups" : profile.push.plural)
        case .squat: return (rule(profile.squat), profile.squat == standard.squat ? "squats" : profile.squat.plural)
        }
    }

    /// What `a` lifted at `bodyWeightKg`, or nil when that cannot be said honestly: no weight, a
    /// record whose sets cannot be trusted (including every attempt from before reps were counted),
    /// movements this build does not recognise, or nothing counted at all.
    ///
    /// Tapped-in reps are counted: they were real work, and the card says they are a different claim
    /// from reps the camera saw.
    public static func of(_ a: Attempt, bodyWeightKg: Double) -> Lifted? {
        if !(bodyWeightKg > 0.0) { return nil }
        guard let tally = tally(a) else { return nil }
        if tally.counted.isEmpty { return nil }
        let parts = tally.counted.map { c in
            Part(movement: c.movement, label: c.label, reps: c.reps, share: c.share,
                 kg: Double(c.reps) * c.share * bodyWeightKg)
        }
        return Lifted(parts: parts, omitted: tally.omitted, totalKg: parts.reduce(0.0) { $0 + $1.kg },
                      atLeast: a.scoreIsLowerBound)
    }

    /// Whether `a` has something to lift, whatever the athlete weighs: what decides if the page
    /// should invite them to enter a weight rather than show nothing.
    public static func measurable(_ a: Attempt) -> Bool {
        !(tally(a)?.counted.isEmpty ?? true)
    }

    private struct Counted {
        let movement: Exercise
        let label: String
        let reps: Int
        let share: Double
    }

    private struct Tally {
        let counted: [Counted]
        let omitted: [Omitted]
    }

    private static func tally(_ a: Attempt) -> Tally? {
        // A nil profile is a session from a build that knew a movement this one does not;
        // relabelling it as the standard three would be the lie CindyProfile exists to stop.
        guard let profile = a.profile else { return nil }
        guard let sets = StravaSets.from(a) else { return nil }
        var counted: [Counted] = []
        var omitted: [Omitted] = []
        for movement in Exercise.allCases {
            let reps = sets.filter { $0.exercise == movement }.reduce(0) { $0 + $1.reps }
            if reps == 0 { continue }
            let (rule, label) = ruleFor(profile, movement)
            switch rule {
            case .share(let of): counted.append(Counted(movement: movement, label: label, reps: reps, share: of))
            case .leftOut(let reason): omitted.append(Omitted(movement: movement, label: label, reps: reps, reason: reason))
            }
        }
        return Tally(counted: counted, omitted: omitted)
    }
}
