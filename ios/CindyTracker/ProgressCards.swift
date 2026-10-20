import SwiftUI
import CindyCore

// The Progress screen's cards, drawn over the sections `ProgressPageBuilder` returns. Each is
// `RecordsActivity.kt`'s card in points; the words come from the models and from `ProgressWords`.

/// A section's small title above its card, indented 4 with 10 above and below.
struct SectionTitle: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).cindy(.eyebrow)
            .padding(.leading, 4).padding(.vertical, 10)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The habit rather than the scores: a line that is true today, both streaks, and which days of this
/// week were trained.
struct HabitCard: View {
    let hero: HeroCard
    let today: LocalDate?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(hero.headline).cindy(.title2, colour: Palette.label).accessibilityAddTraits(.isHeader)
            if let note = hero.emptyNote { Text(note).cindy(.callout).padding(.top, 8) }
            if let daily = hero.daily, let weekly = hero.weekly {
                HStack(alignment: .top, spacing: 0) {
                    StreakView(column: daily)
                    StreakView(column: weekly)
                }
                .padding(.top, 16)
            }
            if let start = hero.weekStart {
                WeekStripView(weekStart: start, trained: hero.trained, today: today ?? start).padding(.top, 16)
            }
            if let next = hero.nextStep { Text(next).cindy(.footnote).padding(.top, 12) }
            if let tally = hero.tally {
                Rectangle().fill(Palette.hairline).frame(height: Palette.hairlineWidth).padding(.top, 14)
                Text(tally).cindy(.footnote).padding(.top, 13)
            }
        }
        .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .padding(.bottom, 12)
    }
}

/// One streak: its name, then the figure, its unit and, for the daily one, the flame. One stop for a
/// screen reader, spoken as the model says it.
private struct StreakView: View {
    let column: StreakColumn

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(column.label).cindy(.eyebrow)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                if column.flame {
                    Image(CindyIcon.flame).resizable().scaledToFit()
                        .frame(width: 26, height: 26)
                        .foregroundStyle(column.value > 0 ? Palette.achievement : Palette.labelTertiary)
                        .padding(.trailing, 6)
                }
                Text("\(column.value)").cindy(.metricL).lineLimit(1).minimumScaleFactor(0.4)
                Text(column.unit).cindy(.headline, colour: Palette.labelSecondary)
                    .lineLimit(1).minimumScaleFactor(0.6).padding(.leading, 6)
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(column.spoken)
    }
}

/// Sessions, reps and time this week against last, then the month so far.
struct ThisWeekCard: View {
    let week: ThisWeek

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle(ProgressWords.thisWeekTitle)
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(week.tiles.enumerated()), id: \.offset) { _, tile in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(tile.label).cindy(.footnote)
                        Text(tile.value).cindy(.metricS).lineLimit(1).minimumScaleFactor(0.4).padding(.top, 4)
                        if let change = tile.change {
                            Text(change).cindy(.footnote, colour: tile.up ? Palette.stateOk : Palette.labelTertiary)
                                .padding(.top, 2)
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(tile.spoken)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .glassCard()
            Text(week.monthNote).cindy(.footnote).padding(.leading, 4).padding(.top, 12).padding(.bottom, 6)
        }
    }
}

/// The chart card: what to plot, over how long and, when more than one kind of Cindy has been
/// trained, which one. The note under it says how the athlete has moved, or what the chart counts.
struct ProgressChartCard: View {
    let card: ProgressCard
    @ObservedObject var vm: ProgressViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle(ProgressWords.progressTitle)
            VStack(alignment: .leading, spacing: 0) {
                ChipRow(options: card.metricLabels, selected: card.metric, onSelect: { vm.chooseMetric($0) })

                let readout = vm.readout
                HStack(alignment: .center, spacing: 0) {
                    Text(readout.headline).cindy(.headline, colour: Palette.label)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    // Only a selected line point is one session; a bar is a week of them, and nothing
                    // selected is the whole range, so the button only ever appears beside a point.
                    if let target = vm.openTarget {
                        Button(ProgressWords.open) { vm.open(session: target) }
                            .buttonStyle(CindyGlassButtonStyle(height: 40))
                    }
                }
                .padding(.top, 8)
                Text(readout.detail).cindy(.footnote)

                Group {
                    if card.chart == nil {
                        Text(card.empty).cindy(.footnote)
                            .frame(maxWidth: .infinity).frame(height: ProgressChartView.height)
                    } else {
                        ProgressChartView(vm: vm)
                    }
                }
                .padding(.top, 8)

                ChipRow(options: card.rangeLabels, selected: card.range, onSelect: { vm.chooseRange($0) })
                    .padding(.top, 4)
                if let labels = card.categoryLabels {
                    ScrollView(.horizontal, showsIndicators: false) {
                        ChipRow(options: labels, selected: card.category, onSelect: { vm.chooseCategory($0) })
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
            Text(card.note).cindy(.footnote).padding(.leading, 4).padding(.top, 10).padding(.bottom, 6)
        }
    }
}

/// Personal bests in the chosen category; never across categories.
struct PeaksGroup: View {
    let peaks: PeaksSection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle(ProgressWords.peaksTitle)
            InsetGroup(Array(peaks.rows.enumerated()), id: \.offset) { _, row in
                TrophyRow(rank: row.rank, title: row.title, detail: row.detail, value: row.value)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(row.spoken)
            }
            Text(peaks.footnote).cindy(.footnote).padding(.leading, 4).padding(.top, 10).padding(.bottom, 6)
        }
    }
}

/// The month grid, with arrows back through the athlete's history.
struct CalendarCard: View {
    let section: CalendarSection
    @ObservedObject var vm: ProgressViewModel

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 0) {
                arrow(.chevronLeft, ProgressWords.previousMonth, enabled: section.canGoBack) { vm.previousMonth() }
                Text("\(vm.calendar.monthTitle) \(section.month.year)")
                    .cindy(.headline, colour: Palette.label)
                    .frame(maxWidth: .infinity)
                arrow(.chevronRight, ProgressWords.nextMonth, enabled: section.canGoForward) { vm.nextMonth() }
            }
            CalendarGridView(vm: vm)
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 16)
        .glassCard()
        .padding(.bottom, 12)
    }

    /// A 46-point target, because these are small glyphs on a screen used with wet hands.
    private func arrow(_ icon: CindyIcon, _ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(icon).resizable().scaledToFit()
                .foregroundStyle(enabled ? Palette.labelSecondary : Palette.labelQuaternary)
                .padding(15)
                .frame(width: 46, height: 46)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
        .accessibilityHidden(!enabled)
    }
}

/// The benchmark and the athlete's own sessions, best first. A row of theirs opens its session.
struct LeaderboardGroup: View {
    let board: Leaderboard
    let onOpen: (Int64) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle(ProgressWords.leaderboardTitle)
            InsetGroup(Array(board.rows.enumerated()), id: \.offset) { _, row in
                RankRow(rank: row.rank, name: row.name, detail: row.detail, score: row.score,
                        mine: row.mine, best: row.best,
                        action: row.opens.map { id in { onOpen(id) } })
                    .accessibilityLabel(row.spoken)
                    .accessibilityIdentifier(row.opens == nil ? "benchmarkRow" : "leaderRow")
            }
            if let note = board.emptyNote {
                Text(note).cindy(.footnote)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 28)
            }
        }
    }
}
