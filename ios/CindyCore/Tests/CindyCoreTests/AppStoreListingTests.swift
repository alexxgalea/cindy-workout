import XCTest
@testable import CindyCore

/// The App Store listing, held to Apple's limits and to what the app actually does.
///
/// Mirrors `PlayListingTest.kt`. The text lives in `appstore/listing/en-US/`, outside the app, so
/// nothing else would notice it going over a limit, naming something the app does not do, or
/// growing a claim App Review turns away. A listing is written once for two builds: the Strava
/// sentences sit between `{{#strava}}` and `{{/strava}}`, and `tools/play/render.py --store appstore`
/// keeps or drops them. This reads the same markers, so both builds' text is checked.
final class AppStoreListingTests: XCTestCase {

    private let root: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    private func read(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private func listing(_ name: String) throws -> String { try read("appstore/listing/en-US/\(name)") }

    /// The same rule `render.py` applies: keep the contents of a `#strava` block for a build with
    /// Strava and of a `^strava` block for one without, and drop the rest.
    private func render(_ raw: String, withStrava: Bool) -> String {
        let block = try! NSRegularExpression(pattern: #"\{\{([#^])strava\}\}(.*?)\{\{/strava\}\}\n?"#,
                                             options: [.dotMatchesLineSeparators])
        var out = raw
        for match in block.matches(in: raw, range: NSRange(raw.startIndex..., in: raw)).reversed() {
            let whole = Range(match.range, in: out)!
            let inverted = out[Range(match.range(at: 1), in: out)!] == "^"
            let inner = String(out[Range(match.range(at: 2), in: out)!])
            let keep = inverted ? !withStrava : withStrava
            out.replaceSubrange(whole, with: keep ? String(inner.drop { $0 == "\n" }) : "")
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private let variants = [false, true]

    private var releaseNotes: [String] {
        let folder = root.appendingPathComponent("appstore/listing/en-US/release-notes")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { $0.hasSuffix(".txt") }.sorted().map { "release-notes/\($0)" }
    }

    private var files: [String] {
        ["name.txt", "subtitle.txt", "promotional-text.txt", "description.txt", "keywords.txt"] + releaseNotes
    }

    /// Every file that is rendered with the listing, the review notes among them.
    private var rendered: [(name: String, raw: String)] {
        get throws { try (files.map { ($0, try listing($0)) }) + [("review-notes.txt", try read("appstore/review-notes.txt"))] }
    }

    private func count(_ text: String, _ pattern: String) -> Int {
        let regex = try! NSRegularExpression(pattern: pattern)
        return regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    /// every Strava block is closed, and none is left after rendering
    func testEveryStravaBlockIsClosedAndNoneIsLeftAfterRendering() throws {
        for (name, raw) in try rendered {
            XCTAssertEqual(count(raw, #"\{\{[#^]strava\}\}"#), count(raw, #"\{\{/strava\}\}"#), "\(name) has an unbalanced Strava block")
            for withStrava in variants {
                XCTAssertFalse(render(raw, withStrava: withStrava).contains("{{"), "\(name) still has a marker (strava=\(withStrava))")
            }
        }
    }

    /// the name, subtitle, promotional text, description and keywords fit App Store Connect's limits
    func testTheTextsFitAppStoreConnectsLimits() throws {
        let limits: [(String, Int)] = [("name.txt", 30), ("subtitle.txt", 30), ("promotional-text.txt", 170),
                                       ("description.txt", 4000), ("keywords.txt", 100)]
        for withStrava in variants {
            for (file, limit) in limits {
                let text = render(try listing(file), withStrava: withStrava)
                XCTAssertTrue((1...limit).contains(text.count), "\(file) is \(text.count) characters, the limit is \(limit)")
            }
        }
    }

    /// every release note and the review notes fit 4000 characters
    func testEveryReleaseNoteAndTheReviewNotesFit4000Characters() throws {
        XCTAssertFalse(releaseNotes.isEmpty, "there are no release notes")
        for name in releaseNotes + ["../../../review-notes.txt"] {
            for withStrava in variants {
                let raw = name.hasPrefix("..") ? try read("appstore/review-notes.txt") : try listing(name)
                let text = render(raw, withStrava: withStrava)
                XCTAssertTrue((1...4000).contains(text.count), "\(name) is \(text.count) characters (strava=\(withStrava))")
            }
        }
    }

    /// there are release notes for the version this build is
    func testThereAreReleaseNotesForTheVersionThisBuildIs() throws {
        let project = try read("ios/project.yml")
        let version = try XCTUnwrap(project.range(of: #"MARKETING_VERSION: "([^"]+)""#, options: .regularExpression)
            .map { String(project[$0]).split(separator: "\"")[1] })
        XCTAssertTrue(releaseNotes.contains("release-notes/\(version).txt"),
                      "MARKETING_VERSION is \(version); write appstore/listing/en-US/release-notes/\(version).txt before an upload")
    }

    /// the keywords are a comma list with no spaces around commas, no repeats, and none the name already carries
    func testTheKeywordsAreACleanCommaListThatDoesNotRepeatTheName() throws {
        let keywords = try listing("keywords.txt").trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(keywords.contains(", ") || keywords.contains(" ,"), "Apple counts the spaces; leave none around the commas")
        let list = keywords.split(separator: ",").map { $0.lowercased() }
        XCTAssertEqual(list.count, Set(list).count, "a keyword is repeated")
        let known = (try listing("name.txt") + " " + (try listing("subtitle.txt"))).lowercased()
        for word in list {
            XCTAssertFalse(known.contains(word), "'\(word)' is already in the name or subtitle, which Apple indexes")
        }
    }

    /// a language count anywhere in the listing is the number the app has
    func testALanguageCountAnywhereInTheListingIsTheNumberTheAppHas() throws {
        let pattern = try NSRegularExpression(pattern: #"(\d+) languages"#)
        for (name, raw) in try rendered {
            for match in pattern.matches(in: raw, range: NSRange(raw.startIndex..., in: raw)) {
                let number = Int(String(raw[Range(match.range(at: 1), in: raw)!]))
                XCTAssertEqual(number, VoicePacks.all.count, "\(name) says \(String(raw[Range(match.range, in: raw)!]))")
            }
        }
    }

    /// the description counts the voice languages the app has
    func testTheDescriptionCountsTheVoiceLanguagesTheAppHas() throws {
        XCTAssertTrue(render(try listing("description.txt"), withStrava: true).contains("in \(VoicePacks.all.count) languages"))
    }

    /// no listing text names Strava in a build that has none
    func testNoListingTextNamesStravaInABuildThatHasNone() throws {
        for (name, raw) in try rendered {
            XCTAssertFalse(render(raw, withStrava: false).lowercased().contains("strava"), "\(name) still names Strava without it")
        }
    }

    /// the name, subtitle and keywords name neither CrossFit nor Strava
    func testTheNameSubtitleAndKeywordsNameNeitherCrossFitNorStrava() throws {
        for name in ["name.txt", "subtitle.txt", "keywords.txt", "promotional-text.txt"] {
            let text = try listing(name).lowercased()
            XCTAssertFalse(text.contains("crossfit"), "\(name) mentions CrossFit")
            XCTAssertFalse(text.contains("strava"), "\(name) mentions Strava")
        }
    }

    /// CrossFit appears only in the sentences that say Cindy is not CrossFit's
    func testCrossFitAppearsOnlyInTheSentencesThatSayCindyIsNotCrossFits() throws {
        let full = render(try listing("description.txt"), withStrava: true)
        let sentence = "Cindy Tracker is an independent app. It is not affiliated with or endorsed by CrossFit, LLC. " +
            "CrossFit is a registered trademark of CrossFit, LLC."
        XCTAssertTrue(full.contains(sentence), "the non-affiliation sentence is missing or has changed")
        let rest = full.replacingOccurrences(of: sentence, with: "").lowercased()
        XCTAssertEqual(rest.components(separatedBy: "crossfit").count - 1, 0, "CrossFit is named outside the disclaimer")
    }

    /// Strava is named only in a build that has it, and never as an endorsement
    func testStravaIsNamedOnlyInABuildThatHasItAndNeverAsAnEndorsement() throws {
        let raw = try listing("description.txt")
        XCTAssertFalse(render(raw, withStrava: false).lowercased().contains("strava"))
        let with = render(raw, withStrava: true)
        XCTAssertTrue(with.contains("Strava"))
        for word in ["official", "partner", "endorsed by strava", "powered by strava"] {
            XCTAssertFalse(with.lowercased().contains(word), "the Strava text says '\(word)'")
        }
    }

    /// nothing in the listing is what App Review's metadata rules turn away
    func testNothingInTheListingIsWhatAppReviewsMetadataRulesTurnAway() throws {
        // Apple: no other platform's name in the metadata, no prices, no unverifiable superlatives.
        for name in files {
            for withStrava in variants {
                let text = render(try listing(name), withStrava: withStrava)
                let where_ = "\(name) (strava=\(withStrava))"
                for word in ["android", "google play", "best", "free", "top", "sale", "discount"] {
                    XCTAssertEqual(count(text.lowercased(), #"\b"# + word + #"\b"#), 0, "\(where_) says '\(word)'")
                }
                XCTAssertFalse(text.contains("#1"), "\(where_) says #1")
                XCTAssertFalse(text.unicodeScalars.contains { (0x1F000...0x1FAFF).contains($0.value) || (0x2600...0x27BF).contains($0.value) },
                               "\(where_) has an emoji")
                XCTAssertEqual(count(text, #"\b[A-Z]{2,}\b[ ,]+\b[A-Z]{2,}\b[ ,]+\b[A-Z]{2,}\b"#), 0, "\(where_) has a run of capitals")
            }
        }
    }

    /// the review notes tell App Review how to reach the screens that need a person, and ask for no sign-in
    func testTheReviewNotesTellAppReviewHowToReachTheCountingScreens() throws {
        let notes = render(try read("appstore/review-notes.txt"), withStrava: true).lowercased()
        XCTAssertTrue(notes.contains("no sign-in") || notes.contains("no account"), "say that there is no account to sign in to")
        XCTAssertTrue(notes.contains("skip"), "say how to move on without doing the movements")
    }
}
