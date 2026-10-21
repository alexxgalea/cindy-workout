import PhotosUI
import SwiftUI
import CindyCore

/// The athlete's picture and name, kept on this phone, and the badges their sessions have earned.
@MainActor
final class AccountViewModel: ObservableObject {

    let profile: Profile
    private let files = AvatarFiles.standard()
    private let store = RecordStore()

    @Published private(set) var page: AccountPage
    @Published private(set) var photo: UIImage?
    @Published private(set) var toast: String?

    init(profile: Profile) {
        self.profile = profile
        page = Self.build(profile, files, store)
        photo = files.load().flatMap(UIImage.init(data:))
    }

    private static func build(_ profile: Profile, _ files: AvatarFiles, _ store: RecordStore) -> AccountPage {
        let zone = Zone(TimeZone.current.identifier)
        let today = zone.localDate(epochMs: Int64(Date().timeIntervalSince1970 * 1000))
        let first = DayOfWeek(rawValue: (Calendar.current.firstWeekday + 5) % 7 + 1) ?? .monday
        return AccountBuilder.build(profile: profile, hasPhoto: files.exists, attempts: store.all(), zone: zone,
                                    firstDayOfWeek: first, today: today)
    }

    /// Rebuilt rather than patched: a name, a photo or a badge sheet may just have changed it.
    func refresh() {
        photo = files.load().flatMap(UIImage.init(data:))
        page = Self.build(profile, files, store)
    }

    func removePhoto() {
        if !files.clear() { show(PhotoSheet.failedToRemove) }
        refresh()
    }

    /// Cuts the picked picture down off the main thread, which is where decoding a twelve megapixel
    /// photo does not belong, then keeps it.
    func importPhoto(_ picked: PhotosPickerItem) {
        Task {
            let data = try? await picked.loadTransferable(type: Data.self)
            let jpeg = await Task.detached(priority: .userInitiated) { data.flatMap(AvatarImporter.jpeg(from:)) }.value
            if let jpeg, files.store(jpeg) { refresh() } else { show(PhotoSheet.failedToUse) }
        }
    }

    private func show(_ text: String) {
        toast = text
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if self?.toast == text { self?.toast = nil }
        }
    }
}

struct AccountScreen: View {
    @StateObject private var vm: AccountViewModel
    @State private var pickingPhoto = false
    @State private var picked: PhotosPickerItem?
    @State private var sheet: AccountSheet?
    @Environment(\.dismiss) private var dismiss

    /// What the screen opens. A badge carries its tile, not only its sheet: the disc in the sheet
    /// carries the badge's face, as Android's does.
    private enum AccountSheet: Identifiable {
        case badge(BadgeTile), name, photo

        var id: String {
            switch self {
            case .badge(let tile): return "badge-\(tile.title)"
            case .name: return "name"
            case .photo: return "photo"
            }
        }
    }

    init(profile: Profile) {
        _vm = StateObject(wrappedValue: AccountViewModel(profile: profile))
    }

    var body: some View {
        let page = vm.page
        VStack(alignment: .leading, spacing: 0) {
            Text(MenuWords.youTitle).cindy(.title).accessibilityAddTraits(.isHeader)
            Text(MenuWords.youSubtitle).cindy(.body).padding(.top, 5)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header(page.header).padding(.bottom, 12)
                    SectionTitle(page.badgesTitle)
                    ForEach(page.families, id: \.heading) { family in
                        Text(family.heading).cindy(.eyebrow)
                            .padding(.leading, 4).padding(.top, 14).padding(.bottom, 8)
                            .accessibilityAddTraits(.isHeader)
                        grid(family).padding(.bottom, 4)
                    }
                }
            }
            .padding(.top, 24)
            // Pinned below the scroll, so it does not go with the badges.
            ActionBar {
                Button("DONE") { dismiss() }.buttonStyle(CindyPrimaryButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
        .background(Palette.background.ignoresSafeArea())
        // Pushed from the menu, this screen has its own title and DONE: the system's bar is not wanted.
        .navigationBarHidden(true)
        .overlay(alignment: .bottom) {
            if let toast = vm.toast { CindyToast(text: toast).padding(.bottom, 90) }
        }
        .onAppear { vm.refresh() }
        .photosPicker(isPresented: $pickingPhoto, selection: $picked, matching: .images)
        .onChange(of: picked) { _, item in
            if let item { vm.importPhoto(item) }
            picked = nil
        }
        // A badge says what it asks for and how far along it is. The name and the photo are asked for
        // here too. Closed any way but a button, each changes nothing.
        .cindySheet(item: $sheet) { which in
            switch which {
            case .badge(let tile):
                CindyPanel(title: tile.sheet.title, subtitle: tile.sheet.requirement,
                           primary: SheetButton(title: SheetWords.done) {}) {
                    HStack(spacing: 16) {
                        BadgeDisc(face: tile.face, earned: tile.earned, size: 56)
                        Text(tile.sheet.status).cindy(.headline, colour: Palette.label)
                    }
                    .padding(.top, 4)
                }
            case .name:
                NameSheet(profile: vm.profile, onSaved: { vm.refresh() })
            case .photo:
                PhotoChoiceSheet(hasPhoto: vm.page.header.hasPhoto,
                                 choose: { pickingPhoto = true }, remove: { vm.removePhoto() })
            }
        }
    }

    private func header(_ header: AccountHeader) -> some View {
        VStack(spacing: 0) {
            Button { sheet = .photo } label: {
                AvatarView(photo: vm.photo, name: header.name).frame(width: 88, height: 88)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(header.photoSpoken)
            .accessibilityAddTraits(.isButton)

            Button { sheet = .name } label: {
                Text(header.title)
                    .cindy(.title2, colour: header.name == nil ? Palette.labelSecondary : Palette.label)
                    .frame(minHeight: 48)
                    .padding(.horizontal, 12)
            }
            .buttonStyle(.plain)
            .padding(.top, 14)
            .accessibilityLabel(header.nameSpoken)
            .accessibilityAddTraits(.isButton)

            Text(header.trainingLine).cindy(.footnote)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 22).padding(.bottom, 20).padding(.horizontal, 20)
        .glassCard()
    }

    /// Three to a row, which leaves each tile room for a two-line title.
    private func grid(_ family: BadgeFamilySection) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0, alignment: .top),
                                 count: AccountPage.columns), spacing: 0) {
            ForEach(family.tiles, id: \.badge) { tile in
                Button { sheet = .badge(tile) } label: { tileView(tile) }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(tile.spoken)
                    .accessibilityAddTraits(.isButton)
            }
        }
        .padding(6)
        .glassCard()
    }

    private func tileView(_ tile: BadgeTile) -> some View {
        VStack(spacing: 0) {
            BadgeDisc(face: tile.face, earned: tile.earned, size: 44)
            Text(tile.title)
                .cindy(.footnote, colour: tile.earned ? Palette.label : Palette.labelSecondary)
                .multilineTextAlignment(.center).lineLimit(2)
                .padding(.top, 8)
            if let progress = tile.progress {
                Text(progress).cindy(.footnote).multilineTextAlignment(.center).lineLimit(2)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4).padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}
