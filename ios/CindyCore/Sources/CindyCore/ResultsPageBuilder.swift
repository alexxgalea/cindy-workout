import Foundation

/// The results page, decided: which cards show, and what each says. Port of `ResultsActivity`'s
/// `render`; the screen draws what this returns and decides nothing of its own.
///
/// Rounds are the score; loose reps are a footnote on it. A part the record cannot give is hidden
/// rather than drawn empty: the tiles always have something to say from the attempt's own totals,
/// but the round track and the movement card need the sets, which an older record never filed.
public struct ResultsPage {
    /// "TIME", "STOPPED", or the date and time of a session reopened from Progress.
    public let headline: String
    public let score: String
    public let scoreReps: String?
    public let scoreDetail: String
    public let celebration: CelebrationBox?
    public let tiles: [StatTile]
    public let track: TrackSection?
    public let movements: MovementsSection?
    public let level: LevelPanel
    public let lifted: LiftedSection
    public let compare: CompareSection?
    public let stats: [StatRow]
    public let splits: SplitsSection?
    public let timeline: TimelineSection?
    public let heart: HeartCard?
    /// What this session is measured against, if anything.
    public let comparison: Attempt?
    public let comparisonKind: Comparisons.Kind?
    /// A reopened session offers only DONE; a live one offers PROGRESS as well.
    public let offersProgress: Bool
}

public enum ResultsPageBuilder {

    public static let maxBadgeRows = 3
    public static let trackHint = "Tap a round to see what went into it."
    public static let timelineHint = "Drag across the chart to scrub through the session."

    public static func build(_ input: ResultsInput) -> ResultsPage {
        let a = input.attempt
        // Sessions this one could honestly be measured against: in review, only what had already
        // happened, so reopening an old session cannot be credited with a celebration, a record or
        // a comparison that later sessions, not this one, actually earned.
        let all = input.records.filter { $0.atMillis <= a.atMillis }
        let stats = SessionStats.from(a)
        let options = Comparisons.options(all, of: a)
        let chosen = options.first { $0.attempt.atMillis == input.comparisonAtMillis } ?? options.first
        let comparison = chosen?.attempt
        let kind = chosen?.kind

        return ResultsPage(
            headline: headline(input),
            score: String(a.rounds),
            scoreReps: a.reps > 0 ? "+\(a.reps)" : nil,
            scoreDetail: scoreDetail(a),
            celebration: celebration(input, all),
            tiles: SessionTiles.of(a, stats),
            track: track(a, stats),
            movements: movements(a, stats),
            level: level(a),
            lifted: lifted(input),
            compare: chosen.map { compare(a, options, $0, input.zone) },
            stats: statRows(input, all),
            splits: splits(a, comparison, kind),
            timeline: timeline(input, comparison, kind),
            heart: heart(input),
            comparison: comparison,
            comparisonKind: kind,
            offersProgress: !input.reviewing)
    }

    // MARK: the top

    static func headline(_ input: ResultsInput) -> String {
        if input.reviewing { return reviewHeadline(input.attempt, input.zone, input.is24Hour) }
        return input.stoppedEarly ? "STOPPED" : "TIME"
    }

