import Foundation

/// What the athlete has said about their body, for the two estimates that need it: what they lifted
/// and what they burned. The `Profile` of the Android app holds these beside its other settings;
/// the rest of that is P13's, and keeps these keys.
///
/// Weight is asked for directly rather than guessed, and age as a year of birth rather than an age,
/// so the figure does not go stale on a birthday: the age is worked out from it when needed.
public final class BodyProfile {

    static let weightKey = "body_weight_kg"
    static let birthYearKey = "birth_year"
    static let sexKey = "sex"

    /// The most a weight may say; anything above is a typing slip.
    public static let maxKg = 400.0

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// The athlete's weight in kilograms, or 0 when it has never been said.
    public var bodyWeightKg: Double {
        get { Double(defaults.float(forKey: Self.weightKey)) }
        set { defaults.set(Float(min(max(newValue, 0), Self.maxKg)), forKey: Self.weightKey) }
    }

    public var hasBodyWeight: Bool { bodyWeightKg > 0 }

    /// The year the athlete was born, or 0 when it has never been said.
    public var birthYear: Int {
        get { defaults.integer(forKey: Self.birthYearKey) }
        set { defaults.set(newValue, forKey: Self.birthYearKey) }
    }

    /// Which of the heart-rate equation's two fits applies, or nil when it has never been said.
    public var sex: Sex? {
        get {
            switch defaults.string(forKey: Self.sexKey) {
            case "FEMALE": return .female
            case "MALE": return .male
            case "UNSTATED": return .unstated
            default: return nil
            }
        }
        set {
            switch newValue {
            case .female: defaults.set("FEMALE", forKey: Self.sexKey)
            case .male: defaults.set("MALE", forKey: Self.sexKey)
            case .unstated: defaults.set("UNSTATED", forKey: Self.sexKey)
            case nil: defaults.removeObject(forKey: Self.sexKey)
            }
        }
    }

    /// The athlete's age in `nowYear`, or nil when the year of birth has never been said.
    public func age(nowYear: Int) -> Int? { birthYear == 0 ? nil : nowYear - birthYear }

    /// The body `Calories` is handed: weight, age and sex read together, at one moment, so an
    /// estimate and the card that explains it can never be worked out from different people.
    public func body(nowYear: Int) -> Body { Body(bodyWeightKg, age: age(nowYear: nowYear), sex: sex) }
}
