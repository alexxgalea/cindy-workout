import Foundation

/// The licences of what Cindy is built on, and who gets the credit. Port of `Licences.kt`.
///
/// The SIL Open Font License asks for a copy of the licence to travel with the binary, so its full
/// text ships in the app and Help shows it. The credits live here, apart from the screen that draws
/// them, so a test can hold the two lists to each other: a credit cannot name a licence whose text
/// is not in the app, and a shipped text cannot go uncredited.
///
/// What differs from Android, and why: Android ships Apache-2.0 for MoveNet, LiteRT, AndroidX,
/// CameraX and Kotlin. None of those is in the iOS app. The joints are found by Apple's Vision and
/// the screens are drawn by Apple's frameworks, which come with iOS and carry no licence for Cindy
/// to pass on, so the credit says whose they are and the Apache text does not ship. The font is the
/// same file, and so is its licence.
///
/// The texts are the licences' own, unedited, apart from the copyright block at the head of
/// `ofl-1.1.txt`, which the OFL itself says is the part to fill in with the font's real notice.
public enum Licences {

    public struct Licence: Equatable, Hashable, Sendable {
        public let name: String
        /// The text's file name in the app's `licences` folder, without the extension.
        public let resource: String
    }

    public static let ofl = Licence(name: "SIL Open Font License 1.1", resource: "ofl-1.1")

    /// Every licence whose full text is in the app.
    public static let all: [Licence] = [ofl]

    public struct Credit: Equatable, Sendable {
        public let what: String
        public let by: String
        /// Nil for what is part of iOS itself: there is no text to carry.
        public let licence: Licence?

        /// The credit as one sentence, as the Help screen prints it.
        public var line: String {
            licence.map { "\(what). \(by). \($0.name)." } ?? "\(what). \(by). Part of iOS."
        }
    }

    public static let credits: [Credit] = [
        Credit(what: "Vision, the framework that finds your joints", by: "Apple", licence: nil),
        Credit(what: "SwiftUI, Swift Charts and AVFoundation, which draw the screens, the charts and the camera",
               by: "Apple", licence: nil),
        // The font's own notice, as it is written in the font file's name table.
        Credit(what: "Manrope, the typeface",
               by: "Copyright 2019 The Manrope Project Authors (https://github.com/sharanda/manrope)", licence: ofl)
    ]
}
