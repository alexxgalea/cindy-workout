import Foundation

/// Three facts about where the phone goes, one line each, rather than a paragraph nobody reads on
/// the way to a bar.
///
/// Shared by the sheet that opens before the first setup check and by the first-launch pages, so
/// that the two cannot drift into giving different advice about the one thing the athlete has to
/// get right. `warning` marks the one that costs a workout's learning if ignored. `icon` is the
/// name of the Android drawable the fact is drawn with (`CindyIcon`'s raw value).
public enum PlacementFacts {

    public struct Fact: Equatable, Sendable {
        public let icon: String
        public let text: String
        public let warning: Bool
    }

    public static let all: [Fact] = [
        Fact(icon: "ic_phone_stand", text: "Stand the phone up rather than laying it flat.", warning: false),
        Fact(icon: "ic_frame", text: "Keep your head and your feet both in shot.", warning: false),
        Fact(icon: "ic_dont_move", text: "Then leave it there — moving it mid-workout resets what it has learned.", warning: true)
    ]
}

/// The words the placement guide's view drew itself, with nothing to pin them to the sheet
/// `MainActivity.showPlacementGuide` builds. `PlacementFactsTests` reads each off the Kotlin.
public enum PlacementWords {
    public static let title = "Where to stand"
    public static let subtitle = "The one thing you have to get right before the camera can help."
    public static let dontShowAgain = "Don't show this again"
    public static let start = "START SETUP"
    public static let notNow = "NOT NOW"
}
