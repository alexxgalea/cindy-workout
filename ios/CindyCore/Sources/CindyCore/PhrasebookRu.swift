import Foundation

/// The voice in Russian.
///
/// Register: the informal "ты", in short imperatives. Plurals: one, few and many (1 раунд, 2–4
/// раунда, 5 раундов, but 11 раундов and 21 раунд). 1 and 2 are written out for the feminine nouns
/// ("одна минута", "две минуты") and 1 for the neuter "одно повторение", because a voice does not
/// reliably agree the numeral's gender with the noun after a digit. Confirmations and results
/// avoid the past tense of the athlete ("побил" or "побила"): the benchmark line says the result is
/// better, which is true whoever is listening. Sentences end on a word, never on a number.
///
/// Counts that end in 1 or 2 beyond those written out (21, 22, 102 and so on) are left as digits
/// for the engine to agree. That is the known gap, and the one to listen for on a real voice.
///
/// Written without a native speaker's review; the lines are short so that they can be read that way.
public struct PhrasebookRu: Phrasebook {

    public init() {}

    public let tag = "ru"

    public func say(_ line: VoiceLine) -> String {
        switch line {
        case .count(let reps): return "\(reps)"
        case .movement(let exercise):
            switch exercise {
            case .pullup: return "подтягивания"
            case .pushup: return "отжимания"
            case .squat: return "приседания"
            }
        case .roundDone(let round, let splitMs): return "Раунд \(round), время \(duration(splitMs))"
        case .phoneMoved: return "Телефон сдвинулся. Проверь кадр."
        case .setUp: return "Встань в кадр и сделай два медленных подтягивания"
        case .go(let calibrated): return calibrated ? "Калибровка завершена. Старт." : "Старт. Подтягивания"
        case .resume: return "Продолжаем"
        case .finished(let early): return early ? "Остановлено." : "Время."
        case .score(let rounds, let totalReps): return score(rounds, totalReps)
        case .averaging(let roundMs): return "В среднем \(duration(roundMs)) на раунд"
        case .beatBenchmark(let name): return "Результат лучше, чем у \(name)"
        case .ready: return "Готово"
        case .fault(let text): return Hint.of(text).map { hint($0) } ?? "Проверь своё положение"
        case .clock(let mark, let rounds, let totalReps, let projectedRounds):
            return clock(mark, rounds, totalReps, projectedRounds)
        case .sample: return "Три. Четыре. Пять. Отжимания."
        case .volumeCheck: return "Три"
        case .recordingSoon(let n): return "Запись через \(secondsAfterCherez(n))"
        case .recordingStarted: return "Идёт запись"
        case .recordingFailed: return "Запись не удалась"
        case .adaptiveHeelsFlat: return "Адаптивная Cindy включена для приседаний с пятками на полу."
        }
    }

    private func hint(_ hint: Hint) -> String {
        switch hint {
        case .stepIntoFrame: return "Встань в кадр"
        case .finishSetupFirst: return "Сначала закончи подготовку"
        case .tracking: return "Ищу тебя"
        case .hangFromBar: return "Повисни на перекладине"
        case .hangVertically: return "Повисни на перекладине вертикально"
        case .getOnBar: return "Возьмись за перекладину"
        case .showBothHands: return "Покажи обе руки"
        case .showYourHead: return "Покажи голову"
        case .armsOutOfFrame: return "Руки вышли из кадра"
        case .getHeadOverBar: return "Подними голову выше перекладины"
        case .returnToDeadHang: return "Вернись в вис на прямых руках"
        case .lowerAllTheWay: return "Опустись до конца"
        case .getSetOnFloor: return "Прими положение на полу"
        case .getOnFloor: return "Ляг на пол"
        case .standUpToStart: return "Встань, чтобы начать"
        case .showYourLegs: return "Покажи ноги камере"
        case .driveUp: return "Вытолкни себя вверх"
        case .goDown: return "Опустись"
        case .losingYou: return "Теряю тебя из виду. Больше света поможет."
        case .tooDark: return "Слишком темно для счёта. Нажми кнопку плюс один."
        case .cantSeeYou: return "Не вижу тебя. Нажми кнопку плюс один."
        }
    }

    private func clock(_ mark: ClockMark, _ rounds: Int, _ totalReps: Int, _ projected: Int?) -> String {
        switch mark {
        case .tenSecondsLeft: return "Десять секунд. Выложись полностью."
        case .oneMinuteLeft: return "Осталась минута. Раундов: \(rounds), закончи текущий."
        case .twoMinutesLeft: return "Две минуты. " + push(rounds, totalReps)
        case .fiveMinutesLeft: return "Осталось пять минут. " + pace(rounds, projected)
        case .halfway: return "Половина времени. " + pace(rounds, projected)
        case .fiveMinutesIn: return "Прошло пять минут. " + pace(rounds, projected)
        }
    }

    private func pace(_ rounds: Int, _ projected: Int?) -> String {
        if let projected { return "Раундов: \(rounds), темп на \(roundsText(projected))." }
        return "Держи свой темп."
    }

    private func push(_ rounds: Int, _ totalReps: Int) -> String {
        score(rounds, totalReps) + (rounds < 1 ? ". Продолжай." : ". Держи темп.")
    }

    private func score(_ rounds: Int, _ totalReps: Int) -> String {
        (rounds < 1 ? reps(totalReps) : "\(roundsText(rounds)), всего \(reps(totalReps))").capitalised()
    }

    private func duration(_ ms: Int64) -> String {
        let (m, s) = minutesAndSeconds(ms)
        if m == 0 { return seconds(s) }
        if s == 0 { return minutes(m) }
        return "\(minutes(m)) и \(seconds(s))"
    }

    private func roundsText(_ n: Int) -> String {
        switch Plurals.russian(n) {
        case .one: return "\(n) раунд"
        case .few: return "\(n) раунда"
        default: return "\(n) раундов"
        }
    }

    private func reps(_ n: Int) -> String {
        switch Plurals.russian(n) {
        case .one: return n == 1 ? "одно повторение" : "\(n) повторение"
        case .few: return "\(n) повторения"
        default: return "\(n) повторений"
        }
    }

    private func minutes(_ n: Int) -> String {
        switch Plurals.russian(n) {
        case .one: return n == 1 ? "одна минута" : "\(n) минута"
        case .few: return n == 2 ? "две минуты" : "\(n) минуты"
        default: return "\(n) минут"
        }
    }

    private func seconds(_ n: Int) -> String {
        switch Plurals.russian(n) {
        case .one: return n == 1 ? "одна секунда" : "\(n) секунда"
        case .few: return n == 2 ? "две секунды" : "\(n) секунды"
        default: return "\(n) секунд"
        }
    }

    /// After "через" the feminine singular is accusative: "через одну секунду".
    private func secondsAfterCherez(_ n: Int) -> String {
        if n == 1 { return "одну секунду" }
        if Plurals.russian(n) == .one { return "\(n) секунду" }
        return seconds(n)
    }
}
