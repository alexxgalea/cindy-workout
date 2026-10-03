import Foundation

/// The voice in Romanian.
///
/// Register: the informal "tu", in short imperatives. Plurals: one, few and other. "Few" covers 0
/// and 2–19 (and 101–119), and from 20 the noun takes "de": "2 runde" but "20 de runde" and
/// "120 de runde". 1 and 2 are written out ("o rundă", "două runde") because a voice does not
/// always agree the numeral's gender with the noun after a digit. The duration follows "timp de" rather
/// than "în", since "în un minut" contracts to "într-un minut". Sentences end on a word, never on
/// a number: Romanian engines read "12." as an ordinal.
///
/// Counts that end in 1 or 2 beyond those written out (21, 22, 102 and so on) are left as digits
/// for the engine to agree. That is the known gap, and the one to listen for on a real voice.
///
/// Written without a native speaker's review; the lines are short so that they can be read that way.
public struct PhrasebookRo: Phrasebook {

    public init() {}

    public let tag = "ro"

    public func say(_ line: VoiceLine) -> String {
        switch line {
        case .count(let reps): return "\(reps)"
        case .movement(let exercise):
            switch exercise {
            case .pullup: return "tracțiuni"
            case .pushup: return "flotări"
            case .squat: return "genuflexiuni"
            }
        case .roundDone(let round, let splitMs): return "Runda \(round), timp de \(duration(splitMs))"
        case .phoneMoved: return "Telefonul s-a mișcat. Verifică cadrul."
        case .setUp: return "Intră în cadru, apoi fă două tracțiuni lente"
        case .go(let calibrated): return calibrated ? "Calibrat. Start." : "Start. Tracțiuni"
        case .resume: return "Reluăm"
        case .finished(let early): return early ? "Oprit." : "Timpul a expirat."
        case .score(let rounds, let totalReps): return score(rounds, totalReps)
        case .averaging(let roundMs): return "În medie \(duration(roundMs)) pe rundă"
        case .beatBenchmark(let name): return "Scor mai bun decât \(name)"
        case .ready: return "Gata"
        case .fault(let text): return Hint.of(text).map { hint($0) } ?? "Verifică-ți poziția"
        case .clock(let mark, let rounds, let totalReps, let projectedRounds):
            return clock(mark, rounds, totalReps, projectedRounds)
        case .sample: return "Trei. Patru. Cinci. Flotări."
        case .volumeCheck: return "Trei"
        case .recordingSoon(let n): return recordingSoon(n)
        case .recordingStarted: return "Se înregistrează"
        case .recordingFailed: return "Înregistrarea a eșuat"
        case .adaptiveHeelsFlat: return "Cindy adaptată activată pentru genuflexiuni cu călcâiele pe podea."
        }
    }

    private func hint(_ hint: Hint) -> String {
        switch hint {
        case .stepIntoFrame: return "Intră în cadru"
        case .finishSetupFirst: return "Termină mai întâi pregătirea"
        case .tracking: return "Te caut"
        case .hangFromBar: return "Agață-te de bară"
        case .hangVertically: return "Agață-te de bară, pe verticală"
        case .getOnBar: return "Prinde bara"
        case .showBothHands: return "Arată ambele mâini"
        case .showYourHead: return "Arată-ți capul"
        case .armsOutOfFrame: return "Brațele ies din cadru"
        case .getHeadOverBar: return "Ridică capul deasupra barei"
        case .returnToDeadHang: return "Revino în atârnare, cu brațele întinse"
        case .lowerAllTheWay: return "Coboară complet"
        case .getSetOnFloor: return "Ia poziția pe podea"
        case .getOnFloor: return "Așază-te pe podea"
        case .standUpToStart: return "Ridică-te ca să începi"
        case .showYourLegs: return "Arată-ți picioarele camerei"
        case .driveUp: return "Împinge în sus"
        case .goDown: return "Coboară"
        case .losingYou: return "Te pierd din vedere. Mai multă lumină ajută."
        case .tooDark: return "Prea întuneric ca să număr. Atinge butonul plus unu."
        case .cantSeeYou: return "Nu te văd. Atinge butonul plus unu."
        }
    }

    private func clock(_ mark: ClockMark, _ rounds: Int, _ totalReps: Int, _ projected: Int?) -> String {
        switch mark {
        case .tenSecondsLeft: return "Zece secunde. Dă tot ce ai."
        case .oneMinuteLeft: return "Mai e un minut. Ai \(roundsText(rounds)). Termină runda în curs."
        case .twoMinutesLeft: return "Două minute. " + push(rounds, totalReps)
        case .fiveMinutesLeft: return "Mai sunt cinci minute. " + pace(rounds, projected)
        case .halfway: return "La jumătate. " + pace(rounds, projected)
        case .fiveMinutesIn: return "Cinci minute. " + pace(rounds, projected)
        }
    }

    private func pace(_ rounds: Int, _ projected: Int?) -> String {
        if let projected { return "Ai \(roundsText(rounds)). Ritm pentru \(roundsText(projected))." }
        return "Ține-ți ritmul."
    }

    private func push(_ rounds: Int, _ totalReps: Int) -> String {
        score(rounds, totalReps) + (rounds < 1 ? ". Continuă." : ". Ține ritmul.")
    }

    private func score(_ rounds: Int, _ totalReps: Int) -> String {
        (rounds < 1 ? reps(totalReps) : "\(roundsText(rounds)), \(reps(totalReps)) în total").capitalised()
    }

    private func duration(_ ms: Int64) -> String {
        let (m, s) = minutesAndSeconds(ms)
        if m == 0 { return seconds(s) }
        if s == 0 { return minutes(m) }
        return "\(minutes(m)) și \(seconds(s))"
    }

    private func recordingSoon(_ n: Int) -> String {
        n == 1 ? "Înregistrare într-o secundă" : "Înregistrare în \(seconds(n))"
    }

    private func roundsText(_ n: Int) -> String { noun(n, "o rundă", "două runde", "runde") }
    private func reps(_ n: Int) -> String { noun(n, "o repetare", "două repetări", "repetări") }
    private func minutes(_ n: Int) -> String { noun(n, "un minut", "două minute", "minute") }
    private func seconds(_ n: Int) -> String { noun(n, "o secundă", "două secunde", "secunde") }

    private func noun(_ n: Int, _ one: String, _ two: String, _ plural: String) -> String {
        if n == 1 { return one }
        if n == 2 { return two }
        if Plurals.romanian(n) == .few { return "\(n) \(plural)" }
        return "\(n) de \(plural)"
    }
}
