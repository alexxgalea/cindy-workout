import SwiftUI
import UniformTypeIdentifiers
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

    /// What this build can open. The Strava row is absent, not greyed out, in a build with no credentials:
    /// `MenuInput.strava` is nil there.
    static let shown: Set<MenuRowID> = [.movements, .progress, .reminder, .bodyWeight, .voice, .music, .heartRate, .strava, .help]

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
            is24Hour: !format.contains("a"), hasPhoto: files.exists, workoutLive: workoutLive,
            notificationsAllowed: ReminderCenter.shared.access != .refused,
            trackName: { MusicLibrary.displayName($0) }, strava: StravaCenter.shared.menuStatus, shown: shown))
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
    @State private var panel: PanelSheet?
    @State private var pickingTrack = false
    @State private var path: [Destination] = []

    /// The sheets that are Cindy sheets, in the one presenter below. The rest are still the system's.
    private enum PanelSheet: Identifiable {
        case movements, bodyWeight, voice, music
        var id: Int { hashValue }
    }

    private enum Sheet: Identifiable {
        case reminder, heartRate, stravaConsent, stravaConnected
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
            VStack(alignment: .leading, spacing: 0) {
                Text(MenuWords.menuTitle).cindy(.title).accessibilityAddTraits(.isHeader)
                Text(MenuWords.menuSubtitle).cindy(.body).padding(.top, 5)
                ScrollView { content }.padding(.top, 24)
                // Pinned below the scroll, so it does not go with the rows.
                ActionBar {
                    Button("DONE") { dismiss() }.buttonStyle(CindyPrimaryButtonStyle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
            .background(Palette.background.ignoresSafeArea())
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
        // The grant, the switch and the uploads change under this screen (the redirect, a refresh), and what
        // Strava has to say about it is said here.
        .onReceive(StravaCenter.shared.$revision) { _ in vm.refresh() }
        .onReceive(StravaCenter.shared.$notice.compactMap { $0 }) { vm.show($0.text) }
        .cindySheet(item: $panel, onDismiss: { workout.applyProfile(); vm.refresh() }) { which in
            switch which {
            case .movements:
                MovementsSheet(profile: vm.profile) { _ in vm.show(MenuBuilder.movementsSubtitle(vm.profile)) }
            case .bodyWeight:
                BodyWeightSheet(profile: vm.profile) { vm.refresh() }
            case .voice:
                VoiceSheet(speaker: workout.speaker, profile: vm.profile,
                           save: { $0.save(to: vm.profile) }, cancel: { workout.restoreLanguage() })
            case .music:
                MusicSheet(profile: vm.profile, choose: { pickingTrack = true }, show: { vm.show($0) },
                           onChanged: { vm.refresh() })
            }
        }
        // The system's picker, held here because the sheet that asked for it is gone by the time it opens.
        .fileImporter(isPresented: $pickingTrack, allowedContentTypes: [.audio]) { result in
            if case .success(let url) = result { adoptTrack(url) }
        }
        .sheet(item: $sheet, onDismiss: { workout.applyProfile(); vm.refresh() }) { which in
            sheetView(which)
        }
        // Above the sheets: a sheet is where the athlete is looking when a toast has something to say.
        .overlay(alignment: sheetIsUp ? .top : .bottom) { toastView }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            profileGroup.padding(.bottom, 12)
            rowsGroup
            footnote
        }
    }

    private var profileGroup: some View {
        InsetGroup([vm.page.card], id: \.title) { card in
            AvatarRow(photo: vm.photo, name: card.name, title: card.title, value: card.value) {
                path.append(.account)
            }
        }
        .dealt(0, settled: settled, still: reduceMotion)
    }

    private var rowsGroup: some View {
        InsetGroup(vm.page.rows, id: \.id) { row in
            NavRow(title: row.title, value: row.subtitle, spoken: row.spoken) { open(row.id) }
                .dealt((vm.page.rows.firstIndex { $0.id == row.id } ?? 0) + 1, settled: settled, still: reduceMotion)
        }
    }

    /// Said here rather than only when the row is tapped, because it explains why the row will
    /// refuse rather than reporting the refusal after the fact.
    @ViewBuilder private var footnote: some View {
        if let note = vm.page.footnote {
            Text(note)
                .cindy(.footnote)
                .padding(.horizontal, 4)
                .padding(.top, 14)
        }
    }

    private var sheetIsUp: Bool { panel != nil || sheet != nil }

    @ViewBuilder private var toastView: some View {
        if let toast = vm.toast {
            CindyToast(text: toast).padding(sheetIsUp ? .top : .bottom, sheetIsUp ? 60 : 90)
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
        case .reminder:
            ReminderSheet(profile: vm.profile, show: { vm.show($0) }, onChanged: { vm.refresh() })
        case .heartRate:
            HeartRateSheet(profile: vm.profile, onChanged: { vm.refresh() })
        case .stravaConsent:
            StravaConsentSheet(origin: .menu)
        case .stravaConnected:
            StravaConnectedSheet(show: { vm.show($0) }, onChanged: { vm.refresh() })
        }
    }

    /// Takes the long-lived grant that lets the track survive a restart, then remembers it. The
    /// track is not loaded here: the workout picks it up when the menu closes, and clears the choice
    /// itself if it turns out not to play.
    private func adoptTrack(_ url: URL) {
        guard let stored = MusicLibrary.store(url) else {
            vm.show(MusicFlow.lapsedText)
            return
        }
        vm.profile.musicTrack = stored
        vm.profile.musicOn = true
        vm.show(MusicFlow.adoptedText(name: MusicLibrary.displayName(stored)))
        vm.refresh()
    }

    private func open(_ id: MenuRowID) {
        switch id {
        case .movements:
            if vm.page.movementsRefused { vm.show(MovementsForm.refusedWhileLive) } else { panel = .movements }
        case .progress: path.append(.progress)
        case .help: path.append(.help)
        case .bodyWeight: panel = .bodyWeight
        case .voice: panel = .voice
        case .music: panel = .music
        case .reminder: sheet = .reminder
        case .heartRate: sheet = .heartRate
        case .strava:
            sheet = StravaMenu.tap(grant: StravaCenter.shared.tokens.grant) == .askConsent ? .stravaConsent : .stravaConnected
        }
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
