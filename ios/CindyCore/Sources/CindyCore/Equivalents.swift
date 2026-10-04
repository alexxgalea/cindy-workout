import Foundation

/// Whether the phone's emoji font can draw a given emoji.
///
/// A platform question, so it is a protocol: the oldest phone this app runs on bundles an emoji font
/// that predates some of these animals, and a hippo drawn as an empty box is worse than a different
/// animal. The app answers it from the system font; the tests answer it with a fake.
public protocol EmojiFont {
    func canDraw(_ emoji: String) -> Bool
}

/// An emoji font that answers from a closure.
public struct AnyEmojiFont: EmojiFont {
    private let check: (String) -> Bool

    public init(_ check: @escaping (String) -> Bool) { self.check = check }

    public func canDraw(_ emoji: String) -> Bool { check(emoji) }

    /// Draws everything.
    public static let all = AnyEmojiFont { _ in true }
}

/// Everyday things a session's weight and energy are the size of, so "12,940 kg" and "312 kcal" mean
/// something at a glance.
///
/// Weight is compared with animals, which is the point of the card. Energy is deliberately *not*
/// compared with food: "that was a doughnut" is the comparison that turns a workout into a debt, and
/// nobody asked for it. A cup of tea, a phone charge and an hour of lamp light are the same kind of
/// number with no moral attached. Port of `Equivalents.kt`.
public enum Equivalents {

    public struct Animal: Equatable, Sendable {
        public let name: String
        public let plural: String
        public let kg: Int
        public let emoji: String

        public init(_ name: String, _ plural: String, _ kg: Int, _ emoji: String) {
            self.name = name
            self.plural = plural
            self.kg = kg
            self.emoji = emoji
        }
    }

    /// Heaviest first, so a larger session is matched by a larger animal when several would do.
    public static let animals: [Animal] = [
        Animal("T. rex", "T. rexes", 8000, "🦖"),
        Animal("African elephant", "African elephants", 6000, "🐘"),
        Animal("white rhino", "white rhinos", 2300, "🦏"),
        Animal("hippo", "hippos", 1500, "🦛"),
        Animal("giraffe", "giraffes", 1200, "🦒"),
        Animal("cow", "cows", 700, "🐄"),
        Animal("horse", "horses", 500, "🐎"),
        Animal("brown bear", "brown bears", 300, "🐻"),
        Animal("gorilla", "gorillas", 160, "🦍"),
        Animal("giant panda", "giant pandas", 100, "🐼")
    ]

    /// The fewest and most of an animal the card will ever claim.
    private static let minAnimals = 1.0
    private static let maxAnimals = 12.0

    /// A count worth meeting: below two it is barely a multiple, above nine it stops being countable.
    private static let preferredMin = 2.0
    private static let preferredMax = 9.0

    /// `count` animals' worth, as `text` ("1.4 hippos", "9 hippos").
    public struct AnimalMatch: Equatable, Sendable {
        public let animal: Animal
        public let count: Double
        public let text: String
    }

    /// An animal `kg` is a sensible number of, or nil when none is (under one panda, over twelve
    /// T. rexes, or none of the candidates can be drawn).
    ///
    /// Counts in 2...9 are preferred. `rotation`, the session's local calendar day number, picks
    /// among them, so the athlete who trains every day does not meet the same hippo every time.
    /// Rotating by the session's own day rather than the clock keeps a reopened session showing what
    /// it showed the first time.
    public static func animalFor(_ kg: Double, rotation: Int64, font: EmojiFont) -> AnimalMatch? {
        if !(kg > 0.0) { return nil }
        let fits = animals
            .filter { font.canDraw($0.emoji) }
            .map { ($0, kg / Double($0.kg)) }
            .filter { $0.1 >= minAnimals && $0.1 <= maxAnimals }
        let preferred = fits.filter { $0.1 >= preferredMin && $0.1 <= preferredMax }
        let pool = preferred.isEmpty ? fits : preferred
        if pool.isEmpty { return nil }
        let (animal, count) = pool[Int(floorMod(rotation, Int64(pool.count)))]
        return AnimalMatch(animal: animal, count: count, text: countText(count, animal))
    }

