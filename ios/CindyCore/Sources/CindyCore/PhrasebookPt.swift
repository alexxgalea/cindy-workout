import Foundation

/// The voice in Brazilian Portuguese.
///
/// Register: "você", in short imperatives. Plurals: nought and one are both singular, as they are
/// in Brazilian Portuguese ("0 repetição"). 1 and 2 are written out for the feminine nouns ("uma
/// rodada", "duas rodadas"), because a voice can read a bare "2 rodadas" as "dois rodadas". The
/// minutes and seconds are masculine and need no help. Confirmations avoid words that change with
/// the athlete's gender ("pronto", "pronta"). Sentences end on a word, never on a number.
///
/// Counts that end in 1 or 2 beyond those written out (21, 22, 102 and so on) are left as digits
/// for the engine to agree. That is the known gap, and the one to listen for on a real voice.
///
/// Written without a native speaker's review; the lines are short so that they can be read that way.
public struct PhrasebookPt: Phrasebook {

    public init() {}

    public let tag = "pt"

    public func say(_ line: VoiceLine) -> String {
        switch line {
        case .count(let reps): return "\(reps)"
        case .movement(let exercise):
            switch exercise {
            case .pullup: return "barras"
            case .pushup: return "flexões"
            case .squat: return "agachamentos"
            }
        case .roundDone(let round, let splitMs): return "Rodada \(round) em \(duration(splitMs))"
        case .phoneMoved: return "O celular se mexeu. Confira o enquadramento."
        case .setUp: return "Entre no enquadramento e faça duas barras lentas"
        case .go(let calibrated): return calibrated ? "Calibrado. Vai." : "Vai. Barras"
        case .resume: return "Retomando"
        case .finished(let early): return early ? "Interrompido." : "Tempo."
        case .score(let rounds, let totalReps): return score(rounds, totalReps)
        case .averaging(let roundMs): return "Média de \(duration(roundMs)) por rodada"
        case .beatBenchmark(let name): return "Você superou \(name)"
        case .ready: return "Tudo certo"
        case .fault(let text): return Hint.of(text).map { hint($0) } ?? "Confira a sua posição"
        case .clock(let mark, let rounds, let totalReps, let projectedRounds):
            return clock(mark, rounds, totalReps, projectedRounds)
        case .sample: return "Três. Quatro. Cinco. Flexões."
        case .volumeCheck: return "Três"
        case .recordingSoon(let n): return "Gravando em \(seconds(n))"
        case .recordingStarted: return "Gravando"
        case .recordingFailed: return "Falha na gravação"
        case .adaptiveHeelsFlat: return "Cindy adaptada ativada para agachamentos com os calcanhares no chão."
        }
    }

    private func hint(_ hint: Hint) -> String {
        switch hint {
        case .stepIntoFrame: return "Entre no enquadramento"
        case .finishSetupFirst: return "Termine primeiro a preparação"
        case .tracking: return "Localizando você"
        case .hangFromBar: return "Pendure-se na barra"
        case .hangVertically: return "Pendure-se na barra na vertical"
        case .getOnBar: return "Segure a barra"
        case .showBothHands: return "Mostre as duas mãos"
        case .showYourHead: return "Mostre a cabeça"
        case .armsOutOfFrame: return "Seus braços estão fora do enquadramento"
        case .getHeadOverBar: return "Passe a cabeça acima da barra"
        case .returnToDeadHang: return "Volte a se pendurar com os braços esticados"
        case .lowerAllTheWay: return "Desça até o fim"
        case .getSetOnFloor: return "Posicione-se no chão"
        case .getOnFloor: return "Vá para o chão"
        case .standUpToStart: return "Fique de pé para começar"
        case .showYourLegs: return "Mostre as pernas para a câmera"
        case .driveUp: return "Empurre para cima"
        case .goDown: return "Desça"
        case .losingYou: return "Estou perdendo você de vista. Mais luz ajuda."
        case .tooDark: return "Escuro demais para contar. Toque no botão mais um."
        case .cantSeeYou: return "Não vejo você. Toque no botão mais um."
        }
    }

    private func clock(_ mark: ClockMark, _ rounds: Int, _ totalReps: Int, _ projected: Int?) -> String {
        switch mark {
        case .tenSecondsLeft: return "Dez segundos. Dê tudo o que tem."
        case .oneMinuteLeft: return "Falta um minuto. Você tem \(roundsText(rounds)). Termine a que está fazendo."
        case .twoMinutesLeft: return "Dois minutos. " + push(rounds, totalReps)
        case .fiveMinutesLeft: return "Faltam cinco minutos. " + pace(rounds, projected)
        case .halfway: return "Metade do tempo. " + pace(rounds, projected)
        case .fiveMinutesIn: return "Cinco minutos. " + pace(rounds, projected)
        }
    }

    private func pace(_ rounds: Int, _ projected: Int?) -> String {
        if let projected { return "Você tem \(roundsText(rounds)). Ritmo para \(roundsText(projected))." }
        return "Mantenha o seu ritmo."
    }

    private func push(_ rounds: Int, _ totalReps: Int) -> String {
        score(rounds, totalReps) + (rounds < 1 ? ". Continue." : ". Mantenha o ritmo.")
    }

    private func score(_ rounds: Int, _ totalReps: Int) -> String {
        (rounds < 1 ? reps(totalReps) : "\(roundsText(rounds)), \(reps(totalReps)) no total").capitalised()
    }

    private func duration(_ ms: Int64) -> String {
        let (m, s) = minutesAndSeconds(ms)
        if m == 0 { return seconds(s) }
        if s == 0 { return minutes(m) }
        return "\(minutes(m)) e \(seconds(s))"
    }

    private func roundsText(_ n: Int) -> String { feminine(n, "rodada", "rodadas") }
    private func reps(_ n: Int) -> String { feminine(n, "repetição", "repetições") }
    private func minutes(_ n: Int) -> String { masculine(n, "minuto", "minutos") }
    private func seconds(_ n: Int) -> String { masculine(n, "segundo", "segundos") }

    private func feminine(_ n: Int, _ singular: String, _ plural: String) -> String {
        if n == 1 { return "uma \(singular)" }
        if n == 2 { return "duas \(plural)" }
        if Plurals.zeroOrOne(n) == .one { return "\(n) \(singular)" }
        return "\(n) \(plural)"
    }

    private func masculine(_ n: Int, _ singular: String, _ plural: String) -> String {
        if n == 1 { return "um \(singular)" }
        if Plurals.zeroOrOne(n) == .one { return "\(n) \(singular)" }
        return "\(n) \(plural)"
    }
}
