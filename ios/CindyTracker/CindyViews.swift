import SwiftUI
import UIKit

/// The shared vocabulary the screens are built from, `CindyViews.kt` for the iPhone.
///
/// Android wrote the tappable row, the label and value row and the rank row out longhand two or
/// three times each, and the copies drifted. These exist once. Two things hold throughout: every
/// measurement is Android's in points, and a row is one element to VoiceOver, spoken as a whole
/// rather than as the three texts it is drawn from.

/// Touch feedback for a row that stays inside the group's rounded corners, as Android's ripple does.
private struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .background(configuration.isPressed ? Color(argb: 0x1FFFFFFF) : Color.clear)
    }
}

/// The frame every row shares: the padding, the minimum height, and the centred line.
private struct RowFrame<Content: View>: View {
    let minHeight: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 0, content: content)
            .padding(.leading, 18).padding(.trailing, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
    }
}

/// The column of title over value that every row shares.
private struct RowText: View {
    let title: String
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).cindy(.headline)
            if let detail { Text(detail).cindy(.footnote) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RowChevron: View {
    var body: some View {
        Image(CindyIcon.chevronRight)
            .resizable()
            .frame(width: 17, height: 17)
            .foregroundStyle(Palette.labelTertiary)
            .padding(.leading, 12)
            .accessibilityHidden(true)
    }
}

/// A row that is a button when it has an action and plain content when it has none.
private struct RowButton<Content: View>: View {
    let action: (() -> Void)?
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        if let action {
            Button(action: action, label: content)
                .buttonStyle(RowPressStyle())
                .accessibilityLabel(label)
                .accessibilityAddTraits(.isButton)
        } else {
            content()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
        }
    }
}

/// One card, with its rows hairline-divided.
///
/// Android's old screens gave every row its own rounded rectangle and a gap, which reads as a pile
/// of unrelated cards rather than a list. Separators are inset to the text edge, as in a grouped
/// list, so the eye follows the column of titles rather than a ladder of full-width rules. The
/// footer follows the last row with no separator, so it reads as a continuation: the small print a
/// row sometimes needs.
struct InsetGroup<Data: RandomAccessCollection, ID: Hashable, Row: View, Footer: View>: View {
    private let data: Data
    private let id: KeyPath<Data.Element, ID>
    private let row: (Data.Element) -> Row
    private let footer: Footer
    @Environment(\.displayScale) private var displayScale

    init(_ data: Data, id: KeyPath<Data.Element, ID>,
         @ViewBuilder row: @escaping (Data.Element) -> Row,
         @ViewBuilder footer: () -> Footer) {
        self.data = data
        self.id = id
        self.row = row
        self.footer = footer()
    }

    var body: some View {
        let first = data.first.map { $0[keyPath: id] }
        VStack(spacing: 0) {
            ForEach(data, id: id) { element in
                if element[keyPath: id] != first {
                    // A hairline is one physical pixel: at 3x, a one-point rule is a visible bar.
                    Rectangle().fill(Palette.hairline).frame(height: 1 / displayScale).padding(.leading, 18)
                }
                row(element)
            }
            footer
        }
        .frame(maxWidth: .infinity)
        .glassCard()
        .clipShape(RoundedRectangle(cornerRadius: Palette.radiusCard))
    }
}

extension InsetGroup where Footer == EmptyView {
    init(_ data: Data, id: KeyPath<Data.Element, ID>, @ViewBuilder row: @escaping (Data.Element) -> Row) {
        self.init(data, id: id, row: row, footer: { EmptyView() })
    }
}

/// A row that opens something: what it is, what it is currently set to, and a chevron.
///
/// The value is part of the row's spoken name as well as its look: announcing only "body weight"
/// would hide the very thing the row exists to report. `spoken` replaces the default name where a
/// row has a better one.
struct NavRow: View {
    let title: String
    let value: String
    var spoken: String? = nil
    let action: () -> Void

    var body: some View {
        RowButton(action: action, label: spoken ?? "\(title), \(value)") {
            RowFrame(minHeight: 64) {
                RowText(title: title, detail: value)
                RowChevron()
            }
        }
    }
}

/// A label and its figure. A tappable row gets a chevron and says so.
struct StatRow: View {
    let label: String
    let value: String
    var action: (() -> Void)? = nil

    var body: some View {
        RowButton(action: action, label: action == nil ? "\(label), \(value)" : "\(label), \(value), tap to change") {
            RowFrame(minHeight: 52) {
                Text(label).cindy(.body).frame(maxWidth: .infinity, alignment: .leading)
                Text(value).cindy(.headline)
                if action != nil { RowChevron() }
            }
        }
    }
}

/// A word set in the heaviest weight and a text style's size, which `cindy(_:)` cannot do because
/// the weight belongs to the style.
private struct ExtraBoldText: View {
    let text: String
    @ScaledMetric(relativeTo: .headline) private var size: CGFloat = CindyType.headline.size

    var body: some View {
        Text(text)
            .font(Manrope.font(.extrabold, size: size))
            .tracking(CindyType.headline.tracking * size)
            .foregroundStyle(Palette.label)
    }
}

/// A leaderboard row: rank, who, when, and the score in metric type.
///
/// `action`, when given, opens the session the row stands for: the athlete's own rows, never the
/// benchmark's, which is not a session anyone can reopen. It gets a chevron and the button role.
struct RankRow: View {
    let rank: String
    let name: String
    let detail: String
    let score: String
    let mine: Bool
    let best: Bool
    var action: (() -> Void)? = nil

