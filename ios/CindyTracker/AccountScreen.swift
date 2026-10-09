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
    @State private var choosingPhoto = false
    @State private var pickingPhoto = false
    @State private var picked: PhotosPickerItem?
    @State private var naming = false
    @State private var badge: BadgeSheet?
    @Environment(\.dismiss) private var dismiss

    init(profile: Profile) {
        _vm = StateObject(wrappedValue: AccountViewModel(profile: profile))
    }

    var body: some View {
        let page = vm.page
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header(page.header)
                Text(page.badgesTitle).font(.system(size: 12, weight: .bold)).foregroundStyle(Color.dim)
                    .padding(.top, 10).padding(.leading, 4).accessibilityAddTraits(.isHeader)
                ForEach(page.families, id: \.heading) { family in
                    Text(family.heading).font(.system(size: 12, weight: .bold)).foregroundStyle(Color.dim)
                        .padding(.top, 14).padding(.leading, 4).accessibilityAddTraits(.isHeader)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0, alignment: .top),
                                             count: AccountPage.columns), spacing: 0) {
                        ForEach(family.tiles, id: \.badge) { tile in
                            Button { badge = tile.sheet } label: { tileView(tile) }
                                .buttonStyle(.plain)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(tile.spoken)
                                .accessibilityAddTraits(.isButton)
                        }
                    }
                    .padding(6)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                }
                Button("DONE") { dismiss() }.buttonStyle(PrimaryButton()).padding(.top, 16)
            }
            .padding(20)
        }
        .background(Color.appBackground)
        .overlay(alignment: .bottom) {
            if let toast = vm.toast {
                Text(toast).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).chip().padding(.bottom, 90)
            }
        }
        .onAppear { vm.refresh() }
        .photosPicker(isPresented: $pickingPhoto, selection: $picked, matching: .images)
        .onChange(of: picked) { _, item in
            if let item { vm.importPhoto(item) }
            picked = nil
        }
        .sheet(isPresented: $naming) { NameSheet(profile: vm.profile, onSaved: { vm.refresh() }) }
        .sheet(item: $badge) { sheet in BadgeSheetView(sheet: sheet) }
        .confirmationDialog(PhotoSheet.title, isPresented: $choosingPhoto, titleVisibility: .visible) {
            Button("CHOOSE PHOTO") { pickingPhoto = true }
            if vm.page.header.hasPhoto { Button("REMOVE", role: .destructive) { vm.removePhoto() } }
            Button("CANCEL", role: .cancel) {}
        } message: {
            Text(PhotoSheet.subtitle)
        }
    }

    private func header(_ header: AccountHeader) -> some View {
        VStack(spacing: 4) {
            Button { choosingPhoto = true } label: {
                AvatarView(photo: vm.photo, name: header.name).frame(width: 88, height: 88)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(header.photoSpoken)
            .accessibilityAddTraits(.isButton)

            Button { naming = true } label: {
                Text(header.title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(header.name == nil ? Ink.secondary : Color.white)
                    .frame(minHeight: 48)
                    .padding(.horizontal, 12)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(header.nameSpoken)
            .accessibilityAddTraits(.isButton)

            Text(header.trainingLine).font(.system(size: 12)).foregroundStyle(Color.dim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22).padding(.horizontal, 20)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    private func tileView(_ tile: BadgeTile) -> some View {
        VStack(spacing: 2) {
            Text(tile.face)
                .font(.system(size: tile.face.count >= 4 ? 12 : 14, weight: .heavy))
                .foregroundStyle(tile.earned ? Color.black : Ink.tertiary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(tile.earned ? Ink.achievement : Color.clear))
                .overlay(Circle().strokeBorder(tile.earned ? Color.clear : Color.white.opacity(0.13), lineWidth: 1))
            Text(tile.title).font(.system(size: 11)).multilineTextAlignment(.center).lineLimit(2)
                .foregroundStyle(tile.earned ? Color.white : Ink.secondary).padding(.top, 6)
            if let progress = tile.progress {
                Text(progress).font(.system(size: 11)).multilineTextAlignment(.center).lineLimit(2)
                    .foregroundStyle(Color.dim)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4).padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

extension BadgeSheet: Identifiable {
    public var id: String { title }
}

/// A badge: what it asks for, and when it was earned or how far along it is.
struct BadgeSheetView: View {
    let sheet: BadgeSheet
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(sheet.title).font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                Text(sheet.requirement).font(.system(size: 14)).foregroundStyle(Color.dim)
            }
            HStack(spacing: 16) {
                Circle().fill(sheet.earned ? Ink.achievement : Color.clear)
                    .overlay(Circle().strokeBorder(sheet.earned ? Color.clear : Color.white.opacity(0.13), lineWidth: 1))
                    .frame(width: 56, height: 56)
                    .accessibilityHidden(true)
                Text(sheet.status).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
            }
            Spacer()
            Button("DONE") { dismiss() }.buttonStyle(PrimaryButton())
        }
        .padding(20)
        .background(Color.appBackground)
        .presentationDetents([.medium])
    }
}
