import SwiftUI
import CindyCore

// The session page's cards, drawn over the sections `ResultsPageBuilder` returns. Each is
// `activity_results.xml`'s and `ResultsActivity.kt`'s card in points; the words come from the models
// and from `ResultsWords`.

/// The headline eyebrow, the score and the line under it. The score is the page's one large figure:
/// the loose reps sit beside it in a lighter ink on the same baseline, and the two are one stop for
/// VoiceOver, spoken as `spoken`.
struct ScoreHeader: View {
    let headline: String
    let score: String
    let reps: String?
    let detail: String
    let spoken: String

    @ScaledMetric(relativeTo: .largeTitle) private var scoreSize: CGFloat = 72
    @ScaledMetric(relativeTo: .largeTitle) private var repsSize: CGFloat = 38

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(headline).cindy(.eyebrow).accessibilityAddTraits(.isHeader)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(score)
                    .font(Manrope.font(.extrabold, size: scoreSize).monospacedDigit())
                    .tracking(-0.048 * scoreSize)
                    .foregroundStyle(Palette.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                if let reps {
                    Text(reps)
                        .font(Manrope.font(.bold, size: repsSize).monospacedDigit())
                        .tracking(-0.048 * repsSize)
                        .foregroundStyle(Palette.labelTertiary)
                        .lineLimit(1)
                        .padding(.leading, 6)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)
            Text(detail).cindy(.callout).padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The level: the title and the rung on one baseline, what the level means, a bar to the next one
/// (absent for an adaptive session, where an empty bar would read as no progress) and what is next.
struct LevelCard: View {
    let level: LevelPanel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(level.title).cindy(.title2, colour: Palette.label)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let rung = level.rung {
                    Text(rung).cindy(.footnote, colour: Palette.labelSecondary)
                }
            }
            Text(level.blurb).cindy(.footnote, colour: Palette.labelSecondary).padding(.top, 5)
            if let percent = level.progressPercent {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.labelQuaternary)
                        Capsule().fill(Palette.primaryFill)
                            .frame(width: geo.size.width * CGFloat(min(max(percent, 0), 100)) / 100)
                    }
                }
                .frame(height: 5)
                .padding(.top, 16)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Level progress")
                .accessibilityValue("\(percent) percent")
            }
            Text(level.next).cindy(.footnote).padding(.top, 10)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18).padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

// MARK: sections

/// A section's small title, above its card.
struct SectionEyebrow: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).cindy(.eyebrow).accessibilityAddTraits(.isHeader)
    }
}

/// The weights of ink that tell the movements apart: white for pull-ups, then ever fainter, so no
/// colour has to be learned.
func movementInk(_ movement: Exercise) -> Color {
    switch movement {
    case .pullup: return Palette.label
    case .pushup: return Palette.labelSecondary
    case .squat: return Palette.labelTertiary
    }
}

/// A glass card with the padding a chart's card has.
struct ChartCard<Content: View>: View {
    var vertical: CGFloat = 14
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .padding(.horizontal, 16)
            .padding(.vertical, vertical)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
    }
}

/// What the session earned, said once and loudly: the first row is the headline. Each row has a slot
/// for its mark, so the words line up whether it is a medal, a flame or a badge.
struct CelebrationCard: View {
    let box: CelebrationBox

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(box.rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 12) {
                    mark(row.icon).frame(width: 36, height: 36)
                    Text(row.text)
                        .cindy(row.headline ? .title2 : .headline,
                               colour: row.headline ? Palette.achievement : Palette.label)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if let more = box.more {
                Text(more).cindy(.callout, colour: Palette.labelSecondary).padding(.leading, 48)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func mark(_ icon: CelebrationBox.Icon) -> some View {
        switch icon {
        case .trophy: Medal(rank: 1)
        case .flame:
            Image(CindyIcon.flame).resizable().scaledToFit()
                .foregroundStyle(Palette.achievement).padding(6).accessibilityHidden(true)
        case .badge(let badge): BadgeDisc(face: badge.face, earned: true, size: 36)
        }
    }
}

/// The session in six numbers, three by two. A figure shrinks before it wraps; each tile is one stop,
/// spoken as the model says it.
struct StatTileGrid: View {
    let tiles: [StatTile]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: 3),
                  spacing: 8) {
            ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in
                VStack(alignment: .leading, spacing: 0) {
                    Text(tile.label).cindy(.eyebrow)
                        .lineLimit(1).minimumScaleFactor(8.0 / 11.0)
                    Text(tile.value).cindy(.metricS)
                        .lineLimit(1).minimumScaleFactor(14.0 / 22.0)
                        .padding(.top, 6)
                    Text(tile.footnote).cindy(.footnote)
                        .lineLimit(3).padding(.top, 2)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .glassCard()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(tile.speech)
            }
        }
    }
}

