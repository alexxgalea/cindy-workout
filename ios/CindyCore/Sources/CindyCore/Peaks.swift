import Foundation

/// One trophy. `rank` 1 to 3 picks the medal.
public struct Peak: Equatable, Sendable {
    public let title: String
    public let value: String
    public let detail: String
    public let rank: Int

    public init(title: String, value: String, detail: String, rank: Int) {
        self.title = title
        self.value = value
        self.detail = detail
        self.rank = rank
    }
}

/// The personal-best board, built only from what is already recorded.
///
/// Pure: no clock, no zone of its own. Scores, rounds and paces are compared within one category
/// and never from a lower-bound attempt, which only says "at least". Streaks and weekly volume are
/// work done rather than a comparison, so they look at every attempt. Port of `Peaks.kt`.
public enum Peaks {

    /// Every trophy, in display order. Empty when there are no attempts.
    public static func of(_ attempts: [Attempt], category: CindyProfile?, today: LocalDate, zone: Zone,
                          firstDayOfWeek: DayOfWeek) -> [Peak] {
        var out: [Peak] = []
        let clean = attempts.filter { $0.profile == category && !$0.scoreIsLowerBound }
        func date(_ a: Attempt) -> String { DateText.long(Progress.localDate(a, zone: zone)) }

        let titles = ["Best score", "2nd best", "3rd best"]
        for (i, a) in Records.ranked(clean).prefix(3).enumerated() {
            out.append(Peak(title: titles[i], value: a.scoreLabel,
                            detail: "\(date(a)) · \(Progress.formatReps(a.totalReps)) reps", rank: i + 1))
        }

        // Newest first, so a tie keeps the more recent attempt.
        let newestFirst = JavaText.sortedStably(clean, by: { $0.atMillis }, descending: true)
        var fastest: (attempt: Attempt, index: Int)?
        for a in newestFirst {
            guard let ms = a.fastestRoundMs else { continue }
            let best = fastest.map { $0.attempt.roundSplitsMs[$0.index] }
            if best == nil || ms < best! { fastest = (a, a.roundSplitsMs.firstIndex(of: ms)!) }
        }
        if let (a, index) = fastest {
            out.append(Peak(title: "Fastest round", value: formatDuration(a.roundSplitsMs[index]),
                            detail: "\(date(a)) · round \(index + 1)", rank: 1))
        }

        var bestAverage: Attempt?
        for a in newestFirst where Progress.isFullSession(a) && a.avgRoundMs != nil {
            // `minByOrNull` keeps the first of equals.
            if bestAverage == nil || a.avgRoundMs! < bestAverage!.avgRoundMs! { bestAverage = a }
        }
        if let a = bestAverage {
            out.append(Peak(title: "Best average round", value: formatDuration(a.avgRoundMs!),
                            detail: "\(date(a)) · \(a.rounds) rounds", rank: 1))
        }

        // The fastest set of each movement, only where the camera saw every rep: a tapped or skipped
        // set is not a time the app can stand behind. There is no set peak without a category,
        // because the title names the movement being timed.
        if let category {
            for movement in Exercise.allCases {
                let plural: String
                switch movement {
                case .pullup: plural = category.pull.plural
                case .pushup: plural = category.push.plural
                case .squat: plural = category.squat.plural
                }
                // Newest first and a strict comparison, so a tie keeps the more recent set.
                var best: (attempt: Attempt, ms: Int64)?
                for a in newestFirst {
                    let times = a.setSplits.filter { $0.movement == movement && $0.measured }.map { $0.ms }
                    guard let ms = times.min() else { continue }
                    if best == nil || ms < best!.ms { best = (a, ms) }
                }
                if let (a, ms) = best {
                    out.append(Peak(title: "Fastest \(movement.target) \(plural)", value: formatDuration(ms),
                                    detail: date(a), rank: 1))
                }
            }
        }

        let days = Streak.daysTrained(attempts, zone: zone)
        if let run = Streak.longestRun(days) {
            let length = run.upperBound.epochDay - run.lowerBound.epochDay + 1
            if length >= 2 {
                let running = run.upperBound == today || run.upperBound == today.minusDays(1)
                out.append(Peak(title: "Longest daily streak", value: "\(length) days",
                                detail: running ? "Running now" : "Ended \(DateText.long(run.upperBound))", rank: 1))
            }
        }

        let weeks = Streak.weeksTrained(days, firstDayOfWeek: firstDayOfWeek)
        if let run = Streak.longestWeeksRun(weeks) {
            let length = (run.upperBound.epochDay - run.lowerBound.epochDay) / 7 + 1
            if length >= 2 {
                let thisWeek = Streak.weekStart(today, firstDayOfWeek: firstDayOfWeek)
                let running = run.upperBound == thisWeek || run.upperBound == thisWeek.minusWeeks(1)
                out.append(Peak(title: "Longest weekly streak", value: "\(length) weeks",
                                detail: running ? "Running now" : "Ended week of \(DateText.long(run.upperBound))", rank: 1))
            }
        }

        var byWeek: [LocalDate: [Attempt]] = [:]
        for a in attempts {
            byWeek[Streak.weekStart(Progress.localDate(a, zone: zone), firstDayOfWeek: firstDayOfWeek), default: []].append(a)
        }
        // Newest week first, so a tie keeps the more recent week.
        let weekList = byWeek.sorted { $0.key > $1.key }
        var biggest: (week: LocalDate, list: [Attempt])?
        for (week, list) in weekList where biggest == nil || list.count > biggest!.list.count { biggest = (week, list) }
        if let (week, list) = biggest, list.count >= 2 {
            out.append(Peak(title: "Biggest week", value: "\(list.count) sessions",
                            detail: "Week of \(DateText.long(week))", rank: 1))
        }
        if weekList.count >= 2 {
            var most: (week: LocalDate, list: [Attempt])?
            for (week, list) in weekList
            where most == nil || list.reduce(0, { $0 + $1.totalReps }) > most!.list.reduce(0, { $0 + $1.totalReps }) {
                most = (week, list)
            }
            if let (week, list) = most {
                out.append(Peak(title: "Most reps in a week",
                                value: "\(Progress.formatReps(list.reduce(0) { $0 + $1.totalReps })) reps",
                                detail: "Week of \(DateText.long(week))", rank: 1))
            }
        }
        return out
    }
}
