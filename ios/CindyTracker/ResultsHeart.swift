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
            Text(heart.footnote).cindy(.footnote)
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
                HStack(spacing: 0) {
                    Text(ResultsWords.hardestRound).cindy(.body).frame(maxWidth: .infinity, alignment: .leading)
                    Text(hardest).font(Manrope.font(.bold, size: 16).monospacedDigit())
                        .foregroundStyle(Palette.label)
                }
                .padding(.leading, 18).padding(.trailing, 16).padding(.vertical, 14)
                .frame(minHeight: 52)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(heart.hardestRoundSpoken ?? "\(ResultsWords.hardestRound), \(hardest)")
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
                HStack(spacing: 10) {
                    Circle().fill(Palette.heart.opacity(ZoneBarModel.alpha[i])).frame(width: 10, height: 10)
                    Text(row.name).cindy(.body, colour: Palette.label)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(row.time).font(Manrope.font(.bold, size: 15).monospacedDigit())
                        .foregroundStyle(Palette.label)
                        .frame(width: 48, alignment: .trailing)
                    Text(row.range).font(Manrope.font(.regular, size: 13).monospacedDigit())
                        .foregroundStyle(Palette.labelTertiary)
                        .frame(width: 98, alignment: .trailing)
                }
                .padding(.horizontal, 18)
                .frame(minHeight: 40)
                .background(vm.zoneSelected == i ? Palette.surfaceGlassRaised : Color.clear)
                .opacity(vm.zoneSelected == nil || vm.zoneSelected == i ? 1 : ZoneBarModel.dim)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(row.spoken)
            }
        }
    }
}

/// Average, peak and the like: a column each, the figure large and its unit beside it.
private struct HeartFigures: View {
    let figures: [HeartCard.Figure]
    @ScaledMetric(relativeTo: .title) private var size: CGFloat = 28

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ForEach(Array(figures.enumerated()), id: \.offset) { _, f in
                VStack(alignment: .leading, spacing: 2) {
                    Text(f.label).cindy(.eyebrow)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(f.value).font(Manrope.font(.bold, size: size).monospacedDigit())
                            .foregroundStyle(Palette.label)
                            .lineLimit(1).minimumScaleFactor(0.5)
                        Text(f.unit).cindy(.footnote)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(f.spoken)
            }
        }
        .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 14)
    }
}
