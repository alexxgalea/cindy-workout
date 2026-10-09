import Foundation

/// The athlete: a name, a photo, and the badges their sessions have earned. Port of
/// `AccountActivity`'s `render`.
///
/// There is no account, on purpose. Nothing here is signed in to or sent anywhere: the name and the
/// photo are kept on this phone like the records are. The badges are not stored: they are worked out
/// from the recorded sessions every time the screen is drawn, so this screen cannot disagree with
/// the record board, and clearing the records clears them with it. The name and the photo are the
/// athlete's rather than the records', and are not cleared by that.
public struct AccountHeader: Equatable, Sendable {
    public let name: String?
    public let hasPhoto: Bool
    /// The name, or the invitation to give one.
    public let title: String
    /// What a screen reader says for the name: it does not look like a button, so it says it is one.
    public let nameSpoken: String
    public let photoSpoken: String
    /// "Training since 2 Mar 2026 · 1 session", or that the badges start with the first session.
    public let trainingLine: String
}

/// One badge: its disc, its name, and, while it is still to be earned, how far along it is.
public struct BadgeTile: Equatable, Sendable {
    public let badge: Badge
    public let face: String
    public let title: String
    public let earned: Bool
    public let progress: String?
    /// The tile is a single control, so a screen reader hears one sentence for it.
    public let spoken: String
    public let sheet: BadgeSheet
}

/// The sheet a tile opens.
public struct BadgeSheet: Equatable, Sendable {
    public let title: String
    public let requirement: String
    public let status: String
    public let earned: Bool
}

public struct BadgeFamilySection: Equatable, Sendable {
    public let heading: String
    public let tiles: [BadgeTile]
}

public struct AccountPage: Equatable, Sendable {
    public let header: AccountHeader
    /// "BADGES · 4 OF 26".
    public let badgesTitle: String
    public let families: [BadgeFamilySection]

    /// Three to a row, which on a narrow phone leaves each tile room for a two-line title.
    public static let columns = 3
}

public enum AccountBuilder {

    public static func build(profile: Profile, hasPhoto: Bool, attempts: [Attempt], zone: Zone,
                             firstDayOfWeek: DayOfWeek, today: LocalDate) -> AccountPage {
        let earned = Dictionary(uniqueKeysWithValues:
            Badges.earned(attempts, zone: zone, firstDayOfWeek: firstDayOfWeek).map { ($0.badge, $0) })
        let name = profile.displayName

        let header = AccountHeader(
            name: name, hasPhoto: hasPhoto, title: name ?? "Add your name",
            nameSpoken: name.map { "Your name, \($0), tap to change" } ?? "Add your name",
            photoSpoken: PhotoSheet.spoken(hasPhoto: hasPhoto),
            trainingLine: Badges.trainingLine(attempts, zone: zone))

        let families = BadgeFamily.allCases.map { family in
            BadgeFamilySection(
                heading: family.label.uppercased(),
                tiles: Badge.allCases.filter { $0.family == family }.map { badge in
                    let won = earned[badge]
                    let progress = won == nil
                        ? Badges.progress(badge, attempts, today: today, zone: zone, firstDayOfWeek: firstDayOfWeek) : nil
                    return BadgeTile(
                        badge: badge, face: badge.face, title: badge.title, earned: won != nil,
                        progress: progress?.label,
                        spoken: Badges.description(badge, won, progress, zone: zone),
                        sheet: BadgeSheet(title: badge.title, requirement: badge.requirement,
                                          status: Badges.status(won, progress, zone: zone), earned: won != nil))
                })
        }
        return AccountPage(header: header, badgesTitle: "BADGES · \(earned.count) OF \(Badge.allCases.count)",
                           families: families)
    }
}

/// The athlete's photo: a small square copy in the app's own files, not a pointer into their library.
///
/// A pointer would not last, and a picture the athlete later deletes from their camera roll should
/// not vanish from their profile. A copy also lets the file be cut to size: the original is twelve
/// megapixels and may carry a location, and neither belongs in a backup. What to do with the picture
/// is decided in `Avatar`; this keeps the file. Port of `AvatarStore`'s file handling.
public struct AvatarFiles {

    public static let fileName = "avatar.jpg"

    private let directory: URL

    public init(directory: URL) { self.directory = directory }

    /// The app's own files, where the athlete's backup finds them.
    public static func standard() -> AvatarFiles {
        AvatarFiles(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0])
    }

    private var file: URL { directory.appendingPathComponent(Self.fileName) }
    private var partial: URL { directory.appendingPathComponent(Self.fileName + ".partial") }

    /// Whether there is a file, not whether it draws: a photo that cannot be read is still one the
    /// athlete can remove.
    public var exists: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }

    /// The stored photo's bytes, or nil when there is none.
    public func load() -> Data? { exists ? try? Data(contentsOf: file) : nil }

    /// Removes the photo. True when there is none afterwards. A half-written copy goes with it:
    /// the files directory is what the backup carries, and a stray partial would be carried too.
    @discardableResult
    public func clear() -> Bool {
        try? FileManager.default.removeItem(at: partial)
        if !FileManager.default.fileExists(atPath: file.path) { return true }
        try? FileManager.default.removeItem(at: file)
        return !FileManager.default.fileExists(atPath: file.path)
    }

    /// Writes `jpeg` beside the stored photo and moves it into place only once it is whole, so a
    /// picture that fails half way cannot leave a corrupt file where the athlete's photo was.
    public func store(_ jpeg: Data) -> Bool {
        defer { try? FileManager.default.removeItem(at: partial) }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try jpeg.write(to: partial)
            // rename(2) puts the new file over the old one in one step, or leaves the old one alone.
            return rename(partial.path, file.path) == 0
        } catch {
            return false
        }
    }
}
