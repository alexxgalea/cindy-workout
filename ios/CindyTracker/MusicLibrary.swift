import Foundation
import CindyCore

/// How a chosen track is remembered: the file picker hands over a URL that is good for this launch
/// only, and a security-scoped bookmark is what lets the app open the same file next time. It is
/// what Android's persistable URI permission is.
///
/// The bookmark is kept in the profile as text (`Profile.musicTrack`), which is all the menu and the
/// core ever need to know about it: whether there is one, and, through `displayName`, whether it
/// still opens.
enum MusicLibrary {

    /// The bookmark for a file the picker returned, or nil if the system would not make one.
    static func store(_ url: URL) -> String? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let data = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        return data?.base64EncodedString()
    }

    /// The file a bookmark points at now, or nil when it no longer resolves.
    static func resolve(_ stored: String) -> URL? {
        guard let data = Data(base64Encoded: stored) else { return nil }
        var stale = false
        return try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
    }

    /// What to call a track without playing it, or nil if it can no longer be opened. The menu names
    /// the chosen track in a row's subtitle and must not start a player to do it.
    static func displayName(_ stored: String) -> String? {
        guard let url = resolve(stored) else { return nil }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return MusicFlow.displayName(fileName: url.lastPathComponent)
    }
}
