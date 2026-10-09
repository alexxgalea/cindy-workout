import Foundation

/// What the athlete has told the app about themselves and about how they intend to train.
///
/// Every setting here is edited from the menu and stored here rather than at its point of use, so
/// that a preference key has exactly one owner: a second reader of any of them would otherwise be a
/// second copy of its key string. The keys are Android's, so a setting means the same thing on both.
/// Port of `Profile.kt`.
public final class Profile {

    private static let weightKey = "body_weight_kg"
    private static let movementsKey = "movement_profile"
    private static let smartSquatsKey = "smart_squats"
    private static let musicKey = "music_uri"
    private static let musicOnKey = "music_on"
    private static let voiceOnKey = "voice_on"
    private static let voiceVolumeKey = "voice_volume"
    private static let voiceLanguageKey = "voice_language"
    private static let musicVolumeKey = "music_volume"
    private static let reminderOnKey = "reminder_on"
    private static let reminderMinuteKey = "reminder_minute"
    private static let birthYearKey = "birth_year"
    private static let sexKey = "sex"
    private static let hrAddressKey = "hr_device_address"
    private static let hrNameKey = "hr_device_name"
    private static let displayNameKey = "display_name"

    /// The voice starts at full and the music below it: the count is information and the track is
    /// atmosphere, so the default mix is the one where a rep is never missed because of a setting
    /// the athlete has not found yet.
    public static let defaultVoiceVolume: Float = 1
    public static let defaultMusicVolume: Float = 0.7
    /// Above the heaviest recorded human, so typos are caught but nobody real is refused.
    public static let maxKg = 400.0
    public static let minKg = 20.0
    /// Bounds for the age the heart-rate formula is given, wide enough to be a typo check only.
    public static let minAge = 13
    public static let maxAge = 100

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private func float(_ key: String, _ fallback: Float) -> Float {
        (defaults.object(forKey: key) as? NSNumber)?.floatValue ?? fallback
    }

    private func bool(_ key: String, _ fallback: Bool) -> Bool {
        (defaults.object(forKey: key) as? NSNumber)?.boolValue ?? fallback
    }

    private func int(_ key: String, _ fallback: Int) -> Int {
        (defaults.object(forKey: key) as? NSNumber)?.intValue ?? fallback
    }

    private func set(_ value: String?, forKey key: String) {
        if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
    }

    /// Kilograms, or 0 when the athlete has not said.
    ///
    /// Kept deliberately empty until they enter it. A default would let `Calories` produce a
    /// confident-looking number that is wrong by however far the default missed, and a wrong
    /// calorie figure is worse than no calorie figure.
    public var bodyWeightKg: Double {
        get { Double(float(Self.weightKey, 0)) }
        set { defaults.set(Float(min(max(newValue, 0), Self.maxKg)), forKey: Self.weightKey) }
    }

    public var hasBodyWeight: Bool { bodyWeightKg > 0 }

    /// The movements this Cindy is made of: standard, or whichever adaptations were chosen. An
    /// unrecognised value decodes back to the standard three, because a preference makes no claim
    /// about a workout that has not happened yet.
    public var movements: CindyProfile {
        get { Variations.decode(defaults.string(forKey: Self.movementsKey)) }
        set { defaults.set(Variations.encode(newValue), forKey: Self.movementsKey) }
    }

    /// Whether an air-squat session may switch itself to Adaptive Cindy when the squats turn out to
    /// be heels flat. Off until real sessions have shown it was the right call: a counter that
    /// changes its own mind about a movement has to be asked for before it is trusted.
    public var smartSquats: Bool {
        get { bool(Self.smartSquatsKey, false) }
        set { defaults.set(newValue, forKey: Self.smartSquatsKey) }
    }

    /// The chosen track, or nil for none. Clearing it is how a track is removed.
    public var musicTrack: String? {
        get { defaults.string(forKey: Self.musicKey) }
        set { set(newValue, forKey: Self.musicKey) }
    }

    public var hasMusic: Bool { musicTrack != nil }

    /// Whether the chosen track plays during the workout. Separate from `musicTrack` so that
    /// turning the music off for one session does not throw away the choice of track.
    public var musicOn: Bool {
        get { bool(Self.musicOnKey, true) }
        set { defaults.set(newValue, forKey: Self.musicOnKey) }
    }

