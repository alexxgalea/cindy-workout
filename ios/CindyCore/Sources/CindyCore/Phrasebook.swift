import Foundation

/// The words for one language: every `VoiceLine`, as a sentence a text-to-speech voice can say.
///
/// One implementation per language, each an exhaustive `switch` over `VoiceLine` with no `default`,
/// so a language that is missing a line is a compile error rather than a silent gap in the middle
/// of a workout. Kept free of platform types, which is what makes the grammar — plurals,
/// agreement, what a voice does to "3." — something a test can pin.
///
/// The English phrasebook, `PhrasebookEn`, is the reference: it says what the app has always said,
/// and the others are its translations.
public protocol Phrasebook: Sendable {

    /// The language this speaks for, as a lower-case tag such as `en` or `es`.
    var tag: String { get }

    /// The words for `line`. Never blank: a voice handed an empty utterance says nothing at all.
    func say(_ line: VoiceLine) -> String
}

/// The whole minutes and the seconds left over in `ms`, dropping any part of a second.
///
/// Shared because every language wants the same split and only the words around it differ; the
/// dropped fraction matches the English phrasebook, which has always truncated rather than rounded.
func minutesAndSeconds(_ ms: Int64) -> (minutes: Int, seconds: Int) {
    let total = ms / 1000
    return (Int(total / 60), Int(total % 60))
}

extension String {
    /// The same text with its first letter in capitals, for a counted phrase that opens a sentence.
    ///
    /// Written-out ones ("una ronda") are lower case where they fall mid-sentence and would
    /// otherwise open one that way. A voice ignores case, so this is for the people who read the
    /// lines.
    func capitalised() -> String { prefix(1).uppercased() + dropFirst() }
}