    var body: some View {
        RowButton(action: action, label: "\(rank), \(name), \(score), \(detail)") {
            RowFrame(minHeight: 64) {
                Text(rank).cindy(.callout, colour: Palette.labelTertiary)
                    .frame(width: 22, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        if mine { ExtraBoldText(text: name) } else { Text(name).cindy(.headline) }
                        if best { BadgeLabel("BEST") }
                    }
                    Text(detail).cindy(.footnote)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(score).cindy(.metricS, colour: mine ? Palette.label : Palette.labelSecondary)
                    .padding(.leading, 10)
                if action != nil { RowChevron() }
            }
            // The athlete's own rows sit on a slightly brighter film; the benchmark recedes.
            .background(mine ? Palette.surfaceGlass : Color.clear)
        }
    }
}

/// A trophy: a disc with its place in it. First is the earned colour; second and third step down
/// the label ramp rather than borrowing metal colours the palette does not have.
struct Medal: View {
    let rank: Int

    var body: some View {
        Text("\(rank)")
            .font(Manrope.font(.bold, size: 12))
            .foregroundStyle(Palette.onPrimary)
            .frame(width: 28, height: 28)
            .background(Circle().fill(fill))
            .accessibilityHidden(true)
    }

    private var fill: Color {
        switch rank {
        case 1: return Palette.achievement
        case 2: return Palette.label
        default: return Palette.labelSecondary
        }
    }
}

/// A trophy row: medal, what it is and when, and the figure.
struct PeakRow: View {
    let rank: Int
    let title: String
    let detail: String
    let value: String

    var body: some View {
        RowFrame(minHeight: 60) {
            Medal(rank: rank)
            RowText(title: title, detail: detail).padding(.leading, 14)
            Text(value).cindy(.metricS).padding(.leading, 10)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value), \(detail)")
    }
}

/// A small filled marker. Reserved for facts, never decoration.
struct BadgeLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Manrope.font(.bold, size: 9.5))
            .tracking(CindyType.eyebrow.tracking * 9.5)
            .foregroundStyle(Palette.onPrimary)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Palette.primaryFill, in: RoundedRectangle(cornerRadius: Palette.radiusControl))
    }
}

/// A badge's disc, with its face in it.
///
/// Earned, it is the colour of everything else the athlete has earned. Locked, it is a ring with
/// the face dimmed, so that what is still to do reads as quiet rather than as broken. The faces run
/// to four characters, so the type steps down for those to keep them inside the circle.
struct BadgeDisc: View {
    let face: String
    let earned: Bool
    var size: CGFloat = 44

    var body: some View {
        Text(face)
            .font(Manrope.font(.extrabold, size: size * (face.count >= 4 ? 0.27 : 0.32)))
            .foregroundStyle(earned ? Palette.onPrimary : Palette.labelTertiary)
            .frame(width: size, height: size)
            .background {
                if earned {
                    Circle().fill(Palette.achievement)
                } else {
                    Circle().strokeBorder(Palette.hairlineStrong, lineWidth: 1)
                }
            }
            .accessibilityHidden(true)
    }
}

/// The row that opens the athlete's profile: their avatar, what to call them, what they have
/// earned, and a chevron.
///
/// Its own row rather than a `NavRow` with a picture bolted on, because the avatar changes the
/// row's shape: it is taller, and the picture sits where the text would have started.
struct AvatarRow: View {
    let photo: UIImage?
    let name: String?
    let title: String
    let value: String
    let action: () -> Void

    var body: some View {
        RowButton(action: action, label: "\(title), \(value)") {
            RowFrame(minHeight: 72) {
                AvatarView(photo: photo, name: name)
                    .frame(width: 44, height: 44)
                    .padding(.trailing, 14)
                RowText(title: title, detail: value)
                RowChevron()
            }
        }
    }
}

/// A row of options in a segmented choice (metric, range, category). `onSelect` fires only when
/// the choice actually changes.
///
/// The pill is 36 points but the target is 48: the padding keeps the row light without shrinking
/// what a wet thumb has to hit.
struct ChipRow: View {
    let options: [String]
    let selected: Int
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, text in
                let isSelected = index == selected
                Button {
                    if !isSelected { onSelect(index) }
                } label: {
                    Text(text)
                        .font(Manrope.font(.semibold, size: 13))
                        .tracking(CindyType.buttonSmall.tracking * 13)
                        .foregroundStyle(isSelected ? Palette.onPrimary : Palette.labelSecondary)
                        .padding(.horizontal, 14)
                        .frame(minWidth: 48, minHeight: 36)
                        .background(pill(isSelected))
                        .frame(minHeight: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isSelected ? "\(text), selected" : text)
                .accessibilityAddTraits(.isButton)
            }
        }
    }

    @ViewBuilder private func pill(_ isSelected: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18)
        if isSelected {
            shape.fill(Palette.primaryFill)
        } else {
            shape.fill(Palette.surfaceGlassRaised)
                .overlay(shape.stroke(Palette.hairline, lineWidth: Palette.hairlineWidth))
        }
    }
}

/// The row of actions every secondary screen ends with, in the thumb's reach.
struct ActionBar<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 10, content: content)
            .padding(.top, 22)
    }
}
