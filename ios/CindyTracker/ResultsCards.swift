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
