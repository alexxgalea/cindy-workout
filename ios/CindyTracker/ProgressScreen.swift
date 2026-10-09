import SwiftUI
import CindyCore

/// The record board: the habit, this week against last, the progress chart, the peaks, the
/// calendar and the leaderboard. `ProgressPageBuilder` decides which cards show and what each says;
/// this only draws what it returns.
struct ProgressScreen: View {
    @StateObject private var vm = ProgressViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let page = vm.page
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                hero(page.hero)
                if let week = page.thisWeek { thisWeek(week) }
                if let card = page.progress { progress(card) }
                if let peaks = page.peaks { peaksSection(peaks) }
                if let calendar = page.calendar { calendarCard(calendar) }
                leaderboard(page.leaderboard)

                HStack(spacing: 10) {
                    if page.canClear {
                        Button("CLEAR") { vm.asksToClear = true }
                            .buttonStyle(GhostButton(tint: .warn))
                    }
                    Button("DONE") { dismiss() }.buttonStyle(PrimaryButton())
                }
                .padding(.top, 16)
            }
            .padding(20)
        }
        .background(Color.appBackground)
        .overlay(alignment: .bottom) {
            if let toast = vm.toast {
                Text(toast).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).chip().padding(.bottom, 90)
            }
        }
        .sheet(item: $vm.route) { route in
            switch route {
            case .day(let sheet): DaySheetView(sheet: sheet, open: vm.open(session:))
            case .session(let request): ResultsView(request)
            }
        }
        // The safe answer is the one that cancels: a reflex second tap where the thumb already is
        // keeps the records.
        .confirmationDialog(vm.progress.clearQuestion?.title ?? "", isPresented: $vm.asksToClear, titleVisibility: .visible) {
            Button("DELETE", role: .destructive) { vm.clear() }
            Button("KEEP THEM", role: .cancel) {}
        } message: {
            Text(vm.progress.clearQuestion?.subtitle ?? "")
        }
    }

    // MARK: the habit

    private func hero(_ hero: HeroCard) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(hero.headline).font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            if let note = hero.emptyNote {
                Text(note).font(.system(size: 15)).foregroundStyle(Color.dim)
            }
            if let daily = hero.daily, let weekly = hero.weekly {
                HStack(alignment: .top) {
                    streak(daily)
                    streak(weekly)
                }
                .padding(.top, 4)
            }
            if let start = hero.weekStart {
                WeekStripView(weekStart: start, trained: hero.trained, today: vm.page.calendar?.today ?? start)
            }
            if let next = hero.nextStep {
                Text(next).font(.system(size: 12)).foregroundStyle(Color.dim)
            }
            if let tally = hero.tally {
                Divider().overlay(Ink.hairline)
                Text(tally).font(.system(size: 12)).foregroundStyle(Color.dim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    private func streak(_ column: StreakColumn) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(column.label).font(.system(size: 10, weight: .bold)).foregroundStyle(Color.dim)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if column.flame {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(column.value > 0 ? Ink.achievement : Ink.tertiary)
                }
                Text("\(column.value)").font(.system(size: 34, weight: .bold, design: .monospaced)).foregroundStyle(.white)
                Text(column.unit).font(.system(size: 15, weight: .semibold)).foregroundStyle(Ink.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(column.spoken)
    }

    // MARK: this week

    private func thisWeek(_ week: ThisWeek) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("THIS WEEK")
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(week.tiles.enumerated()), id: \.offset) { _, tile in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tile.label).font(.system(size: 12)).foregroundStyle(Color.dim)
                        Text(tile.value).font(.system(size: 20, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white).minimumScaleFactor(0.6).lineLimit(1)
                        if let change = tile.change {
                            Text(change).font(.system(size: 12)).foregroundStyle(tile.up ? Color.accent : Ink.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(tile.spoken)
                }
            }
            .padding(.vertical, 16)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            Text(week.monthNote).font(.system(size: 12)).foregroundStyle(Color.dim).padding(.leading, 4)
        }
    }

    // MARK: the chart

    private func progress(_ card: ProgressCard) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("PROGRESS")
            VStack(alignment: .leading, spacing: 8) {
                chips(card.metricLabels, selected: card.metric) { vm.chooseMetric($0) }

                let readout = vm.readout
                HStack {
                    Text(readout.headline).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    Spacer()
                    // Only a selected line point is one session; a bar is a week of them, and nothing
                    // selected is the whole range, so the button only ever appears beside a point.
                    if let target = vm.openTarget {
                        Button("OPEN") { vm.open(session: target) }.buttonStyle(GhostButton(tint: .white))
                    }
                }
                Text(readout.detail).font(.system(size: 12)).foregroundStyle(Color.dim)

                if card.chart == nil {
                    Text(card.empty).font(.system(size: 12)).foregroundStyle(Color.dim)
                        .frame(maxWidth: .infinity).frame(height: ProgressChartView.height)
                } else {
                    ProgressChartView(vm: vm)
                }

                chips(card.rangeLabels, selected: card.range) { vm.chooseRange($0) }
                if let labels = card.categoryLabels {
                    ScrollView(.horizontal, showsIndicators: false) {
                        chips(labels, selected: card.category) { vm.chooseCategory($0) }
                    }
                }
            }
            .padding(16)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            Text(card.note).font(.system(size: 12)).foregroundStyle(Color.dim).padding(.leading, 4)
        }
    }

    private func chips(_ labels: [String], selected: Int, choose: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(labels.enumerated()), id: \.offset) { i, label in
                Button { choose(i) } label: {
                    Text(label)
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .foregroundStyle(i == selected ? Color.black : Color.white)
                        .background(i == selected ? Color.white : Color.white.opacity(0.12), in: Capsule())
                }
                .accessibilityAddTraits(i == selected ? .isSelected : [])
            }
        }
    }

    // MARK: peaks, calendar, leaderboard

    private func peaksSection(_ peaks: PeaksSection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("PEAKS")
            VStack(spacing: 0) {
                ForEach(Array(peaks.rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 14) {
                        medal(row.rank)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                            Text(row.detail).font(.system(size: 12)).foregroundStyle(Color.dim)
                        }
                        Spacer()
                        Text(row.value).font(.system(size: 20, weight: .semibold, design: .monospaced)).foregroundStyle(.white)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(row.spoken)
                }
            }
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            Text(peaks.footnote).font(.system(size: 12)).foregroundStyle(Color.dim).padding(.leading, 4)
        }
    }

    /// A disc with its place in it: first is the earned colour; second and third step down the ramp.
    private func medal(_ rank: Int) -> some View {
        Text("\(rank)")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.black)
            .frame(width: 28, height: 28)
            .background(rank == 1 ? Ink.achievement : (rank == 2 ? Ink.label : Ink.secondary), in: Circle())
            .accessibilityHidden(true)
    }

    private func calendarCard(_ section: CalendarSection) -> some View {
        VStack(spacing: 4) {
            HStack {
                arrow("chevron.left", "Previous month", enabled: section.canGoBack) { vm.previousMonth() }
                Text("\(vm.calendar.monthTitle) \(section.month.year)")
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                arrow("chevron.right", "Next month", enabled: section.canGoForward) { vm.nextMonth() }
            }
            CalendarGridView(vm: vm)
        }
        .padding(16)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    /// A 46-point target, because these are small glyphs on a screen used with wet hands.
    private func arrow(_ symbol: String, _ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .foregroundStyle(enabled ? Ink.secondary : Ink.quaternary)
                .frame(width: 46, height: 46)
        }
        .disabled(!enabled)
        .accessibilityLabel(label)
        .accessibilityHidden(!enabled)
    }

    private func leaderboard(_ board: Leaderboard) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("LEADERBOARD")
            VStack(spacing: 0) {
                ForEach(Array(board.rows.enumerated()), id: \.offset) { _, row in
                    if let opens = row.opens {
                        Button { vm.open(session: opens) } label: { leaderRow(row, tappable: true) }
                            .accessibilityLabel(row.spoken)
                            .accessibilityAddTraits(.isButton)
                    } else {
                        leaderRow(row, tappable: false).accessibilityElement(children: .ignore).accessibilityLabel(row.spoken)
                    }
                }
            }
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            if let note = board.emptyNote {
                Text(note).font(.system(size: 12)).foregroundStyle(Color.dim)
                    .frame(maxWidth: .infinity).padding(.top, 28)
            }
        }
    }

    private func leaderRow(_ row: LeaderRow, tappable: Bool) -> some View {
        HStack(spacing: 10) {
            Text(row.rank).font(.system(size: 15)).foregroundStyle(Ink.tertiary).frame(width: 22, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(row.name).font(.system(size: 16, weight: row.mine ? .heavy : .semibold)).foregroundStyle(.white)
                    if row.best {
                        Text("BEST").font(.system(size: 9.5, weight: .bold)).foregroundStyle(.black)
                            .padding(.horizontal, 6).padding(.vertical, 2).background(Color.white, in: Capsule())
                    }
                }
                Text(row.detail).font(.system(size: 12)).foregroundStyle(Color.dim)
            }
            Spacer()
            Text(row.score).font(.system(size: 20, weight: .semibold, design: .monospaced))
                .foregroundStyle(row.mine ? Color.white : Ink.secondary)
            if tappable { Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Color.dim) }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(row.mine ? Color.white.opacity(0.05) : Color.clear)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.system(size: 12, weight: .bold)).foregroundStyle(Color.dim)
            .padding(.top, 10).padding(.leading, 4).accessibilityAddTraits(.isHeader)
    }
}

/// One trained day's sessions, oldest first. A row opens its session.
struct DaySheetView: View {
    let sheet: DaySheet
    let open: (Int64) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(sheet.title).font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                Text(sheet.subtitle).font(.system(size: 14)).foregroundStyle(Color.dim)
            }
            VStack(spacing: 0) {
                ForEach(Array(sheet.rows.enumerated()), id: \.offset) { _, row in
                    Button { open(row.opens) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.time).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                                Text(row.value).font(.system(size: 12)).foregroundStyle(Color.dim)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Color.dim)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                    }
                    .accessibilityLabel(row.spoken)
                    .accessibilityAddTraits(.isButton)
                }
            }
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            Spacer()
            Button("DONE") { dismiss() }.buttonStyle(PrimaryButton())
        }
        .padding(20)
        .background(Color.appBackground)
        .presentationDetents([.medium, .large])
    }
}