    private static let weekdays = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]

    /// "TUE 29 SEP 2026 · 18:04", honouring the phone's 12/24-hour setting.
    static func reviewHeadline(_ a: Attempt, _ zone: Zone, _ is24Hour: Bool) -> String {
        let date = zone.localDate(epochMs: a.atMillis)
        let day = weekdays[date.dayOfWeek.rawValue - 1]
        let text = "\(day) \(date.day) \(DateText.months[date.month - 1].uppercased()) \(date.year)"
        let minutes = zone.minuteOfDay(epochMs: a.atMillis)
        let h = minutes / 60, m = minutes % 60
        let time: String
        if is24Hour {
            time = String(format: "%02d:%02d", h, m)
        } else {
            time = "\(h % 12 == 0 ? 12 : h % 12):\(String(format: "%02d", m)) \(h < 12 ? "AM" : "PM")"
        }
        return "\(text) · \(time)"
    }

    static func scoreDetail(_ a: Attempt) -> String {
        var s = "\(a.totalReps) reps in \(formatDuration(a.durationMs)) of clock"
        if a.pausedMs > 0 { s += " · \(formatDuration(a.realTimeMs)) real" }
        if Records.beatsBenchmark(a) { s += "  ·  past \(Records.benchmarkName)" }
        return s
    }

    // MARK: celebration

    static func celebration(_ input: ResultsInput, _ all: [Attempt]) -> CelebrationBox? {
        let a = input.attempt
        let lines = Cheer.forResult(all, a, zone: input.zone, firstDayOfWeek: input.firstDayOfWeek)
        // Latest in the catalogue first. Within a family that is the hardest one earned, and the
        // badges of a first session sink to the bottom, where the line above already says so.
        let badges = Badges.earnedBy(all, a, zone: input.zone, firstDayOfWeek: input.firstDayOfWeek)
            .sorted { $0.ordinal > $1.ordinal }
        if lines.isEmpty && badges.isEmpty { return nil }

        var rows: [CelebrationBox.Row] = []
        for line in lines {
            let trophy = line.kind == .first || line.kind == .record
            rows.append(.init(icon: trophy ? .trophy : .flame, text: line.text, headline: rows.isEmpty))
        }
        for badge in badges.prefix(maxBadgeRows) {
            rows.append(.init(icon: .badge(badge), text: "New badge: \(badge.title)", headline: rows.isEmpty))
        }
        let more = badges.count > maxBadgeRows ? "+\(badges.count - maxBadgeRows) more in your profile" : nil
        return CelebrationBox(rows: rows, more: more)
    }

    // MARK: level

    static func level(_ a: Attempt) -> LevelPanel {
        if let level = a.level {
            let next = Level.roundsToNext(a.rounds).map { need in
                "\(need) more round\(need == 1 ? "" : "s") to \(Level.next(after: level)?.title ?? "nil")"
            } ?? "Top of the ladder."
            return LevelPanel(title: level.title, rung: "\(level.rawValue + 1) of \(Level.allCases.count)",
                              blurb: level.blurb, progressPercent: Int(Level.progress(a.rounds) * 100), next: next)
        }
        let profile = a.profile
        let changed = profile?.changedMovements() ?? ""
        return LevelPanel(
            title: profile?.mode.label ?? "Adaptive Cindy", rung: nil,
            blurb: changed.isEmpty ? "Movements this version does not recognise." : changed,
            // No rung, so no bar to fill: an empty progress bar would read as "no progress".
            progressPercent: nil,
            next: "Ranked against your own sessions at these movements, not the strict ladder.")
    }

    // MARK: round track and movements

    static func track(_ a: Attempt, _ stats: SessionStats?) -> TrackSection? {
        guard let rounds = stats?.rounds, !rounds.isEmpty else { return nil }
        let plurals = SessionStats.plurals(a.profile)
        let scheme = Exercise.allCases.map { "\($0.target) \(plurals[$0])" }.joined(separator: ", ")
        // Said once, in the session's own words, so the three segments of a pill can be read: knee
        // push-ups are not "push-ups", and the order is the order they are done.
        var footnote = "A round is \(scheme), in that order, left to right. What was not done stays hollow."
        if a.scoreIsLowerBound {
            footnote += " The camera lost you for \(formatDuration(a.untrackedMs)), so rounds may hold more than shown."
        }
        return TrackSection(rounds: rounds, plurals: plurals, atLeast: a.scoreIsLowerBound,
                            hint: trackHint, footnote: footnote)
    }

    /// Past this many characters a label no longer fits one line in a third of a phone.
    static let longLabel = 10

    static func movements(_ a: Attempt, _ stats: SessionStats?) -> MovementsSection? {
        guard let movements = stats?.movements, !movements.isEmpty else { return nil }
        let atLeast = a.scoreIsLowerBound
        let columns = movements.map { m -> MovementColumn in
            var lines: [String] = []
            if let t = m.timeMs { lines.append("\(formatDuration(t)) total") }
            if let t = m.averageCompleteSetMs { lines.append("\(formatDuration(t)) a set") }
            if let share = m.shareOfClock { lines.append("\(JavaText.roundToInt(share * 100))% of set time") }
            if let tapped = m.tappedReps, tapped > 0 { lines.append("\(tapped) tapped") }
            var spoken = "\(m.label): \(atLeast ? "at least " : "")\(m.reps) reps"
            for line in lines { spoken += ", \(line)" }
            return MovementColumn(movement: m.movement, label: m.label, reps: m.reps, atLeast: atLeast,
                                  lines: lines, spoken: spoken)
        }
        return MovementsSection(
            columns: columns, tall: movements.contains { $0.label.utf16.count > longLabel },
            footnote: "Times cover finished sets and include getting into position. The average is of "
                + "the sets that reached their target.")
    }

    // MARK: stat rows

    static func statRows(_ input: ResultsInput, _ all: [Attempt]) -> [StatRow] {
        let a = input.attempt
        var rows: [StatRow] = []
        if a.pausedMs > 0 {
            // The clock stops when you pause; the day does not.
            rows.append(StatRow("Paused", formatDuration(a.pausedMs)))
            rows.append(StatRow("Real time", formatDuration(a.realTimeMs)))
        }
        // Said beside the score it explains. The athlete did not choose this label, and a record
        // that reads "Adaptive Cindy" with no word about why would look like a fault.
        if input.heelsFlatSpotted {
            rows.append(StatRow("Squats", "Heels flat · Adaptive Cindy", action: .explainHeelsFlat))
        }
        // A streak describes today, which a session reopened from another day is not.
        if !input.reviewing {
            let days = Streak.daysTrained(all, zone: input.zone)
            let streakDays = Streak.current(days, today: input.today)
            let streakWeeks = Streak.currentWeeks(Streak.weeksTrained(days, firstDayOfWeek: input.firstDayOfWeek),
                                                  today: input.today, firstDayOfWeek: input.firstDayOfWeek)
            rows.append(StatRow("Streak", "\(streakDays) day\(streakDays == 1 ? "" : "s") · "
                                + "\(streakWeeks) week\(streakWeeks == 1 ? "" : "s")"))
        }
        // Said out loud rather than folded into the total: the app saw most of these and was
        // told about the rest, and those are different kinds of claim.
        if a.manualReps > 0 { rows.append(StatRow("Added by hand", "\(a.manualReps) of \(a.totalReps)")) }
        // Said plainly and next to the score it qualifies, rather than buried. A total the camera
        // could not stand behind is a floor, and the athlete is owed that distinction here, where
        // they are reading the number, not in a settings screen.
        if a.untrackedMs > 0 {
            rows.append(StatRow("Camera lost you", formatDuration(a.untrackedMs)))
            if a.scoreIsLowerBound {
                rows.append(StatRow("Score", "At least \(a.totalReps) — some reps may be missing"))
            }
        }
        rows.append(energyRow(input))
        return rows
    }

    /// The energy estimate, or an invitation to make one possible.
    ///
    /// Shown as an estimate either way, because that is what it is. Without a heart rate the
    /// arithmetic is a MET table and the athlete's weight; where a watch was heard from during this
    /// workout, the minutes it covered switch to the Keytel heart-rate equation instead, and the
    /// footnote says exactly how much of the number came from which. The row stays labelled
    /// "Calories (est.)" whatever produced it: heart rate makes this a better estimate, not a
    /// measurement.
    static func energyRow(_ input: ResultsInput) -> StatRow {
        let a = input.attempt
        let body = input.body
        guard let est = Calories.estimate(totalReps: a.totalReps, activeMs: a.durationMs, body: body,
                                          trace: input.heartTrace) else {
            return StatRow("Calories", "Set your weight", action: .askBodyWeight)
        }
        let formula: String
        switch body.sex {
        case .female?: formula = "female"
        case .male?: formula = "male"
        case .unstated?, nil: formula = "averaged"
        }
        let kg = JavaText.fixed(body.weightKg, 0)
        let met = JavaText.fixed(est.met, 1)
        let footnote: String
        if est.usedHeartRate && est.estimatedMs == 0 {
            footnote = "From your heart rate across the whole workout · \(kg) kg, \(body.age!), \(formula) formula."
        } else if est.usedHeartRate {
            footnote = "From your heart rate for \(formatDuration(est.heartRateMs)) of \(formatDuration(a.durationMs)); "
                + "the other \(formatDuration(est.estimatedMs)) estimated from your reps at about \(met) METs · "
                + "\(kg) kg, \(body.age!), \(formula) formula."
        } else if input.heartTrace != nil && !body.canUseHeartRate {
            footnote = "Estimated from \(kg) kg at about \(met) METs. Your heart rate was recorded — tap "
                + "to add your age and sex and use it."
        } else {
            footnote = "Estimated from \(kg) kg at about \(met) METs. Tap to change your weight."
        }
        // A trace was recorded but there is nothing yet to read it with: offer the details that
        // would unlock it rather than the weight prompt that already ran.
        let action: ResultsAction = input.heartTrace != nil && !body.canUseHeartRate ? .askHeartRateDetails : .askBodyWeight
        return StatRow("Calories (est.)", "\(est.kcal) kcal", action: action, footnote: footnote)
    }

    // MARK: lifted and burned

    static func lifted(_ input: ResultsInput) -> LiftedSection {
        let a = input.attempt
        let lifted = Lifted.of(a, bodyWeightKg: input.body.weightKg)
        // The same call, with the same inputs, as the energy row under SESSION: this card must
        // never disagree with the number it sits above.
        let est = Calories.estimate(totalReps: a.totalReps, activeMs: a.durationMs, body: input.body,
                                    trace: input.heartTrace)
        if lifted == nil && est == nil {
            let invite = !(input.body.weightKg > 0) && (a.durationMs > 0 || Lifted.measurable(a))
            return invite ? .invite : .hidden
        }

        let rotation = Int64(input.zone.localDate(epochMs: a.atMillis).epochDay)
        var spoken: [String] = []

        var liftedPart: LiftedCard.LiftedPart?
        if let lifted {
            let match = Equivalents.animalFor(lifted.totalKg, rotation: rotation, font: input.font)
            let kgText = lifted.kgText()
            spoken.append("You lifted \(kgText.prefix(1).lowercased() + kgText.dropFirst()).")
            var sentence: String?
            if let match {
                sentence = Equivalents.heavySentence(match, atLeast: lifted.atLeast)
                spoken.append(sentence!)
            }
            let rounded = match.map { JavaText.roundToInt($0.count) } ?? 0
            liftedPart = .init(
                animalEmoji: match?.animal.emoji, emojiCount: match.map { Equivalents.emojiCount($0.count) } ?? 0,
                more: rounded > Equivalents.maxEmoji ? "×\(rounded)" : nil,
                figure: Figure(prefix: lifted.kgPrefix, number: lifted.kgNumber, unit: "kg"), sentence: sentence)
        }

        var burnedPart: LiftedCard.BurnedPart?
        var energyMethod: String?
        if let est {
            let match = Equivalents.energyFor(Double(est.kcal), rotation: rotation, font: input.font)
            let prefix: String? = a.scoreIsLowerBound ? "At least" : nil
            spoken.append("You burned \(prefix != nil ? "at least " : "")\(est.kcal) kcal.")
            var sentence: String?
            if let match {
                sentence = match.reference.sentence(match.count, atLeast: a.scoreIsLowerBound)
                spoken.append(sentence!)
                energyMethod = match.reference.method
            }
            burnedPart = .init(figure: Figure(prefix: prefix, number: "\(est.kcal)", unit: "kcal"),
                               emoji: match?.reference.emoji, sentence: sentence)
        }

        var notes: [String] = []
        if let lifted { notes.append(lifted.footnote(tappedIn: a.manualReps > 0)) }
        if est != nil {
            // The energy figure is the one the calories row already explains; this only points at it.
            var s = "Energy is the same estimate as the calories row below."
            if let m = energyMethod { s += " \(m)" }
            if lifted == nil && a.scoreIsLowerBound {
                s += " The camera lost you for part of this session, so this is a floor."
            }
            notes.append(s)
        }
        let note = notes.joined(separator: " ")
        spoken.append(note)
        return .card(LiftedCard(lifted: liftedPart, burned: burnedPart, note: note,
                                spoken: spoken.joined(separator: " ")))
    }

    // MARK: the comparison

    static func compare(_ a: Attempt, _ options: [Comparisons.Option], _ chosen: Comparisons.Option,
                        _ zone: Zone) -> CompareSection {
        let reference = chosen.attempt
        let date = DateText.short(zone.localDate(epochMs: reference.atMillis))
        let referenceLine = "\(date) · \(reference.scoreLabel) · \(Progress.formatReps(reference.totalReps)) reps"
        let d = Comparisons.delta(a, reference)
        var parts: [String] = []
        if d.reps > 0 { parts.append("+\(d.reps) reps") }
        else if d.reps < 0 { parts.append("\(-d.reps) fewer reps") }
        else { parts.append("level on reps") }
        if d.rounds > 0 { parts.append("\(d.rounds) round\(d.rounds == 1 ? "" : "s") more") }
        else if d.rounds < 0 { parts.append("\(-d.rounds) round\(d.rounds == -1 ? "" : "s") fewer") }
        if let ms = d.avgRoundMs {
            if ms > 0 { parts.append("\(formatDuration(ms)) faster a round") }
            else if ms < 0 { parts.append("\(formatDuration(-ms)) slower a round") }
        }
        // "At least" when the session's own score is a lower bound: the true gap can only be
        // larger than this, never smaller.
        let joined = parts.joined(separator: " · ")
        let deltaLine = a.scoreIsLowerBound ? "At least \(joined)" : joined
        return CompareSection(
            labels: options.map { $0.label }, chosen: options.firstIndex { $0.attempt.atMillis == reference.atMillis } ?? 0,
            card: ComparisonCard(attemptAtMillis: reference.atMillis, referenceLine: referenceLine,
                                 deltaLine: deltaLine, ahead: d.reps > 0))
    }

    // MARK: splits

    static func splits(_ a: Attempt, _ comparison: Attempt?, _ kind: Comparisons.Kind?) -> SplitsSection? {
        guard let split = RoundSplits.of(a) else { return nil }
        let ticks = RoundSplits.reference(split, comparison)
        let fastest = split.bars[split.fastest]
        // Taller is slower here, so say which way to read it.
        var note = "Taller is slower. Fastest was round \(fastest.round) at \(formatDuration(fastest.ms))."
        if a.pausedMs > 0 { note += " Splits exclude paused time." }
        if split.hasBreakdown {
            let names = RoundSplits.movementNames(a.profile)
            note += " Each bar stacks \(names[0]), \(names[1]) and \(names[2]), bottom to top."
        }
        if ticks.contains(where: { $0 != nil }) {
            note += kind == .last ? " The tick over each bar marks the same round last time."
                : " The tick over each bar marks the same round in your best."
        }
        if split.hasUnfinished { note += " The outlined bar is the round still under way when the clock stopped." }
        return SplitsSection(split: split, reference: ticks, note: note,
                             averageLabel: "AVG \(formatDuration(split.averageMs))")
    }

    // MARK: the timeline

    static func timeline(_ input: ResultsInput, _ comparison: Attempt?, _ kind: Comparisons.Kind?) -> TimelineSection? {
        let a = input.attempt
        let t = SessionTimeline.of(
            a, marks: input.repMarks, trace: input.heartTrace, reference: comparison, referenceKind: kind,
            referenceMarks: comparison.flatMap { input.marksFor($0.atMillis) },
            // Empty without a body weight, which hides the lane rather than guessing a weight.
            calories: Calories.timeline(totalReps: a.totalReps, activeMs: a.durationMs, body: input.body,
                                        trace: input.heartTrace))
        if !t.hasData { return nil }
        var kinds: [String] = []
        if t.reps != nil { kinds.append("reps") }
        if !t.heartRuns.isEmpty { kinds.append("heart rate") }
        if !t.calorieRuns.isEmpty { kinds.append("estimated calories") }
        var joined = kinds.joined(separator: ", ")
        if let comma = joined.range(of: ", ", options: .backwards) {
            joined.replaceSubrange(comma, with: " and ")
        }
        return TimelineSection(
            timeline: t, lanes: timelineLanes(t),
            stops: t.rounds.map { TimelineStop($0.startMs, $0.endMs, t.describeRound($0)) },
            description: "Timeline of this session: \(joined), one stop for each round", legend: t.legend())
    }

    /// The timeline's lanes, in the order they stack. Reps step: a rep is banked and then held, so
    /// a per-set session shows its sets as steps with a dot at each, which says "this much by the
    /// end of that set" and nothing about the reps in between.
    static func timelineLanes(_ t: SessionTimeline) -> [TimelineLane] {
        var lanes: [TimelineLane] = []
        if let reps = t.reps {
            lanes.append(TimelineLane(
                label: "REPS", tint: .reps,
                runs: [TimelineRun(reps.points.map { TimelinePoint($0.clockMs, Double($0.reps)) })],
                comparison: t.reference?.reps?.points.map { TimelinePoint($0.clockMs, Double($0.reps)) } ?? [],
                format: { Progress.formatReps(JavaText.roundToInt($0)) },
                stepped: true, zeroBased: true, markPoints: !reps.exact, height: 132))
        }
        if !t.heartRuns.isEmpty {
            lanes.append(TimelineLane(
                label: "HEART RATE", tint: .heart,
                runs: t.heartRuns.map { run in TimelineRun(run.map { TimelinePoint($0.clockMs, Double($0.bpm)) }) },
                format: { String(JavaText.roundToInt($0)) }, holdMs: Calories.maxHoldMs, height: 88))
        }
        if !t.calorieRuns.isEmpty {
            // Solid where a heart rate measured the stretch and dashed where the reps estimated
            // it, so the line says for itself how far to trust each part. Not the heart colour:
            // this is energy, and that colour is reserved for the pulse.
            lanes.append(TimelineLane(
                label: "KCAL (EST.)", tint: .energy,
                runs: t.calorieRuns.map { run in
                    TimelineRun(run.points.map { TimelinePoint($0.clockMs, $0.kcal) }, dashed: run.estimated)
                },
                format: { String(JavaText.roundToInt($0)) }, zeroBased: true, interpolate: true, height: 88))
        }
        return lanes
    }

    // MARK: the heart-rate card

    static func heart(_ input: ResultsInput) -> HeartCard? {
        let a = input.attempt
        let rounds = SessionTimeline.roundSpans(a, SessionTimeline.roundEnds(a)).filter { $0.complete }
        guard let s = HeartRateStats.of(input.heartTrace, durationMs: a.durationMs, rounds: rounds,
                                        age: input.body.age) else { return nil }

        let figures = [
            HeartCard.Figure(label: "AVERAGE", value: "\(s.avgBpm)", unit: "bpm",
                             spoken: "Average heart rate, \(s.avgBpm) beats per minute"),
            HeartCard.Figure(label: "MAXIMUM", value: "\(s.maxBpm)", unit: "bpm",
                             spoken: "Maximum heart rate, \(s.maxBpm) beats per minute"),
            HeartCard.Figure(label: "COVERED", value: formatDuration(s.coveredMs), unit: "of \(formatDuration(s.durationMs))",
                             spoken: "Your watch covered \(SessionTimeline.spokenDuration(s.coveredMs)) of "
                                + SessionTimeline.spokenDuration(s.durationMs))
        ]

        var zoneRows: [HeartCard.ZoneRow]?
        if let zones = s.zones {
            zoneRows = zones.map { z in
                let share = s.coveredMs > 0 ? JavaText.roundToInt(Double(z.ms) * 100.0 / Double(s.coveredMs)) : 0
                let spokenRange: String
                let range: String
                if let from = z.fromBpm, let to = z.toBpm {
                    spokenRange = "\(from) to \(to)"
                    range = "\(from)–\(to)"
                } else if let to = z.toBpm {
                    spokenRange = "under \(to + 1)"
                    range = "under \(to + 1)"
                } else {
                    spokenRange = "\(z.fromBpm!) and over"
                    range = "\(z.fromBpm!)+"
                }
                return HeartCard.ZoneRow(
                    zone: z.zone, name: "\(z.zone.short) \(z.zone.label)", time: formatDuration(z.ms),
                    range: "\(range) bpm",
                    spoken: "\(z.zone.short) \(z.zone.label), \(SessionTimeline.spokenDuration(z.ms)), "
                        + "\(share) percent of covered time, \(spokenRange) beats per minute",
                    ms: z.ms)
            }
        }
        let method = s.estimatedMaxBpm.map { max in
            "Zones are an estimate: shares of a maximum worked out from your age as 208 − 0.7 × age "
                + "(Tanaka), \(max) bpm for you, not one measured. A reading above it counts as Maximum. "
        } ?? ""
        return HeartCard(
            figures: figures, zones: zoneRows, zoneTimes: s.zones, invitesAge: s.zones == nil,
            hardestRound: s.hardestRound.map { "Round \($0.number) · \($0.avgBpm) bpm avg" },
            hardestRoundSpoken: s.hardestRound.map {
                "Hardest round, round \($0.number), \($0.avgBpm) beats per minute on average"
            },
            verdict: s.verdict,
            footnote: method + "Average and maximum count only the time your watch covered, and a watch can "
                + "lag your actual effort by a few seconds.",
            coveredMs: s.coveredMs)
    }
}
