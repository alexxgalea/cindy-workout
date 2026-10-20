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
        VStack(alignment: .leading, spacing: 0) {
            Text(ProgressWords.title).cindy(.title).accessibilityAddTraits(.isHeader)
            Text(ProgressWords.subtitle).cindy(.body).padding(.top, 5)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HabitCard(hero: page.hero, today: page.calendar?.today)
                    if let week = page.thisWeek { ThisWeekCard(week: week) }
                    if let card = page.progress { ProgressChartCard(card: card, vm: vm) }
                    if let peaks = page.peaks { PeaksGroup(peaks: peaks) }
                    if let calendar = page.calendar { CalendarCard(section: calendar, vm: vm) }
                    LeaderboardGroup(board: page.leaderboard, onOpen: { vm.open(session: $0) })
                }
            }
            .padding(.top, 24)

            // Sessions are deleted one at a time, from their own page: there is deliberately no
            // button here that takes the whole board at once. The bar is pinned, outside the scroll.
            ActionBar {
                ForEach(page.actions, id: \.rawValue) { action in
                    switch action {
                    case .done: Button(action.rawValue) { dismiss() }.buttonStyle(CindyPrimaryButtonStyle())
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
        .background(Palette.background.ignoresSafeArea())
        .overlay(alignment: .bottom) {
            if let toast = vm.toast { CindyToast(text: toast).padding(.bottom, 90) }
        }
        // A trained day lists its sessions, oldest first; a row closes the sheet and opens its session.
        .cindySheet(isPresented: Binding(get: { vm.day != nil }, set: { if !$0 { vm.day = nil } }),
                    title: vm.day?.title ?? "",
                    subtitle: vm.day?.subtitle,
                    primary: SheetButton(title: "DONE") {}) {
            if let sheet = vm.day {
                InsetGroup(sheet.rows, id: \.opens) { row in
                    NavRow(title: row.time, value: row.value) { vm.open(session: row.opens) }
                        .accessibilityIdentifier("daySession")
                }
                .padding(.top, 16)
            }
        }
        // Whichever session was opened from here can discard itself, so the page is built again from
        // the board when that page goes, and only if the board changed.
        .fullScreenCover(item: $vm.reopened, onDismiss: { vm.boardMayHaveChanged() }) { request in
            ResultsView(request, onDiscarded: { vm.discarded() })
        }
    }
}
