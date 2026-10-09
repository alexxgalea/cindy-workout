import Foundation

// The sheets that change what the athlete has told the app, decided apart from how they look.
// Ports of the choices and checks in `Dialogs.kt` and `AccountActivity.kt`: what each sheet says,
// what it refuses, what it keeps and when. The screen draws a field or a list and calls these.

/// "Your body weight": the one thing `Calories` needs and the camera cannot see.
public enum BodyWeightForm {

    public static let title = "Your body weight"
    public static let subtitle = "Calories are estimated from body weight and how hard you worked. "
        + "It stays on this phone."
    public static let hint = "kg"
    public static let tooLight = "Enter a weight between \(Int(Profile.minKg)) and \(Int(Profile.maxKg)) kg"

    /// What the field starts with: a weight already entered is there to be replaced.
    public static func initialText(_ profile: Profile) -> String {
        profile.hasBodyWeight ? JavaText.fixed(profile.bodyWeightKg, 0) : ""
    }

    public enum Outcome: Equatable, Sendable {
        case saved(Double)
        /// A message to show, with nothing stored.
        case refused(String)
    }

    /// Reads a weight the way the field gives it. A comma is accepted for the point, because the
    /// number pad of a phone set to many languages types one.
    public static func parse(_ text: String) -> Double? {
        let trimmed = Records.trimmed(text).replacingOccurrences(of: ",", with: ".")
        guard let kg = Double(trimmed), kg.isFinite else { return nil }
        return kg
    }

    /// Stores a plausible weight and says what was stored, or refuses with the message.
    @discardableResult
    public static func save(_ text: String, to profile: Profile) -> Outcome {
        guard let kg = parse(text), kg >= Profile.minKg, kg <= Profile.maxKg else { return .refused(tooLight) }
        profile.bodyWeightKg = kg
        return .saved(kg)
    }
}

/// "For heart rate": a birth year and a sex, the two things `Calories` needs beyond weight.
public enum HeartRateDetailsForm {

    public static let title = "For heart rate"
    public static let subtitle = "Heart-rate calorie formulas are fitted separately for women and men, and "
        + "shift with age, and so does the maximum your heart rate zones are measured against. "
        + "Used only for those, and it stays on this phone."
    public static let hint = "Year of birth"
    public static let sexTitle = "SEX"
    public static let badYear = "Enter a birth year that makes you \(Profile.minAge) to \(Profile.maxAge)"
    public static let noSex = "Choose one — the formula needs it"

    /// The note under a sex option: the third one says what it does.
    public static func note(for sex: Sex) -> String? {
        sex == .unstated ? "uses the average of both formulas" : nil
    }

    public static func initialYear(_ profile: Profile) -> String {
        profile.birthYear != 0 ? String(profile.birthYear) : ""
    }

    public enum Outcome: Equatable, Sendable {
        case saved
        case refused(String)
    }

    /// Stores both once both are valid. The year is checked first, then the sex.
    @discardableResult
    public static func save(year text: String, sex: Sex?, nowYear: Int, to profile: Profile) -> Outcome {
        let year = Records.toInt(Records.trimmed(text))
        let age = year.map { nowYear - $0 }
        guard let year, let age, age >= Profile.minAge, age <= Profile.maxAge else { return .refused(badYear) }
        guard let sex else { return .refused(noSex) }
        profile.birthYear = year
        profile.sex = sex
        return .saved
    }
}

/// "Your name": kept only when the athlete says SAVE, and taken back by emptying it.
public enum NameForm {

    public static let title = "Your name"
    public static let subtitle = "Shown in the menu and beside your scores. Leave it empty to stay "
        + "\u{201C}You\u{201D}. It stays on this phone."
    public static let hint = "Your name"

    /// What the field holds as it is typed: never longer than `Avatar.maxName` UTF-16 units, and
    /// never ending in half a character.
    public static func limited(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        var units = 0
        for scalar in text.unicodeScalars {
            let width = scalar.value > 0xFFFF ? 2 : 1
            if units + width > Avatar.maxName { break }
            out.append(scalar)
            units += width
        }
        return String(out)
    }

    public static func save(_ text: String, to profile: Profile) { profile.displayName = text }
}

/// "Your photo": what the sheet offers depends on whether there is one to remove.
public enum PhotoSheet {

    public static let title = "Your photo"
    public static let subtitle = "Pick a picture from your phone. It is cut to a square and a copy is kept "
        + "on this phone; the original stays where it is."
    public static let failedToRemove = "The photo could not be removed"
    public static let failedToUse = "That picture could not be used"

    public struct Action: Equatable, Sendable {
        public let title: String
        public let destructive: Bool
    }

    /// The primary action first. REMOVE only where there is a photo, CANCEL only where there is not.
    public static func actions(hasPhoto: Bool) -> [Action] {
        [Action(title: "CHOOSE PHOTO", destructive: false),
         hasPhoto ? Action(title: "REMOVE", destructive: true) : Action(title: "CANCEL", destructive: false)]
    }