    /// "1.4 hippos" below three, "9 hippos" from three up.
    ///
    /// Decided on the rounded figure, so 2.96 reads "3 hippos" and not "3.0 hippos", and 1.04 reads
    /// "1 hippo" and not "1.0 hippos".
    public static func countText(_ count: Double, _ animal: Animal) -> String {
        if count < 3.0 {
            let tenths = javaFixed(count, 1)
            if tenths == "1.0" { return "1 \(animal.name)" }
            if tenths != "3.0" { return "\(tenths) \(animal.plural)" }
        }
        let whole = JavaText.roundToInt(count)
        return "\(whole) \(whole == 1 ? animal.name : animal.plural)"
    }

    /// "As heavy as 9 hippos.", "At least as heavy as 9 hippos." for a lower-bound score.
    public static func heavySentence(_ match: AnimalMatch, atLeast: Bool) -> String {
        atLeast ? "At least as heavy as \(match.text)." : "As heavy as \(match.text)."
    }

    /// Beyond this many the row is five and a "×9".
    public static let maxEmoji = 5

    /// How many emoji to draw for `count`, one to five.
    public static func emojiCount(_ count: Double) -> Int {
        min(max(JavaText.roundToInt(count), 1), maxEmoji)
    }

    /// A non-food thing some energy is the size of.
    ///
    /// `kcal` is the energy in one of it, `sentence` words a whole-number count of it, and `method`
    /// says where the figure comes from, because the card is an estimate of an estimate and should
    /// show its working.
    public struct EnergyReference: Sendable {
        public let emoji: String
        public let kcal: Double
        public let method: String
        private let phrase: @Sendable (Int) -> String

        init(_ emoji: String, _ kcal: Double, _ method: String, phrase: @escaping @Sendable (Int) -> String) {
            self.emoji = emoji
            self.kcal = kcal
            self.method = method
            self.phrase = phrase
        }

        public func sentence(_ count: Int, atLeast: Bool) -> String {
            (atLeast ? "At least enough to " : "Enough to ") + phrase(count) + "."
        }
    }

    public static let energyReferences: [EnergyReference] = [
        EnergyReference("☕", 20.0,
                        "A cup of tea is 250 ml of water heated from 20 °C to boiling, about 20 kcal.") { n in
            "boil water for \(n) \(n == 1 ? "cup" : "cups") of tea"
        },
        EnergyReference("🔋", 13.0, "A full phone charge is about 13 kcal (15 Wh).") { n in
            "charge a phone fully \(n == 1 ? "once" : "\(n) times")"
        },
        EnergyReference("💡", 7.7, "An hour of a 9 W LED bulb is about 7.7 kcal.") { n in
            "run a 9 W LED bulb for \(n) \(n == 1 ? "hour" : "hours")"
        }
    ]

    private static let minEnergyCount = 1
    private static let maxEnergyCount = 60

    public struct EnergyMatch: Sendable {
        public let reference: EnergyReference
        public let count: Int
    }

    /// A reference `kcal` is between 1 and 60 of, or nil when none is (under about 7 kcal, or none of
    /// the three can be drawn). Rotated like `animalFor`, so consecutive sessions tend to differ.
    public static func energyFor(_ kcal: Double, rotation: Int64, font: EmojiFont) -> EnergyMatch? {
        if !(kcal > 0.0) { return nil }
        let fits = energyReferences
            .filter { font.canDraw($0.emoji) }
            .map { ($0, JavaText.roundToInt(kcal / $0.kcal)) }
            .filter { $0.1 >= minEnergyCount && $0.1 <= maxEnergyCount }
        if fits.isEmpty { return nil }
        let (reference, count) = fits[Int(floorMod(rotation, Int64(fits.count)))]
        return EnergyMatch(reference: reference, count: count)
    }

    /// `Math.floorMod`: the remainder takes the sign of the divisor, so a negative rotation still picks.
    private static func floorMod(_ a: Int64, _ b: Int64) -> Int64 {
        let r = a % b
        return r < 0 ? r + b : r
    }
}
