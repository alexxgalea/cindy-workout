import Foundation

/// The voice in Dutch.
///
/// Register: imperatives without a pronoun, which is neither formal nor informal. Plurals: one and
/// other. 1 is written out ("een ronde"), so a voice does not read a bare digit as a word of its
/// own. The movements use the Dutch names ("optrekken", "opdrukken") because a Dutch voice reads
/// the English "pull-ups" as if it were Dutch. Sentences end on a word, never on a number.
///
/// Counts other than 1 are left as digits for the engine to agree with the noun that follows.
///
/// Written without a native speaker's review; the lines are short so that they can be read that way.
public struct PhrasebookNl: Phrasebook {

    public init() {}

    public let tag = "nl"

    public func say(_ line: VoiceLine) -> String {
        switch line {
        case .count(let reps): return "\(reps)"
        case .movement(let exercise):
            switch exercise {
            case .pullup: return "optrekken"
            case .pushup: return "opdrukken"
            case .squat: return "squats"
            }
        case .roundDone(let round, let splitMs): return "Ronde \(round) in \(duration(splitMs))"
        case .phoneMoved: return "De telefoon is bewogen. Controleer het beeld."
        case .setUp: return "Ga in beeld en doe twee keer langzaam optrekken"
        case .go(let calibrated): return calibrated ? "Gekalibreerd. Start." : "Start. Optrekken"
        case .resume: return "Hervat"
        case .finished(let early): return early ? "Gestopt." : "Tijd."
        case .score(let rounds, let totalReps): return score(rounds, totalReps)
        case .averaging(let roundMs): return "Gemiddeld \(duration(roundMs)) per ronde"
        case .beatBenchmark(let name): return "Je hebt \(name) verslagen"
        case .ready: return "Klaar"
        case .fault(let text): return Hint.of(text).map { hint($0) } ?? "Controleer je positie"
        case .clock(let mark, let rounds, let totalReps, let projectedRounds):
            return clock(mark, rounds, totalReps, projectedRounds)
        case .sample: return "Drie. Vier. Vijf. Opdrukken."
        case .volumeCheck: return "Drie"
        case .recordingSoon(let n): return "Opname over \(seconds(n))"
        case .recordingStarted: return "Opname gestart"
        case .recordingFailed: return "Opname mislukt"
        case .adaptiveHeelsFlat: return "Aangepaste Cindy ingeschakeld voor squats met de hielen op de grond."
        }
    }

    private func hint(_ hint: Hint) -> String {
        switch hint {
        case .stepIntoFrame: return "Ga in beeld staan"
        case .finishSetupFirst: return "Rond eerst de voorbereiding af"
        case .tracking: return "Ik zoek je"
        case .hangFromBar: return "Hang aan de stang"
        case .hangVertically: return "Hang verticaal aan de stang"
        case .getOnBar: return "Pak de stang"
        case .showBothHands: return "Laat allebei je handen zien"
        case .showYourHead: return "Laat je hoofd zien"
        case .armsOutOfFrame: return "Je armen zijn buiten beeld"
        case .getHeadOverBar: return "Breng je hoofd boven de stang"
        case .returnToDeadHang: return "Hang weer met gestrekte armen"
        case .lowerAllTheWay: return "Ga helemaal omlaag"
        case .getSetOnFloor: return "Ga in positie op de grond"
        case .getOnFloor: return "Ga op de grond"
        case .standUpToStart: return "Sta op om te beginnen"
        case .showYourLegs: return "Laat je benen aan de camera zien"
        case .driveUp: return "Duw omhoog"
        case .goDown: return "Ga omlaag"
        case .losingYou: return "Ik verlies je uit beeld. Meer licht helpt."
        case .tooDark: return "Te donker om te tellen. Tik op de knop plus één."
        case .cantSeeYou: return "Ik zie je niet. Tik op de knop plus één."
        }
    }

    private func clock(_ mark: ClockMark, _ rounds: Int, _ totalReps: Int, _ projected: Int?) -> String {
        switch mark {
        case .tenSecondsLeft: return "Tien seconden. Geef alles."
        case .oneMinuteLeft: return "Nog een minuut. Je hebt \(roundsText(rounds)). Maak de huidige ronde af."
        case .twoMinutesLeft: return "Twee minuten. " + push(rounds, totalReps)
        case .fiveMinutesLeft: return "Nog vijf minuten. " + pace(rounds, projected)
        case .halfway: return "Halverwege. " + pace(rounds, projected)
        case .fiveMinutesIn: return "Vijf minuten bezig. " + pace(rounds, projected)
        }
    }

    private func pace(_ rounds: Int, _ projected: Int?) -> String {
        if let projected { return "Je hebt \(roundsText(rounds)). Tempo voor \(roundsText(projected))." }
        return "Houd je tempo vast."
    }

    private func push(_ rounds: Int, _ totalReps: Int) -> String {
        score(rounds, totalReps) + (rounds < 1 ? ". Ga door." : ". Houd het tempo vast.")
    }

    private func score(_ rounds: Int, _ totalReps: Int) -> String {
        (rounds < 1 ? reps(totalReps) : "\(roundsText(rounds)), \(reps(totalReps)) in totaal").capitalised()
    }

    private func duration(_ ms: Int64) -> String {
        let (m, s) = minutesAndSeconds(ms)
        if m == 0 { return seconds(s) }
        if s == 0 { return minutes(m) }
        return "\(minutes(m)) en \(seconds(s))"
    }

    private func roundsText(_ n: Int) -> String { noun(n, "een ronde", "rondes") }
    private func reps(_ n: Int) -> String { noun(n, "een herhaling", "herhalingen") }
    private func minutes(_ n: Int) -> String { noun(n, "een minuut", "minuten") }
    private func seconds(_ n: Int) -> String { noun(n, "een seconde", "seconden") }

    private func noun(_ n: Int, _ one: String, _ other: String) -> String {
        Plurals.oneOther(n) == .one ? one : "\(n) \(other)"
    }
}
