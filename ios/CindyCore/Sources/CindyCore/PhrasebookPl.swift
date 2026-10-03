import Foundation

/// The voice in Polish.
///
/// Register: the informal imperative. Plurals: one, few and many (1 runda, 2–4 rundy, 5 rund, but
/// 12 rund and 22 rundy). 1 and 2 are written out for the feminine nouns ("jedna runda", "dwie
/// rundy"), because a voice can read a bare "2 rundy" as "dwa rundy"; the neuter "powtórzenie" takes
/// "jedno" and needs nothing for 2.
///
/// A count inside a sentence would need the case of the verb before it, and the feminine singular
/// changes shape in the accusative ("rundę"), so counted phrases are kept to places that ask for
/// the nominative: a standalone score, a duration after "czas", and a label such as "Ukończone
/// rundy: 6". The one accusative that cannot be avoided ("za jedną sekundę", "na jedną rundę") is
/// written out. Sentences end on a word, never on a number: Polish engines read "12." as an ordinal.
///
/// Counts that end in 1 or 2 beyond those written out (21, 22, 102 and so on) are left as digits
/// for the engine to agree. That is the known gap, and the one to listen for on a real voice.
///
/// Written without a native speaker's review; the lines are short so that they can be read that way.
public struct PhrasebookPl: Phrasebook {

    public init() {}

    public let tag = "pl"

    public func say(_ line: VoiceLine) -> String {
        switch line {
        case .count(let reps): return "\(reps)"
        case .movement(let exercise):
            switch exercise {
            case .pullup: return "podciągnięcia"
            case .pushup: return "pompki"
            case .squat: return "przysiady"
            }
        case .roundDone(let round, let splitMs): return "Runda \(round), czas \(duration(splitMs))"
        case .phoneMoved: return "Telefon się przesunął. Sprawdź kadr."
        case .setUp: return "Wejdź w kadr i zrób dwa powolne podciągnięcia"
        case .go(let calibrated): return calibrated ? "Skalibrowano. Start." : "Start. Podciągnięcia"
        case .resume: return "Wznawiamy"
        case .finished(let early): return early ? "Zatrzymano." : "Koniec czasu."
        case .score(let rounds, let totalReps): return score(rounds, totalReps)
        case .averaging(let roundMs): return "Średnio \(duration(roundMs)) na rundę"
        case .beatBenchmark(let name): return "Wynik lepszy niż \(name)"
        case .ready: return "Gotowe"
        case .fault(let text): return Hint.of(text).map { hint($0) } ?? "Sprawdź swoją pozycję"
        case .clock(let mark, let rounds, let totalReps, let projectedRounds):
            return clock(mark, rounds, totalReps, projectedRounds)
        case .sample: return "Trzy. Cztery. Pięć. Pompki."
        case .volumeCheck: return "Trzy"
        case .recordingSoon(let n): return "Nagrywanie za \(secondsAfterZa(n))"
        case .recordingStarted: return "Nagrywanie rozpoczęte"
        case .recordingFailed: return "Nagrywanie nie powiodło się"
        case .adaptiveHeelsFlat: return "Włączono adaptacyjną Cindy dla przysiadów z piętami na podłodze."
        }
    }

