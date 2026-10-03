import Foundation

/// The voice in French.
///
/// Register: the informal "tu", in short imperatives. Plurals: nought and one are both singular
/// ("0 tour", "1 tour"), which is French and not a slip. 1 is written out ("un tour", "une
/// répétition") because a voice does not always agree the article with the noun that follows a
/// digit. Sentences end on a word, never on a number, because a digit before a full stop is read by
/// some engines as an ordinal.
///
/// Counts other than 1 are left as digits for the engine to agree with the noun that follows.
///
/// Written without a native speaker's review; the lines are short so that they can be read that way.
public struct PhrasebookFr: Phrasebook {

    public init() {}

    public let tag = "fr"

    public func say(_ line: VoiceLine) -> String {
        switch line {
        case .count(let reps): return "\(reps)"
        case .movement(let exercise):
            switch exercise {
            case .pullup: return "tractions"
            case .pushup: return "pompes"
            case .squat: return "squats"
            }
        case .roundDone(let round, let splitMs): return "Tour \(round) en \(duration(splitMs))"
        case .phoneMoved: return "Le téléphone a bougé. Vérifie le cadrage."
        case .setUp: return "Place-toi dans le cadre, puis fais deux tractions lentes"
        case .go(let calibrated): return calibrated ? "Calibré. C'est parti." : "C'est parti. Tractions"
        case .resume: return "On reprend"
        case .finished(let early): return early ? "Arrêté." : "Temps."
        case .score(let rounds, let totalReps): return score(rounds, totalReps)
        case .averaging(let roundMs): return "En moyenne, \(duration(roundMs)) par tour"
        case .beatBenchmark(let name): return "Tu as battu \(name)"
        case .ready: return "C'est bon"
        case .fault(let text): return Hint.of(text).map { hint($0) } ?? "Vérifie ta position"
        case .clock(let mark, let rounds, let totalReps, let projectedRounds):
            return clock(mark, rounds, totalReps, projectedRounds)
        case .sample: return "Trois. Quatre. Cinq. Pompes."
        case .volumeCheck: return "Trois"
        case .recordingSoon(let n): return "Enregistrement dans \(seconds(n))"
        case .recordingStarted: return "Enregistrement en cours"
        case .recordingFailed: return "L'enregistrement a échoué"
        case .adaptiveHeelsFlat: return "Cindy adaptée activée pour les squats talons au sol."
        }
    }

    private func hint(_ hint: Hint) -> String {
        switch hint {
        case .stepIntoFrame: return "Place-toi dans le cadre"
        case .finishSetupFirst: return "Termine d'abord la préparation"
        case .tracking: return "Recherche en cours"
        case .hangFromBar: return "Suspends-toi à la barre"
        case .hangVertically: return "Suspends-toi à la barre, à la verticale"
        case .getOnBar: return "Attrape la barre"
        case .showBothHands: return "Montre les deux mains"
        case .showYourHead: return "Montre ta tête"
        case .armsOutOfFrame: return "Tes bras sortent du cadre"
        case .getHeadOverBar: return "Passe la tête au-dessus de la barre"
        case .returnToDeadHang: return "Reviens en suspension, bras tendus"
        case .lowerAllTheWay: return "Descends complètement"
        case .getSetOnFloor: return "Mets-toi en position au sol"
        case .getOnFloor: return "Mets-toi au sol"
        case .standUpToStart: return "Lève-toi pour commencer"
        case .showYourLegs: return "Montre tes jambes à la caméra"
        case .driveUp: return "Pousse vers le haut"
        case .goDown: return "Descends"
        case .losingYou: return "Je te perds de vue. Plus de lumière aiderait."
        case .tooDark: return "Trop sombre pour compter. Touche le bouton plus un."
        case .cantSeeYou: return "Je ne te vois pas. Touche le bouton plus un."
        }
    }

    private func clock(_ mark: ClockMark, _ rounds: Int, _ totalReps: Int, _ projected: Int?) -> String {
        switch mark {
        case .tenSecondsLeft: return "Dix secondes. Donne tout."
        case .oneMinuteLeft:
            return "Il reste une minute. Tu en es à \(roundsText(rounds)). Termine celui en cours."
        case .twoMinutesLeft: return "Deux minutes. " + push(rounds, totalReps)
        case .fiveMinutesLeft: return "Il reste cinq minutes. " + pace(rounds, projected)
        case .halfway: return "À mi-parcours. " + pace(rounds, projected)
        case .fiveMinutesIn: return "Cinq minutes. " + pace(rounds, projected)
        }
    }

    private func pace(_ rounds: Int, _ projected: Int?) -> String {
        if let projected { return "Tu en es à \(roundsText(rounds)). Rythme pour \(roundsText(projected))." }
        return "Garde ton rythme."
    }

    private func push(_ rounds: Int, _ totalReps: Int) -> String {
        score(rounds, totalReps) + (rounds < 1 ? ". Continue." : ". Garde le rythme.")
    }

    private func score(_ rounds: Int, _ totalReps: Int) -> String {
        (rounds < 1 ? reps(totalReps) : "\(roundsText(rounds)), \(reps(totalReps)) au total").capitalised()
    }

    private func duration(_ ms: Int64) -> String {
        let (m, s) = minutesAndSeconds(ms)
        if m == 0 { return seconds(s) }
        if s == 0 { return minutes(m) }
        return "\(minutes(m)) et \(seconds(s))"
    }

    private func roundsText(_ n: Int) -> String { noun(n, "un tour", "tour", "tours") }
    private func reps(_ n: Int) -> String { noun(n, "une répétition", "répétition", "répétitions") }
    private func minutes(_ n: Int) -> String { noun(n, "une minute", "minute", "minutes") }
    private func seconds(_ n: Int) -> String { noun(n, "une seconde", "seconde", "secondes") }

    private func noun(_ n: Int, _ one: String, _ singular: String, _ plural: String) -> String {
        if n == 1 { return one }
        if Plurals.zeroOrOne(n) == .one { return "\(n) \(singular)" }
        return "\(n) \(plural)"
    }
}
