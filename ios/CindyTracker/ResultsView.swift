import SwiftUI
import CindyCore

/// What just happened, or a saved session reopened: every card the README's "Records, levels and
/// statistics" describes. `ResultsPageBuilder` decides which cards show and what each says; this
/// only draws what it returns.
struct ResultsView: View {
    @StateObject private var vm: ResultsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var asking: Asking?
    @State private var reopened: ResultsRequest?
    @State private var heelsFlatExplained = false
    @State private var showProgress = false
    @State private var asksToDiscard = false
    @State private var toast: String?
    @State private var askingStrava = false
    /// Redraws the Strava row as its upload moves through the ledger.
    @ObservedObject private var strava = StravaCenter.shared
    /// Said to whatever is underneath once this page has discarded its session and closed: a
    /// dismissed sheet takes its own overlay with it, so the screen it was over has to say so.
    private let onDiscarded: () -> Void

    private enum Asking: Identifiable {
        case weight, heartRate
        var id: Int { self == .weight ? 0 : 1 }
    }

    init(_ request: ResultsRequest, onDiscarded: @escaping () -> Void = {}) {
        _vm = StateObject(wrappedValue: ResultsViewModel(request))
        self.onDiscarded = onDiscarded
    }

    var body: some View {
        let page = vm.page
        let discardQuestion = vm.discardQuestion
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header(page)
                if let box = page.celebration { celebration(box) }
                tiles(page.tiles)
                LevelCard(level: page.level)
                if let track = page.track { trackCard(track) }
                if let movements = page.movements { movementCard(movements) }
                lifted(page.lifted)
                if let compare = page.compare { comparison(compare) }
                if !page.stats.isEmpty || stravaRow != nil { statRows(page.stats) }
                if let splits = page.splits { splitsCard(splits) }
                if let timeline = page.timeline { timelineCard(timeline) }
                if let heart = page.heart { heartCard(heart) }

                // The bar is whatever the page says it is: PROGRESS only straight after a workout (a
                // reopened session came from Progress), DISCARD only for a session on the board.
                ActionBar {
                    ForEach(page.actions, id: \.rawValue) { action in
                        switch action {
                        case .progress:
                            Button(action.rawValue) { showProgress = true }.buttonStyle(CindyGlassButtonStyle())
                        case .discard:
                            Button(action.rawValue) { asksToDiscard = true }
                                .buttonStyle(CindyGlassButtonStyle(tint: Palette.stateAlert))
                        case .done:
                            Button(action.rawValue) { dismiss() }.buttonStyle(CindyPrimaryButtonStyle())
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
        }
        .background(Palette.background.ignoresSafeArea())
        .sheet(item: $asking, onDismiss: { vm.bodyChanged() }) { which in
            switch which {
            case .weight: BodyWeightSheet(profile: vm.profile, onSaved: { vm.bodyChanged() })
            case .heartRate: HeartRateDetailsSheet(profile: vm.profile, onSaved: { vm.bodyChanged() })
            }
        }
        .fullScreenCover(item: $reopened) { request in
            ResultsView(request, onDiscarded: { flash(ResultsPageBuilder.discardedToast) })
        }
        .sheet(isPresented: $askingStrava) { StravaConsentSheet(origin: .results(atMillis: vm.atMillis)) }
        .sheet(isPresented: $showProgress) { ProgressScreen() }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).chip().padding(.bottom, 90)
            }
        }
        // Why a standard Cindy came back as an Adaptive one, and a way to make the change the
        // athlete's own. Closed any way but the first button, it changes nothing.
        .cindySheet(isPresented: $heelsFlatExplained,
                    title: HeelsFlatSheet.title,
                    subtitle: HeelsFlatSheet.subtitle,
                    primary: SheetButton(title: HeelsFlatSheet.primary) {
                        HeelsFlatSheet.setHeelsFlat(on: vm.profile)
                        flash(HeelsFlatSheet.done)
                    },
                    secondary: SheetButton(title: HeelsFlatSheet.secondary) {}) {
            Text(HeelsFlatSheet.note).cindy(.footnote)
        }
        // KEEP IT is the one filled button, where a reflex tap lands after tapping DISCARD to get
        // here; DISCARD is the red one beside it. Every other way out of the question keeps the session.
        .cindySheet(isPresented: $asksToDiscard,
                    title: discardQuestion.title,
                    subtitle: discardQuestion.subtitle,
                    primary: SheetButton(title: discardQuestion.keep) {},
                    secondary: SheetButton(title: discardQuestion.discard, tint: Palette.stateAlert) {
                        // The page closes either way, but only a session that was there was discarded.
                        if vm.discard() { onDiscarded() }
                        dismiss()
                    })
    }

    private func flash(_ text: String) {
        toast = text
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if toast == text { toast = nil }
        }
    }

    // MARK: the top

    private func header(_ page: ResultsPage) -> some View {
        ScoreHeader(headline: page.headline, score: page.score, reps: page.scoreReps,
                    detail: page.scoreDetail, spoken: scoreSpoken(page))
    }

    private func scoreSpoken(_ page: ResultsPage) -> String {
        let rounds = Int(page.score) ?? 0
        let base = "\(rounds) round\(rounds == 1 ? "" : "s")"
        guard let reps = page.scoreReps else { return base }
        return "\(base) and \(reps.dropFirst()) more reps"
    }

    private func celebration(_ box: CelebrationBox) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(box.rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: symbol(row.icon))
                        .foregroundStyle(row.headline ? Ink.achievement : Color.dim)
                        .accessibilityHidden(true)
                    Text(row.text)
                        .font(.system(size: row.headline ? 16 : 14, weight: row.headline ? .semibold : .regular))
                        .foregroundStyle(.white)
                }
            }
            if let more = box.more {
                Text(more).font(.system(size: 12)).foregroundStyle(Color.dim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Ink.achievement.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    private func symbol(_ icon: CelebrationBox.Icon) -> String {
        switch icon {
        case .trophy: return "trophy.fill"
        case .flame: return "flame.fill"
        case .badge: return "rosette"
        }
    }

    private func tiles(_ tiles: [StatTile]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: 3), spacing: 8) {
            ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in
                VStack(alignment: .leading, spacing: 2) {
                    Text(tile.label).font(.system(size: 10, weight: .bold)).foregroundStyle(Color.dim)
                    Text(tile.value)
                        .font(.system(size: 20, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text(tile.footnote).font(.system(size: 10)).foregroundStyle(Color.dim)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(tile.speech)
            }
        }
    }

    // MARK: rounds and movements

    private func trackCard(_ track: TrackSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("ROUNDS")
            RoundTrackView(vm: vm)
            Text(vm.trackCaption).font(.system(size: 13)).foregroundStyle(.white)
                .frame(minHeight: 36, alignment: .topLeading)
            Text(track.footnote).font(.system(size: 12)).foregroundStyle(Color.dim)
        }
    }

    private func movementCard(_ movements: MovementsSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("MOVEMENTS")
            HStack(alignment: .top, spacing: 8) {
                ForEach(Array(movements.columns.enumerated()), id: \.offset) { _, column in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(column.label).font(.system(size: 11, weight: .bold)).foregroundStyle(Color.dim)
                            .lineLimit(movements.tall ? 3 : 1)
                        Text("\(column.atLeast ? "≥" : "")\(column.reps)")
                            .font(.system(size: 24, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Ink.movement(column.movement))
                        ForEach(column.lines, id: \.self) { line in
                            Text(line).font(.system(size: 11)).foregroundStyle(Color.dim)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(column.spoken)
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            Text(movements.footnote).font(.system(size: 12)).foregroundStyle(Color.dim)
        }
    }

    // MARK: lifted and burned

    @ViewBuilder private func lifted(_ section: LiftedSection) -> some View {
        switch section {
        case .hidden:
            EmptyView()
        case .invite:
            Button { asking = .weight } label: {
                HStack {
                    Text("Add your weight to see what you lifted and burned")
                        .font(.system(size: 14)).foregroundStyle(.white)
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(Color.dim)
                }
                .padding(14)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            }
        case .card(let card):
            liftedCard(card)
        }
    }

    private func liftedCard(_ card: LiftedCard) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let lifted = card.lifted {
                VStack(alignment: .leading, spacing: 4) {
                    sectionTitle("LIFTED")
                    figure(lifted.figure)
                    if let animal = lifted.animalEmoji {
                        HStack(spacing: 2) {
                            ForEach(0..<lifted.emojiCount, id: \.self) { _ in Text(animal).font(.system(size: 26)) }
                            if let more = lifted.more {
                                Text(more).font(.system(size: 14, design: .monospaced)).foregroundStyle(Color.dim)
                            }
                        }
                    }
                    if let sentence = lifted.sentence {
                        Text(sentence).font(.system(size: 13)).foregroundStyle(Color.dim)
                    }
                }
            }
            if let burned = card.burned {
                VStack(alignment: .leading, spacing: 4) {
                    sectionTitle("BURNED")
                    HStack(spacing: 6) {
                        figure(burned.figure)
                        if let emoji = burned.emoji { Text(emoji).font(.system(size: 26)) }
                    }
                    if let sentence = burned.sentence {
                        Text(sentence).font(.system(size: 13)).foregroundStyle(Color.dim)
                    }
                }
            }
            Text(card.note).font(.system(size: 12)).foregroundStyle(Color.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        // The emoji would be named one by one; the card says itself in one sentence.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.spoken)
    }

    private func figure(_ f: Figure) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if let prefix = f.prefix { Text(prefix).font(.system(size: 13)).foregroundStyle(Color.dim) }
            Text(f.number).font(.system(size: 30, weight: .bold, design: .monospaced)).foregroundStyle(.white)
            Text(f.unit).font(.system(size: 14)).foregroundStyle(Color.dim)
        }
    }

    // MARK: compared with

    private func comparison(_ compare: CompareSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("COMPARED WITH")
            if compare.labels.count > 1 {
                HStack(spacing: 8) {
                    ForEach(Array(compare.labels.enumerated()), id: \.offset) { i, label in
                        Button { vm.chooseComparison(i) } label: {
                            Text(label)
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .foregroundStyle(i == compare.chosen ? Color.black : Color.white)
                                .background(i == compare.chosen ? Color.white : Color.white.opacity(0.12), in: Capsule())
                        }
                        .accessibilityAddTraits(i == compare.chosen ? .isSelected : [])
                    }
                }
            }
            // Tapping the card reopens that session's own results.
            Button { reopened = vm.reopen(compare.card.attemptAtMillis) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(compare.card.referenceLine).font(.system(size: 14)).foregroundStyle(.white)
                    Text(compare.card.deltaLine)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(compare.card.ahead ? Color.accent : Color.warn)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            }
            .accessibilityLabel(compare.card.spoken)
            .accessibilityHint("Opens that session")
        }
    }

    // MARK: details

    private func statRows(_ rows: [StatRow]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("DETAILS")
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 2) {
                    if let action = row.action {
                        Button { perform(action) } label: { statLine(row, tappable: true) }
                    } else {
                        statLine(row, tappable: false)
                    }
                    if let note = row.footnote {
                        Text(note).font(.system(size: 11)).foregroundStyle(Color.dim)
                    }
                }
            }
            if let row = stravaRow { stravaLine(row) }
        }
    }

    // MARK: strava

    /// Where this attempt's upload has got to, or an offer to start one. Absent in a build with no
    /// Strava credentials. `strava.revision` is read so the row follows the ledger.
    private var stravaRow: StravaRow? {
        _ = strava.revision
        return StravaRow.of(config: strava.config, tokens: strava.tokens, ledger: strava.ledger, atMillis: vm.atMillis)
    }

    @ViewBuilder private func stravaLine(_ row: StravaRow) -> some View {
        let line = HStack {
            Text(StravaRow.label).font(.system(size: 14)).foregroundStyle(Color.dim)
            Spacer()
            Text(row.value)
                .font(.system(size: 16, weight: row.isLink ? .bold : .regular, design: .monospaced))
                .underline(row.isLink)
                .foregroundStyle(.white)
            if row.action != nil { Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Color.dim) }
        }
        if let action = row.action {
            Button { performStrava(action) } label: { line }
                .accessibilityLabel("\(StravaRow.label), \(row.value)")
                .accessibilityIdentifier("stravaRow")
        } else {
            line.accessibilityElement(children: .combine).accessibilityIdentifier("stravaRow")
        }
    }

    private func performStrava(_ action: StravaRow.Action) {
        switch action {
        case .upload: strava.upload(atMillis: vm.atMillis)
        case .askThenConnect: askingStrava = true
        case .openActivity(let id): strava.openActivity(id)
        }
    }

    private func statLine(_ row: StatRow, tappable: Bool) -> some View {
        HStack {
            Text(row.label).font(.system(size: 14)).foregroundStyle(Color.dim)
            Spacer()
            Text(row.value).font(.system(size: 16, design: .monospaced)).foregroundStyle(.white)
            if tappable { Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Color.dim) }
        }
    }

    private func perform(_ action: ResultsAction) {
        switch action {
        case .askBodyWeight: asking = .weight
        case .askHeartRateDetails: asking = .heartRate
        case .explainHeelsFlat: heelsFlatExplained = true
        }
    }

    // MARK: splits and timeline

    private func splitsCard(_ splits: SplitsSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("ROUND SPLITS")
            if let readout = vm.splitsReadout {
                VStack(alignment: .leading, spacing: 2) {
                    Text(readout.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    Text(readout.detail).font(.system(size: 12)).foregroundStyle(Color.dim)
                    // Kept (empty) while a comparison exists, so the chart under it does not move.
                    if readout.versusVisibility != .gone {
                        Text(readout.versus ?? " ")
                            .font(.system(size: 12))
                            .foregroundStyle(readout.faster == true ? Color.accent : Color.warn)
                            .opacity(readout.versusVisibility == .visible ? 1 : 0)
                    }
                }
            }
            RoundSplitsView(vm: vm)
            Text(splits.note).font(.system(size: 12)).foregroundStyle(Color.dim)
        }
    }

    private func timelineCard(_ timeline: TimelineSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("TIMELINE")
            if let readout = vm.timelineReadout {
                VStack(alignment: .leading, spacing: 2) {
                    Text(readout.title).font(.system(size: 14, weight: .semibold, design: .monospaced)).foregroundStyle(.white)
                    Text(readout.detail).font(.system(size: 12)).foregroundStyle(Color.dim)
                }
            }
            SessionTimelineView(vm: vm)
            if let legend = timeline.legend {
                Text(legend).font(.system(size: 12)).foregroundStyle(Color.dim)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(timeline.description)
    }

    // MARK: heart rate

    private func heartCard(_ heart: HeartCard) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("HEART RATE")
            HStack(alignment: .top, spacing: 16) {
                ForEach(Array(heart.figures.enumerated()), id: \.offset) { _, f in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(f.label).font(.system(size: 10, weight: .bold)).foregroundStyle(Color.dim)
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(f.value).font(.system(size: 28, weight: .bold, design: .monospaced)).foregroundStyle(.white)
                            Text(f.unit).font(.system(size: 12)).foregroundStyle(Color.dim)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(f.spoken)
                }
            }
            if let rows = heart.zones {
                ZoneBarView(vm: vm)
                ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                    HStack {
                        Circle().fill(Ink.heart.opacity(ZoneBarModel.alpha[i])).frame(width: 10, height: 10)
                        Text(row.name).font(.system(size: 13)).foregroundStyle(.white)
                        Text(row.range).font(.system(size: 11)).foregroundStyle(Color.dim)
                        Spacer()
                        Text(row.time).font(.system(size: 13, design: .monospaced)).foregroundStyle(.white)
                    }
                    .opacity(vm.zoneSelected == nil || vm.zoneSelected == i ? 1 : ZoneBarModel.dim)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(row.spoken)
                }
            } else if heart.invitesAge {
                Button { asking = .heartRate } label: {
                    HStack {
                        Text("Add your birth year to see your heart-rate zones")
                            .font(.system(size: 14)).foregroundStyle(.white)
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Color.dim)
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            if let hardest = heart.hardestRound {
                Text(hardest).font(.system(size: 13)).foregroundStyle(.white)
                    .accessibilityLabel(heart.hardestRoundSpoken ?? hardest)
            }
            if let verdict = heart.verdict {
                Text(verdict).font(.system(size: 13)).foregroundStyle(Color.dim)
            }
            Text(heart.footnote).font(.system(size: 11)).foregroundStyle(Color.dim)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Color.dim)
            .padding(.top, 8)
            .accessibilityAddTraits(.isHeader)
    }
}