    private func hint(_ hint: Hint) -> String {
        switch hint {
        case .stepIntoFrame: return "Wejdź w kadr"
        case .finishSetupFirst: return "Najpierw dokończ przygotowanie"
        case .tracking: return "Szukam cię"
        case .hangFromBar: return "Zwiś na drążku"
        case .hangVertically: return "Zwiś pionowo na drążku"
        case .getOnBar: return "Chwyć drążek"
        case .showBothHands: return "Pokaż obie dłonie"
        case .showYourHead: return "Pokaż głowę"
        case .armsOutOfFrame: return "Ramiona są poza kadrem"
        case .getHeadOverBar: return "Podnieś głowę nad drążek"
        case .returnToDeadHang: return "Wróć do zwisu na wyprostowanych rękach"
        case .lowerAllTheWay: return "Opuść się do końca"
        case .getSetOnFloor: return "Przyjmij pozycję na podłodze"
        case .getOnFloor: return "Połóż się na podłodze"
        case .standUpToStart: return "Wstań, żeby zacząć"
        case .showYourLegs: return "Pokaż nogi kamerze"
        case .driveUp: return "Wypchnij się w górę"
        case .goDown: return "Opuść się"
        case .losingYou: return "Tracę cię z oczu. Więcej światła pomoże."
        case .tooDark: return "Za ciemno, żeby liczyć. Dotknij przycisku plus jeden."
        case .cantSeeYou: return "Nie widzę cię. Dotknij przycisku plus jeden."
        }
    }

    private func clock(_ mark: ClockMark, _ rounds: Int, _ totalReps: Int, _ projected: Int?) -> String {
        switch mark {
        case .tenSecondsLeft: return "Dziesięć sekund. Daj z siebie wszystko."
        case .oneMinuteLeft: return "Została minuta. Ukończone rundy: \(rounds), dokończ bieżącą."
        case .twoMinutesLeft: return "Dwie minuty. " + push(rounds, totalReps)
        case .fiveMinutesLeft: return "Zostało pięć minut. " + pace(rounds, projected)
        case .halfway: return "Połowa czasu. " + pace(rounds, projected)
        case .fiveMinutesIn: return "Pięć minut za nami. " + pace(rounds, projected)
        }
    }

    private func pace(_ rounds: Int, _ projected: Int?) -> String {
        if let projected { return "Ukończone rundy: \(rounds), tempo na \(roundsAfterNa(projected))." }
        return "Utrzymaj swoje tempo."
    }

    private func push(_ rounds: Int, _ totalReps: Int) -> String {
        score(rounds, totalReps) + (rounds < 1 ? ". Dalej." : ". Utrzymaj tempo.")
    }

    private func score(_ rounds: Int, _ totalReps: Int) -> String {
        (rounds < 1 ? reps(totalReps) : "\(roundsText(rounds)), łącznie \(reps(totalReps))").capitalised()
    }

    private func duration(_ ms: Int64) -> String {
        let (m, s) = minutesAndSeconds(ms)
        if m == 0 { return seconds(s) }
        if s == 0 { return minutes(m) }
        return "\(minutes(m)) i \(seconds(s))"
    }

    private func roundsText(_ n: Int) -> String {
        switch Plurals.polish(n) {
        case .one: return "jedna runda"
        case .few: return n == 2 ? "dwie rundy" : "\(n) rundy"
        default: return "\(n) rund"
        }
    }

    private func reps(_ n: Int) -> String {
        switch Plurals.polish(n) {
        case .one: return "jedno powtórzenie"
        case .few: return "\(n) powtórzenia"
        default: return "\(n) powtórzeń"
        }
    }

    private func minutes(_ n: Int) -> String {
        switch Plurals.polish(n) {
        case .one: return "jedna minuta"
        case .few: return n == 2 ? "dwie minuty" : "\(n) minuty"
        default: return "\(n) minut"
        }
    }

    private func seconds(_ n: Int) -> String {
        switch Plurals.polish(n) {
        case .one: return "jedna sekunda"
        case .few: return n == 2 ? "dwie sekundy" : "\(n) sekundy"
        default: return "\(n) sekund"
        }
    }

    /// After "za" the feminine singular is accusative: "za jedną sekundę".
    private func secondsAfterZa(_ n: Int) -> String { Plurals.polish(n) == .one ? "jedną sekundę" : seconds(n) }

    /// After "na" the feminine singular is accusative: "na jedną rundę".
    private func roundsAfterNa(_ n: Int) -> String { Plurals.polish(n) == .one ? "jedną rundę" : roundsText(n) }
}