/// A pill per round, the caption for the one touched, and the footnote.
struct TrackCard: View {
    @ObservedObject var vm: ResultsViewModel
    let track: TrackSection

    var body: some View {
        ChartCard {
            RoundTrackView(vm: vm)
            Text(vm.trackCaption).cindy(.callout, colour: Palette.label)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .topLeading)
                .padding(.top, 8)
            Text(track.footnote).cindy(.footnote).padding(.top, 4)
        }
    }
}

/// What each movement came to: a column apiece, the dot the weight of that movement's ink.
struct MovementCard: View {
    let movements: MovementsSection

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(Array(movements.columns.enumerated()), id: \.offset) { _, column in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Circle().fill(movementInk(column.movement)).frame(width: 6, height: 6)
                            Text(column.label).cindy(.footnote, colour: Palette.labelSecondary)
                                .lineLimit(2, reservesSpace: movements.tall)
                        }
                        if column.atLeast { Text("at least").cindy(.footnote) }
                        Text("\(column.reps)").cindy(.metricS)
                            .lineLimit(1).minimumScaleFactor(14.0 / 22.0)
                        ForEach(column.lines, id: \.self) { line in
                            Text(line).cindy(.footnote)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(column.spoken)
                }
            }
            .padding(14)
            .glassCard()
            Text(movements.footnote).cindy(.footnote).padding(.leading, 4)
        }
    }
}

/// What the session lifted and what it burned, in one card of two halves.
struct LiftedCardView: View {
    let card: LiftedCard

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let lifted = card.lifted {
                SectionEyebrow(ResultsWords.liftedEyebrow)
                if let animal = lifted.animalEmoji {
                    HStack(spacing: 2) {
                        ForEach(0..<lifted.emojiCount, id: \.self) { _ in Text(animal).font(.system(size: 36)) }
                        if let more = lifted.more { Text(more).cindy(.callout) }
                    }
                    .padding(.top, 6)
                }
                figure(lifted.figure).padding(.top, 6)
                if let sentence = lifted.sentence {
                    Text(sentence).cindy(.body).padding(.top, 4)
                }
            }
            if let burned = card.burned {
                if card.lifted != nil {
                    Rectangle().fill(Palette.hairline).frame(height: Palette.hairlineWidth).padding(.vertical, 18)
                }
                SectionEyebrow(ResultsWords.burnedEyebrow)
                HStack(spacing: 8) {
                    figure(burned.figure)
                    if let emoji = burned.emoji { Text(emoji).font(.system(size: 36)) }
                }
                .padding(.top, 6)
                if let sentence = burned.sentence {
                    Text(sentence).cindy(.body).padding(.top, 4)
                }
            }
            Text(card.note).cindy(.footnote).padding(.top, 16)
        }
        .padding(.horizontal, 20).padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        // The emoji would be named one by one; the card says itself in one sentence.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.spoken)
    }

    private func figure(_ f: Figure) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if let prefix = f.prefix { Text(prefix).cindy(.callout, colour: Palette.labelSecondary) }
            Text(f.number).cindy(.metricM).lineLimit(1).minimumScaleFactor(0.5)
            Text(f.unit).cindy(.callout, colour: Palette.labelSecondary)
        }
    }
}

/// The earlier session this one is set against, with the choice of which. The card opens that
/// session.
struct ComparisonCardView: View {
    let compare: CompareSection
    let onChoose: (Int) -> Void
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(ResultsWords.compareTitle)
            if compare.labels.count > 1 {
                ChipRow(options: compare.labels, selected: compare.chosen, onSelect: onChoose)
            }
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(compare.card.referenceLine).cindy(.headline)
                    Text(compare.card.deltaLine)
                        .cindy(.callout, colour: compare.card.ahead ? Palette.stateOk : Palette.labelTertiary)
                }
                .padding(.horizontal, 18).padding(.vertical, 14)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .glassCard()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(compare.card.spoken)
            .accessibilityHint("Opens that session")
        }
    }
}
