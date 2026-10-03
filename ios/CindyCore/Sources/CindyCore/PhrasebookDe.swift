import Foundation

/// The voice in German.
///
/// Register: the informal "du", in short imperatives. Plurals: one and other. 1 is written out
/// ("eine Runde"), because a voice does not always agree the article with the noun after a digit.
/// The time of a round follows the word "Zeit" rather than "in", since "in" would put the count in
/// the dative ("in einer Minute") where the average wants the nominative ("eine Minute"). Sentences
/// end on a word, never on a number: German engines read "12." as "zwölfte".
///
/// Counts other than 1 are left as digits for the engine to agree with the noun that follows.
///
/// Written without a native speaker's review; the lines are short so that they can be read that way.
public struct PhrasebookDe: Phrasebook {

    public init() {}

    public let tag = "de"

    public func say(_ line: VoiceLine) -> String {
        switch line {
        case .count(let reps): return "\(reps)"
        case .movement(let exercise):
            switch exercise {
            case .pullup: return "Klimmzüge"
            case .pushup: return "Liegestütze"
            case .squat: return "Kniebeugen"
            }
        case .roundDone(let round, let splitMs): return "Runde \(round), Zeit \(duration(splitMs))"
        case .phoneMoved: return "Das Handy hat sich bewegt. Prüfe den Bildausschnitt."
        case .setUp: return "Geh ins Bild und mach dann zwei langsame Klimmzüge"
        case .go(let calibrated): return calibrated ? "Kalibriert. Los." : "Los. Klimmzüge"
        case .resume: return "Weiter"
        case .finished(let early): return early ? "Gestoppt." : "Zeit."
        case .score(let rounds, let totalReps): return score(rounds, totalReps)
        case .averaging(let roundMs): return "Im Schnitt \(duration(roundMs)) pro Runde"
        case .beatBenchmark(let name): return "Du hast \(name) geschlagen"
        case .ready: return "Bereit"
        case .fault(let text): return Hint.of(text).map { hint($0) } ?? "Prüfe deine Position"
        case .clock(let mark, let rounds, let totalReps, let projectedRounds):
            return clock(mark, rounds, totalReps, projectedRounds)
        case .sample: return "Drei. Vier. Fünf. Liegestütze."
        case .volumeCheck: return "Drei"
        case .recordingSoon(let n): return "Aufnahme in \(secondsAfterIn(n))"
        case .recordingStarted: return "Aufnahme läuft"
        case .recordingFailed: return "Aufnahme fehlgeschlagen"
        case .adaptiveHeelsFlat: return "Angepasste Cindy aktiviert für Kniebeugen mit Fersen am Boden."
        }
    }

    private func hint(_ hint: Hint) -> String {
        switch hint {
        case .stepIntoFrame: return "Geh ins Bild"
        case .finishSetupFirst: return "Schließe zuerst die Vorbereitung ab"
        case .tracking: return "Ich suche dich"
        case .hangFromBar: return "Häng dich an die Stange"
        case .hangVertically: return "Häng dich senkrecht an die Stange"
        case .getOnBar: return "Greif die Stange"
        case .showBothHands: return "Zeig beide Hände"
        case .showYourHead: return "Zeig deinen Kopf"
        case .armsOutOfFrame: return "Deine Arme sind außerhalb des Bildes"
        case .getHeadOverBar: return "Bring den Kopf über die Stange"
        case .returnToDeadHang: return "Häng dich wieder mit gestreckten Armen an die Stange"
        case .lowerAllTheWay: return "Geh ganz nach unten"
        case .getSetOnFloor: return "Geh in Position auf dem Boden"
        case .getOnFloor: return "Geh auf den Boden"
        case .standUpToStart: return "Steh zum Start auf"
        case .showYourLegs: return "Zeig der Kamera deine Beine"
        case .driveUp: return "Drück dich hoch"
        case .goDown: return "Geh runter"
        case .losingYou: return "Ich verliere dich aus dem Blick. Mehr Licht hilft."
        case .tooDark: return "Zu dunkel zum Zählen. Tippe auf die Taste plus eins."
        case .cantSeeYou: return "Ich sehe dich nicht. Tippe auf die Taste plus eins."
        }
    }

    private func clock(_ mark: ClockMark, _ rounds: Int, _ totalReps: Int, _ projected: Int?) -> String {
        switch mark {
        case .tenSecondsLeft: return "Zehn Sekunden. Gib alles."
        case .oneMinuteLeft:
            return "Noch eine Minute. \(roundsText(rounds).capitalised()) geschafft. Beende die laufende Runde."
        case .twoMinutesLeft: return "Zwei Minuten. " + push(rounds, totalReps)
        case .fiveMinutesLeft: return "Noch fünf Minuten. " + pace(rounds, projected)
        case .halfway: return "Halbzeit. " + pace(rounds, projected)
        case .fiveMinutesIn: return "Fünf Minuten sind um. " + pace(rounds, projected)
        }
    }

    private func pace(_ rounds: Int, _ projected: Int?) -> String {
        if let projected {
            return "\(roundsText(rounds).capitalised()) geschafft. Tempo für \(roundsText(projected))."
        }
        return "Halte dein Tempo."
    }

    private func push(_ rounds: Int, _ totalReps: Int) -> String {
        score(rounds, totalReps) + (rounds < 1 ? ". Weiter so." : ". Halte das Tempo.")
    }

    private func score(_ rounds: Int, _ totalReps: Int) -> String {
        (rounds < 1 ? reps(totalReps) : "\(roundsText(rounds)), \(reps(totalReps)) insgesamt").capitalised()
    }

    private func duration(_ ms: Int64) -> String {
        let (m, s) = minutesAndSeconds(ms)
        if m == 0 { return seconds(s) }
        if s == 0 { return minutes(m) }
        return "\(minutes(m)) und \(seconds(s))"
    }

    private func roundsText(_ n: Int) -> String { noun(n, "eine Runde", "Runden") }
    private func reps(_ n: Int) -> String { noun(n, "eine Wiederholung", "Wiederholungen") }
    private func minutes(_ n: Int) -> String { noun(n, "eine Minute", "Minuten") }
    private func seconds(_ n: Int) -> String { noun(n, "eine Sekunde", "Sekunden") }

    /// After "in" the singular is dative: "in einer Sekunde".
    private func secondsAfterIn(_ n: Int) -> String { n == 1 ? "einer Sekunde" : seconds(n) }

    private func noun(_ n: Int, _ one: String, _ other: String) -> String {
        Plurals.oneOther(n) == .one ? one : "\(n) \(other)"
    }
}
