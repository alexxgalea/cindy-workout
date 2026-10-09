import SwiftUI
import CindyCore

/// Everything the athlete does not need while they are on the bar. `MenuBuilder` decides which rows
/// there are and what each says; this draws them and opens what they open.
@MainActor
final class MenuViewModel: ObservableObject {

    let profile: Profile
    private let files = AvatarFiles.standard()
    private let store = RecordStore()

    @Published private(set) var page: MenuPage
    @Published private(set) var photo: UIImage?
    @Published private(set) var toast: String?
    private let workoutLive: Bool

    /// What this build can open. The rest arrive with their phases: heart rate (P15), music (P17),
    /// the daily reminder (P18) and Strava (P20).
    static let shown: Set<MenuRowID> = [.movements, .progress, .bodyWeight, .voice, .help]

    init(profile: Profile, workoutLive: Bool) {
        self.profile = profile
        self.workoutLive = workoutLive
        page = Self.build(profile, workoutLive, files, store)
        photo = files.load().flatMap(UIImage.init(data:))
    }

    private static func build(_ profile: Profile, _ workoutLive: Bool, _ files: AvatarFiles, _ store: RecordStore) -> MenuPage {
        let zone = Zone(TimeZone.current.identifier)
        let today = zone.localDate(epochMs: Int64(Date().timeIntervalSince1970 * 1000))
        let first = DayOfWeek(rawValue: (Calendar.current.firstWeekday + 5) % 7 + 1) ?? .monday
        let format = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? ""
        return MenuBuilder.build(MenuInput(
            profile: profile, attempts: store.all(), zone: zone, firstDayOfWeek: first, today: today,
            is24Hour: !format.contains("a"), hasPhoto: files.exists, workoutLive: workoutLive, shown: shown))
    }

    /// Rebuilt rather than patched, because a row's subtitle is derived from state a sheet may just
    /// have changed.
    func refresh() {
        photo = files.load().flatMap(UIImage.init(data:))
        page = Self.build(profile, workoutLive, files, store)
    }

    func show(_ text: String) {
        toast = text
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if self?.toast == text { self?.toast = nil }
        }
    }
}

struct MenuScreen: View {
    let workout: WorkoutViewModel
    /// Closes the menu: Help's pages, taken again, end on the camera screen with the tour next.
    let onReturnToCamera: () -> Void
    @StateObject private var vm: MenuViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settled = false
    @State private var sheet: Sheet?
    @State private var path: [Destination] = []

    private enum Sheet: Identifiable {
        case movements, bodyWeight, voice
        var id: Int { hashValue }
    }

    private enum Destination: Hashable { case account, progress, help }

    init(workout: WorkoutViewModel, workoutLive: Bool, onReturnToCamera: @escaping () -> Void) {
        self.workout = workout
        self.onReturnToCamera = onReturnToCamera
        _vm = StateObject(wrappedValue: MenuViewModel(profile: workout.settings, workoutLive: workoutLive))
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView { content }
                .background(Color.appBackground)
                .overlay(alignment: .bottom) { toastView }
                .navigationBarHidden(true)
                .navigationDestination(for: Destination.self) { destination in
                    destinationView(destination)
                }
        }
        .onAppear {
            vm.refresh()
            // Dealt in once, on the way in. Drawn again after a sheet, a list that re-deals itself
            // each time you change a volume would be a screen that cannot keep still.
            if !settled { settled = true }
        }
        .onChange(of: path) { _, _ in vm.refresh() }
        .sheet(item: $sheet, onDismiss: { workout.applyProfile(); vm.refresh() }) { which in
            sheetView(which)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            profileButton
            rowsList
            footnote
            Button("DONE") { dismiss() }.buttonStyle(PrimaryButton()).padding(.top, 16)
        }
        .padding(20)
    }

    private var profileButton: some View {
        Button { path.append(.account) } label: { profileCard(vm.page.card) }
            .buttonStyle(.plain)
            .accessibilityLabel(vm.page.card.spoken)
            .accessibilityAddTraits(.isButton)
            .dealt(0, settled: settled, still: reduceMotion)
    }

    private var rowsList: some View {
        VStack(spacing: 0) {
            ForEach(Array(vm.page.rows.enumerated()), id: \.element.id) { i, row in
                menuRow(i, row)
            }
        }
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    private func menuRow(_ index: Int, _ row: MenuRow) -> some View {
        Button { open(row.id) } label: { rowView(row) }
            .buttonStyle(.plain)
            .accessibilityLabel(row.spoken)
            .accessibilityAddTraits(.isButton)
            .dealt(index + 1, settled: settled, still: reduceMotion)
    }

    /// Said here rather than only when the row is tapped, because it explains why the row will
    /// refuse rather than reporting the refusal after the fact.
    @ViewBuilder private var footnote: some View {
        if let note = vm.page.footnote {
            Text(note)
                .font(.system(size: 12))
                .foregroundStyle(Color.dim)
                .padding(.horizontal, 4)
                .padding(.top, 14)
        }
    }

    @ViewBuilder private var toastView: some View {
        if let toast = vm.toast {
            Text(toast)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .chip()
                .padding(.bottom, 90)
        }
    }

    @ViewBuilder private func destinationView(_ destination: Destination) -> some View {
        switch destination {
        case .account: AccountScreen(profile: vm.profile)
        case .progress: ProgressScreen()
        case .help: HelpScreen(profile: vm.profile, onReturnToCamera: onReturnToCamera)
        }
    }

    @ViewBuilder private func sheetView(_ which: Sheet) -> some View {
        switch which {
        case .movements:
            MovementsSheet(profile: vm.profile) { _ in vm.show(MenuBuilder.movementsSubtitle(vm.profile)) }
        case .bodyWeight:
            BodyWeightSheet(profile: vm.profile) { vm.refresh() }
        case .voice:
            VoiceSheet(speaker: workout.speaker, profile: vm.profile,
                       save: { $0.save(to: vm.profile) }, cancel: { workout.restoreLanguage() })
        }
    }

    private func open(_ id: MenuRowID) {
        switch id {
        case .movements:
            if vm.page.movementsRefused { vm.show(MovementsForm.refusedWhileLive) } else { sheet = .movements }
        case .progress: path.append(.progress)
        case .help: path.append(.help)
        case .bodyWeight: sheet = .bodyWeight
        case .voice: sheet = .voice
        case .reminder, .heartRate, .strava, .music: break
        }
    }

    private func profileCard(_ card: MenuProfileCard) -> some View {
        HStack(spacing: 14) {
            AvatarView(photo: vm.photo, name: card.name).frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(card.title).font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                Text(card.value).font(.system(size: 13)).foregroundStyle(Color.dim)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Color.dim)
        }
        .padding(16)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    private func rowView(_ row: MenuRow) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                Text(row.subtitle).font(.system(size: 12)).foregroundStyle(Color.dim)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Color.dim)
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}

private extension View {
    /// Brings a card in after the ones before it, once: every card is dealt on one running count,
    /// the profile card first. The phone's reduced-motion setting skips it.
    func dealt(_ index: Int, settled: Bool, still: Bool) -> some View {
        self
            .opacity(settled || still ? 1 : 0)
            .offset(y: settled || still ? 0 : 14)
            .animation(still ? nil : .easeOut(duration: 0.24).delay(Double(MenuPage.delayMs(index)) / 1000), value: settled)
    }
}
