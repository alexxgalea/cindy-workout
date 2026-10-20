import SwiftUI
import CindyCore

/// The heart-rate block: the three figures, the time in each zone, the hardest round and the verdict
/// as one group of rows, as `ResultsActivity.kt`'s `renderHeartRate` lays them out. The zone bar is
/// touched through the model in CindyCore; the rows under it follow the zone it selects.
struct HeartSection: View {
    @ObservedObject var vm: ResultsViewModel
    let heart: HeartCard
    let onInviteAge: () -> Void

    private enum Item: Hashable { case figures, zones, invite, hardest, verdict }

    private var items: [Item] {
        var items: [Item] = [.figures]
        if heart.zones != nil { items.append(.zones) } else if heart.invitesAge { items.append(.invite) }
        if heart.hardestRound != nil { items.append(.hardest) }
        if heart.verdict != nil { items.append(.verdict) }
        return items
    }

    var body: some View {
        InsetGroup(items, id: \.self, row: row) {
            Text(heart.footnote).smallPrint()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18).padding(.bottom, 14)
        }
    }

    @ViewBuilder private func row(_ item: Item) -> some View {
        switch item {
        case .figures: HeartFigures(figures: heart.figures)
        case .zones: if let rows = heart.zones { zoneBlock(rows) }
        case .invite:
            NavRow(title: ResultsWords.zonesInviteTitle, value: ResultsWords.zonesInviteValue, action: onInviteAge)
        case .hardest:
            if let hardest = heart.hardestRound {
                HardestRoundRow(value: hardest,
                                spoken: heart.hardestRoundSpoken ?? "\(ResultsWords.hardestRound), \(hardest)")
            }
        case .verdict:
            if let verdict = heart.verdict {
                Text(verdict).cindy(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18).padding(.vertical, 14)
            }
        }
    }

    private func zoneBlock(_ rows: [HeartCard.ZoneRow]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionEyebrow(ResultsWords.timeInZone).padding(.horizontal, 18).padding(.top, 14)
            ZoneBarView(vm: vm).padding(.horizontal, 18).padding(.top, 6)
            ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                ZoneRowView(row: row, alpha: ZoneBarModel.alpha[i], held: vm.zoneSelected == i,
                            dimmed: vm.zoneSelected != nil && vm.zoneSelected != i)
            }
        }
    }
}

/// A time in a zone: the zone's swatch, its name, how long and its range. The figures scale with the
/// text size as the name does.
private struct ZoneRowView: View {
    let row: HeartCard.ZoneRow
    let alpha: Double
    let held: Bool
    let dimmed: Bool
    @ScaledMetric(relativeTo: .body) private var timeSize: CGFloat = 15
    @ScaledMetric(relativeTo: .footnote) private var rangeSize: CGFloat = 13

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(Palette.heart.opacity(alpha)).frame(width: 10, height: 10)
            Text(row.name).cindy(.body, colour: Palette.label)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.time).font(Manrope.font(.bold, size: timeSize).monospacedDigit())
                .foregroundStyle(Palette.label)
                .lineLimit(1).minimumScaleFactor(0.5)
                .frame(minWidth: 48, alignment: .trailing)
            Text(row.range).font(Manrope.font(.regular, size: rangeSize).monospacedDigit())
                .foregroundStyle(Palette.labelTertiary)
                .lineLimit(1).minimumScaleFactor(0.5)
                .frame(minWidth: 98, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 40)
        .background(held ? Palette.surfaceGlassRaised : Color.clear)
        .opacity(dimmed ? ZoneBarModel.dim : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.spoken)
    }
}

/// The hardest round, as a label and its figure.
private struct HardestRoundRow: View {
    let value: String
    let spoken: String
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 16

    var body: some View {
        HStack(spacing: 0) {
            Text(ResultsWords.hardestRound).cindy(.body).frame(maxWidth: .infinity, alignment: .leading)
            Text(value).font(Manrope.font(.bold, size: size).monospacedDigit())
                .foregroundStyle(Palette.label)
        }
        .padding(.leading, 18).padding(.trailing, 16).padding(.vertical, 14)
        .frame(minHeight: 52)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }
}

/// Covered, average, peak: a column each, the label over the figure over its unit.
private struct HeartFigures: View {
    let figures: [HeartCard.Figure]
    @ScaledMetric(relativeTo: .title) private var size: CGFloat = 28

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ForEach(Array(figures.enumerated()), id: \.offset) { _, f in
                VStack(alignment: .leading, spacing: 0) {
                    Text(f.label).cindy(.eyebrow)
                    Text(f.value).font(Manrope.font(.bold, size: size).monospacedDigit())
                        .foregroundStyle(Palette.label)
                        .lineLimit(1).minimumScaleFactor(0.4)
                        .padding(.top, 4)
                    Text(f.unit).cindy(.footnote)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(f.spoken)
            }
        }
        .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 14)
    }
}
