import Foundation

/// Three facts about where the phone goes, one line each, rather than a paragraph nobody reads on
/// the way to a bar.
///
/// Shared by the sheet that opens before the first setup check and by the first-launch pages, so
/// that the two cannot drift into giving different advice about the one thing the athlete has to
/// get right. `warning` marks the one that costs a workout's learning if ignored.
public enum PlacementFacts {

    public struct Fact: Equatable, Sendable {
        public let symbol: String
        public let text: String
        public let warning: Bool
    }

    public static let all: [Fact] = [
        Fact(symbol: "iphone.gen3", text: "Stand the phone up rather than laying it flat.", warning: false),
        Fact(symbol: "viewfinder", text: "Keep your head and your feet both in shot.", warning: false),
        Fact(symbol: "lock", text: "Then leave it there — moving it mid-workout resets what it has learned.", warning: true)
    ]
}