    /// Whether the voice counts reps out loud.
    public var voiceOn: Bool {
        get { bool(Self.voiceOnKey, true) }
        set { defaults.set(newValue, forKey: Self.voiceOnKey) }
    }

    /// How loud the voice is, 0 to 1. Separate from the phone's own volume, and not a replacement
    /// for it: the two mix against each other on purpose.
    public var voiceVolume: Float {
        get { min(max(float(Self.voiceVolumeKey, Self.defaultVoiceVolume), 0), 1) }
        set { defaults.set(min(max(newValue, 0), 1), forKey: Self.voiceVolumeKey) }
    }

    /// The language the voice speaks, as a `VoicePacks` tag: `en` until the athlete picks another.
    /// Read back through `VoicePacks.of`, so a value for a language this version does not have is
    /// English rather than an error.
    public var voiceLanguage: String {
        get { VoicePacks.of(defaults.string(forKey: Self.voiceLanguageKey)).tag }
        set { defaults.set(VoicePacks.of(newValue).tag, forKey: Self.voiceLanguageKey) }
    }

    /// How loud the track is, 0 to 1, before the voice ducks it.
    public var musicVolume: Float {
        get { min(max(float(Self.musicVolumeKey, Self.defaultMusicVolume), 0), 1) }
        set { defaults.set(min(max(newValue, 0), 1), forKey: Self.musicVolumeKey) }
    }

    /// Whether the daily reminder is on. Off until the athlete asks for it.
    public var reminderOn: Bool {
        get { bool(Self.reminderOnKey, false) }
        set { defaults.set(newValue, forKey: Self.reminderOnKey) }
    }

    /// Minutes after local midnight the reminder is due, 0 to 1439.
    public var reminderMinute: Int {
        get { min(max(int(Self.reminderMinuteKey, Reminder.defaultMinuteOfDay), 0), 1439) }
        set { defaults.set(min(max(newValue, 0), 1439), forKey: Self.reminderMinuteKey) }
    }

    /// The year the athlete was born, or 0 when they have not said. A year rather than an age: an
    /// age goes stale the moment it is typed, and nobody reopens a settings screen once a year to
    /// keep a number current.
    public var birthYear: Int {
        get { int(Self.birthYearKey, 0) }
        set { defaults.set(newValue, forKey: Self.birthYearKey) }
    }

    /// Which of the heart-rate equation's fits applies, or nil when it has never been said. The
    /// third choice averages the other two instead of guessing between them. A name this build does
    /// not know decodes to nil rather than a guessed default.
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

    /// The watch or strap paired for heart rate, or nil when none is. The two keys behind it are
    /// only ever written or cleared together: an address without the name that goes with it is not
    /// something a reconnect could fall back to, and a name without an address is not something it
    /// could connect to in the first place.
    public var heartRateDevice: HeartRateDevice? {
        get {
            guard let address = defaults.string(forKey: Self.hrAddressKey),
                  let name = defaults.string(forKey: Self.hrNameKey) else { return nil }
            return HeartRateDevice(address: address, name: name)
        }
        set {
            if let device = newValue {
                defaults.set(device.address, forKey: Self.hrAddressKey)
                defaults.set(device.name, forKey: Self.hrNameKey)
            } else {
                defaults.removeObject(forKey: Self.hrAddressKey)
                defaults.removeObject(forKey: Self.hrNameKey)
            }
        }
    }

    /// What the athlete wants to be called, or nil when they have not said. Nil is meaningful: the
    /// app goes on saying "You". Tidied on the way in and again on the way out, so that a value a
    /// backup restored from some other build still shows the same way on every screen.
    public var displayName: String? {
        get { Avatar.cleanName(defaults.string(forKey: Self.displayNameKey)) }
        set { set(Avatar.cleanName(newValue), forKey: Self.displayNameKey) }
    }

    /// The athlete's age in `nowYear`, or nil when the year of birth has never been said.
    public func age(nowYear: Int) -> Int? { birthYear == 0 ? nil : nowYear - birthYear }

    /// The body `Calories` is handed: weight, age and sex read together, at one moment, so an
    /// estimate and the card that explains it can never be worked out from different people.
    public func body(nowYear: Int) -> Body { Body(bodyWeightKg, age: age(nowYear: nowYear), sex: sex) }
}
