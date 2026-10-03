import Foundation

/// The voice in Italian.
///
/// Register: the informal "tu", in short imperatives. Plurals: one and other. 1 is written out
/// ("un giro", "una ripetizione") because a voice does not always agree the article with the noun after a
/// digit. A round is a "giro", the word a circuit uses, rather than the English "round", which an
/// Italian voice pronounces in its own way. Confirmations avoid words that change with the
/// athlete's gender ("pronto", "pronta"). Sentences end on a word, never on a number.
///
/// Counts other than 1 are left as digits for the engine to agree with the noun that follows.
///
/// Written without a native speaker's review; the lines are short so that they can be read that way.
public struct PhrasebookIt: Phrasebook {

    public init() {}

    public let tag = "it"

    public func say(_ line: VoiceLine) -> String {
        switch line {
        case .count(let reps): return "\(reps)"
        case .movement(let exercise):
            switch exercise {
            case .pullup: return "trazioni"
            case .pushup: return "flessioni"
            case .squat: return "squat"
            }
        case .roundDone(let round, let splitMs): return "Giro \(round) in \(duration(splitMs))"
        case .phoneMoved: return "Il telefono si è mosso. Controlla l'inquadratura."
        case .setUp: return "Mettiti nell'inquadratura, poi fai due trazioni lente"
        case .go(let calibrated): return calibrated ? "Calibrato. Via." : "Via. Trazioni"
        case .resume: return "Si riprende"
        case .finished(let early): return early ? "Fermato." : "Tempo."
        case .score(let rounds, let totalReps): return score(rounds, totalReps)
        case .averaging(let roundMs): return "In media \(duration(roundMs)) a giro"
        case .beatBenchmark(let name): return "Hai battuto \(name)"
        case .ready: return "Posizione ok"
        case .fault(let text): return Hint.of(text).map { hint($0) } ?? "Controlla la tua posizione"
        case .clock(let mark, let rounds, let totalReps, let projectedRounds):
            return clock(mark, rounds, totalReps, projectedRounds)
        case .sample: return "Tre. Quattro. Cinque. Flessioni."
        case .volumeCheck: return "Tre"
        case .recordingSoon(let n): return "Registrazione tra \(seconds(n))"
        case .recordingStarted: return "Registrazione in corso"
        case .recordingFailed: return "Registrazione non riuscita"
        case .adaptiveHeelsFlat: return "Cindy adattata attivata per gli squat con i talloni a terra."
        }
    }

    private func hint(_ hint: Hint) -> String {
        switch hint {
        case .stepIntoFrame: return "Entra nell'inquadratura"
        case .finishSetupFirst: return "Completa prima la preparazione"
        case .tracking: return "Ti sto cercando"
        case .hangFromBar: return "Appenditi alla sbarra"
        case .hangVertically: return "Appenditi alla sbarra in verticale"
        case .getOnBar: return "Afferra la sbarra"
        case .showBothHands: return "Mostra entrambe le mani"
        case .showYourHead: return "Mostra la testa"
        case .armsOutOfFrame: return "Le braccia sono fuori inquadratura"
        case .getHeadOverBar: return "Porta la testa sopra la sbarra"
        case .returnToDeadHang: return "Torna appeso a braccia tese"
        case .lowerAllTheWay: return "Scendi fino in fondo"
        case .getSetOnFloor: return "Mettiti in posizione a terra"
        case .getOnFloor: return "Mettiti a terra"
        case .standUpToStart: return "Alzati per iniziare"
        case .showYourLegs: return "Mostra le gambe alla fotocamera"
        case .driveUp: return "Spingi verso l'alto"
        case .goDown: return "Scendi"
        case .losingYou: return "Ti perdo di vista. Serve più luce."
        case .tooDark: return "Troppo buio per contare. Tocca il pulsante più uno."
        case .cantSeeYou: return "Non ti vedo. Tocca il pulsante più uno."
        }
    }

    private func clock(_ mark: ClockMark, _ rounds: Int, _ totalReps: Int, _ projected: Int?) -> String {
        switch mark {
        case .tenSecondsLeft: return "Dieci secondi. Dai tutto."
        case .oneMinuteLeft: return "Manca un minuto. Sei a \(roundsText(rounds)). Finisci quello in corso."
        case .twoMinutesLeft: return "Due minuti. " + push(rounds, totalReps)
        case .fiveMinutesLeft: return "Mancano cinque minuti. " + pace(rounds, projected)
        case .halfway: return "Metà tempo. " + pace(rounds, projected)
        case .fiveMinutesIn: return "Cinque minuti. " + pace(rounds, projected)
        }
    }

    private func pace(_ rounds: Int, _ projected: Int?) -> String {
        if let projected { return "Sei a \(roundsText(rounds)). Ritmo da \(roundsText(projected))." }
        return "Mantieni il tuo ritmo."
    }

    private func push(_ rounds: Int, _ totalReps: Int) -> String {
        score(rounds, totalReps) + (rounds < 1 ? ". Continua così." : ". Mantieni il ritmo.")
    }

    private func score(_ rounds: Int, _ totalReps: Int) -> String {
        (rounds < 1 ? reps(totalReps) : "\(roundsText(rounds)), \(reps(totalReps)) in totale").capitalised()
    }

    private func duration(_ ms: Int64) -> String {
        let (m, s) = minutesAndSeconds(ms)
        if m == 0 { return seconds(s) }
        if s == 0 { return minutes(m) }
        return "\(minutes(m)) e \(seconds(s))"
    }

    private func roundsText(_ n: Int) -> String { noun(n, "un giro", "giri") }
    private func reps(_ n: Int) -> String { noun(n, "una ripetizione", "ripetizioni") }
    private func minutes(_ n: Int) -> String { noun(n, "un minuto", "minuti") }
    private func seconds(_ n: Int) -> String { noun(n, "un secondo", "secondi") }

    private func noun(_ n: Int, _ one: String, _ other: String) -> String {
        Plurals.oneOther(n) == .one ? one : "\(n) \(other)"
    }
}
