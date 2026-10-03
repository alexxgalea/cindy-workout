import Foundation

/// The voice in Spanish.
///
/// Register: the informal "tú", in short imperatives, as a coach says them. Plurals: one and other.
/// A voice can read a bare "1 ronda" as "uno ronda", so 1 is written out ("una ronda", "un
/// minuto") and everything else is left as a digit. Sentences end on a word, never on a number,
/// because a digit before a full stop is read by some engines as an ordinal.
///
/// Counts other than 1 are left as digits for the engine to agree with the noun that follows.
///
/// Written without a native speaker's review; the lines are short so that they can be read that way.
public struct PhrasebookEs: Phrasebook {

    public init() {}

    public let tag = "es"

    public func say(_ line: VoiceLine) -> String {
        switch line {
        case .count(let reps): return "\(reps)"
        case .movement(let exercise):
            switch exercise {
            case .pullup: return "dominadas"
            case .pushup: return "flexiones"
            case .squat: return "sentadillas"
            }
        case .roundDone(let round, let splitMs): return "Ronda \(round) en \(duration(splitMs))"
        case .phoneMoved: return "El teléfono se movió. Revisa el encuadre."
        case .setUp: return "Colócate en el encuadre y haz dos dominadas lentas"
        case .go(let calibrated): return calibrated ? "Calibrado. Ya." : "Ya. Dominadas"
        case .resume: return "Seguimos"
        case .finished(let early): return early ? "Detenido." : "Tiempo."
        case .score(let rounds, let totalReps): return score(rounds, totalReps)
        case .averaging(let roundMs): return "De media, \(duration(roundMs)) por ronda"
        case .beatBenchmark(let name): return "Superaste a \(name)"
        case .ready: return "Todo listo"
        case .fault(let text): return Hint.of(text).map { hint($0) } ?? "Revisa tu posición"
        case .clock(let mark, let rounds, let totalReps, let projectedRounds):
            return clock(mark, rounds, totalReps, projectedRounds)
        case .sample: return "Tres. Cuatro. Cinco. Flexiones."
        case .volumeCheck: return "Tres"
        case .recordingSoon(let n): return "Grabando en \(seconds(n))"
        case .recordingStarted: return "Grabando"
        case .recordingFailed: return "Falló la grabación"
        case .adaptiveHeelsFlat: return "Cindy adaptada activada para sentadillas con los talones en el suelo."
        }
    }

    private func hint(_ hint: Hint) -> String {
        switch hint {
        case .stepIntoFrame: return "Entra en el encuadre"
        case .finishSetupFirst: return "Termina primero la preparación"
        case .tracking: return "Localizándote"
        case .hangFromBar: return "Cuélgate de la barra"
        case .hangVertically: return "Cuélgate de la barra en vertical"
        case .getOnBar: return "Agárrate a la barra"
        case .showBothHands: return "Muestra las dos manos"
        case .showYourHead: return "Muestra la cabeza"
        case .armsOutOfFrame: return "Tus brazos quedan fuera del encuadre"
        case .getHeadOverBar: return "Sube la cabeza por encima de la barra"
        case .returnToDeadHang: return "Vuelve a colgarte con los brazos estirados"
        case .lowerAllTheWay: return "Baja del todo"
        case .getSetOnFloor: return "Colócate en el suelo"
        case .getOnFloor: return "Ponte en el suelo"
        case .standUpToStart: return "Ponte de pie para empezar"
        case .showYourLegs: return "Muestra las piernas a la cámara"
        case .driveUp: return "Empuja hacia arriba"
        case .goDown: return "Baja"
        case .losingYou: return "Te pierdo de vista. Ayuda más luz."
        case .tooDark: return "Demasiado oscuro para contar. Pulsa el botón más uno."
        case .cantSeeYou: return "No te veo. Pulsa el botón más uno."
        }
    }

    private func clock(_ mark: ClockMark, _ rounds: Int, _ totalReps: Int, _ projected: Int?) -> String {
        switch mark {
        case .tenSecondsLeft: return "Diez segundos. Todo lo que tengas."
        case .oneMinuteLeft:
            return "Queda un minuto. Llevas \(roundsText(rounds)). Termina la que estás haciendo."
        case .twoMinutesLeft: return "Dos minutos. " + push(rounds, totalReps)
        case .fiveMinutesLeft: return "Quedan cinco minutos. " + pace(rounds, projected)
        case .halfway: return "A mitad de camino. " + pace(rounds, projected)
        case .fiveMinutesIn: return "Cinco minutos. " + pace(rounds, projected)
        }
    }

    private func pace(_ rounds: Int, _ projected: Int?) -> String {
        if let projected { return "Llevas \(roundsText(rounds)). Ritmo para \(roundsText(projected))." }
        return "Mantén tu ritmo."
    }

    private func push(_ rounds: Int, _ totalReps: Int) -> String {
        score(rounds, totalReps) + (rounds < 1 ? ". Sigue así." : ". Mantén el ritmo.")
    }

    private func score(_ rounds: Int, _ totalReps: Int) -> String {
        (rounds < 1 ? reps(totalReps) : "\(roundsText(rounds)), \(reps(totalReps)) en total").capitalised()
    }

    private func duration(_ ms: Int64) -> String {
        let (m, s) = minutesAndSeconds(ms)
        if m == 0 { return seconds(s) }
        if s == 0 { return minutes(m) }
        return "\(minutes(m)) y \(seconds(s))"
    }

    private func roundsText(_ n: Int) -> String { noun(n, "una ronda", "rondas") }
    private func reps(_ n: Int) -> String { noun(n, "una repetición", "repeticiones") }
    private func minutes(_ n: Int) -> String { noun(n, "un minuto", "minutos") }
    private func seconds(_ n: Int) -> String { noun(n, "un segundo", "segundos") }

    private func noun(_ n: Int, _ one: String, _ other: String) -> String {
        Plurals.oneOther(n) == .one ? one : "\(n) \(other)"
    }
}
