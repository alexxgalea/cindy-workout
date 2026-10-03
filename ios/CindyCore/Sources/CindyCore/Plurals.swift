import Foundation

/// The plural forms the voice's languages use, named as the Unicode CLDR rules name them.
public enum Plural: Sendable { case one, few, many, other }

/// Which form of a noun goes with a count, for each rule family the phrasebooks need.
///
/// "2 round" is a mistake in English and only a slightly worse one in Spanish, but in Polish,
/// Romanian and Russian the form changes at 2, at 5, at 12 and again at 22, and a score is read
/// out loud to someone who is out of breath: "5 rundy" instead of "5 rund" is noticed. So each
/// language names the rule it follows rather than approximating with "one or more than one".
///
/// These are the CLDR cardinal rules restricted to whole numbers, which is all a count of rounds,
/// repetitions, minutes or seconds ever is. Every argument is a count and never negative.
public enum Plurals {

    /// English, Spanish, German, Italian, Dutch: exactly one is singular.
    public static func oneOther(_ n: Int) -> Plural { n == 1 ? .one : .other }

    /// French and Brazilian Portuguese: nought and one are both singular ("0 tour").
    public static func zeroOrOne(_ n: Int) -> Plural { n == 0 || n == 1 ? .one : .other }

    /// Polish: one; then a "few" form for counts ending 2–4 except the teens, and a "many" form
    /// for everything else (0, 5–21, 25–31 …), so 22 is "few" and 12 is not.
    public static func polish(_ n: Int) -> Plural {
        if n == 1 { return .one }
        if (2...4).contains(n % 10) && !(12...14).contains(n % 100) { return .few }
        return .many
    }

    /// Romanian: one; "few" for 0 and for anything ending 01–19 (so 2 to 19, and 101 to 119); and
    /// "other" from 20, which is also the form that takes "de" ("20 de runde", "120 de runde").
    public static func romanian(_ n: Int) -> Plural {
        if n == 1 { return .one }
        if n == 0 || (1...19).contains(n % 100) { return .few }
        return .other
    }

    /// Russian: "one" for counts ending 1 except 11, "few" for 2–4 except the teens, "many" for
    /// the rest. 21 is singular again, and 111 is not.
    public static func russian(_ n: Int) -> Plural {
        if n % 10 == 1 && n % 100 != 11 { return .one }
        if (2...4).contains(n % 10) && !(12...14).contains(n % 100) { return .few }
        return .many
    }
}