    /// What a screen reader says for the picture in the header.
    public static func spoken(hasPhoto: Bool) -> String { hasPhoto ? "Your photo, tap to change" : "Add a photo" }
}

/// "Make Cindy yours": one choice per movement, taken before the clock starts.
///
/// Neutral names only. No "easy", "beginner", "scaled" or "cheat": a band-assisted pull-up is a
/// different prescription, not a lesser athlete. What the sheet does say plainly is which choices
/// the camera can score and which it will ask to be tapped in. Nothing here changes until SAVE.
public struct MovementsForm: Equatable, Sendable {

    public static let title = "Make Cindy yours"
    public static let subtitle = "Anything other than the standard three is saved as an Adaptive Cindy and "
        + "ranked against your own sessions at the same movements."
    public static let spotTitle = "Spot heels-flat squats"
    public static let spotNote = "Off while it's being tested. When on, three heels-flat squats in a standard Cindy "
        + "switch it to Adaptive Cindy — Cindy says so out loud — and count them, the "
        + "first three included. Applies when Air squat is chosen."
    public static let refusedWhileLive = "Reset the workout first to change movements"

    public struct Option: Equatable, Sendable {
        public let label: String
        /// "you tap +1" where the movement is counted by hand.
        public let note: String?
        /// The same note in words a screen reader should say.
        public let spokenNote: String?
        public var spoken: String { label + (spokenNote.map { ", \($0)" } ?? "") }
    }

    public var pull: PullVariant
    public var push: PushVariant
    public var squat: SquatVariant
    public var smart: Bool

    public init(current: CindyProfile, smartSquats: Bool) {
        pull = current.pull
        push = current.push
        squat = current.squat
        smart = smartSquats
    }

    private static func option(_ label: String, _ tracking: Tracking) -> Option {
        tracking == .manual ? Option(label: label, note: "you tap +1", spokenNote: "you tap plus one")
            : Option(label: label, note: nil, spokenNote: nil)
    }

    public static let pullOptions = PullVariant.allCases.map { option($0.label, $0.tracking) }
    public static let pushOptions = PushVariant.allCases.map { option($0.label, $0.tracking) }
    public static let squatOptions = SquatVariant.allCases.map { option($0.label, $0.tracking) }

    public var chosen: CindyProfile { CindyProfile(pull: pull, push: push, squat: squat) }

    /// What a screen reader says for the setting: "Spot heels-flat squats, off".
    public var spotSpoken: String { "\(Self.spotTitle), \(smart ? "on" : "off")" }

    /// SAVE: the setting goes first, then the movements. Returns what was chosen.
    @discardableResult
    public func save(to profile: Profile) -> CindyProfile {
        profile.smartSquats = smart
        let picked = chosen
        profile.movements = picked
        return picked
    }
}

/// Why a standard Cindy came back as an Adaptive one, and a way to make the change the athlete's own.
///
/// The second half matters more than the first: smart squat counting is an experiment, and the
/// honest thing to do with its first guess is to say what it guessed and let the athlete either
/// keep it or not. The note names the one way it could have guessed wrong, which is a camera that
/// cannot see the knees bend.
public enum HeelsFlatSheet {

    public static let title = "Adaptive Cindy activated"
    public static let subtitle = "Your squats were heels flat, so after three of them Cindy switched this "
        + "session to Adaptive Cindy and counted every squat from then on, those three "
        + "included. It is ranked with your other heels-flat sessions."
    public static let note = "If you were squatting to full depth, the camera may not be seeing your knees "
        + "bend — stand side-on to the phone, or raise it. SET HEELS FLAT makes it "
        + "your choice for every workout."
    public static let primary = "SET HEELS FLAT"
    public static let secondary = "NOT NOW"
    public static let done = "Squats set to heels flat"

    /// Makes heels flat the athlete's own squat for every workout, keeping the other two as chosen.
    public static func setHeelsFlat(on profile: Profile) {
        var movements = profile.movements
        movements.squat = .heelsFlat
        profile.movements = movements
    }
}

/// The voice sheet: whether it counts, how loud, and in which language. Kept only on SAVE.
public struct VoiceForm: Equatable, Sendable {

    public static let title = "Voice"
    public static let subtitle = "Counts each rep out loud, calls the movement changes, and says when "
        + "you are in a position that will score."
    public static let toggleTitle = "Count reps out loud"
    public static let note = "Mixes against the phone's own media volume rather than replacing it. The track "
        + "drops out of the way whenever the voice speaks."

    public var on: Bool
    public var volume: Float
    public var language: String

    public init(_ profile: Profile) {
        on = profile.voiceOn
        volume = profile.voiceVolume
        language = profile.voiceLanguage
    }

    public func save(to profile: Profile) {
        profile.voiceOn = on
        profile.voiceVolume = volume
        profile.voiceLanguage = language
    }
}
