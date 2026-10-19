import XCTest
@testable import CindyCore

/// The privacy policy the iPhone app links to, held to what App Review asks of one and to what the
/// app says about itself.
///
/// Mirrors `PlayPolicyTest.kt` (5). The policy is published at an address the app opens, and Help's
/// PRIVACY section and the consent sheet say the same things inside the app. A promise made in one
/// and not the other is the kind of mismatch App Review looks for, so the sentences that appear in
/// more than one place are checked against each other here. Rendering is `tools/play/render.py
/// --store appstore`; this reads the same markers.
final class AppStorePolicyTests: XCTestCase {

    private let root: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    private var template: String {
        get throws { try String(contentsOf: root.appendingPathComponent("appstore/privacy-policy.html"), encoding: .utf8) }
    }

    /// Keeps a `#strava` block for a build with Strava and a `^strava` block for one without.
    private func render(withStrava: Bool) throws -> String {
        let raw = try template
        let block = try NSRegularExpression(pattern: #"\{\{([#^])strava\}\}(.*?)\{\{/strava\}\}\n?"#,
                                            options: [.dotMatchesLineSeparators])
        var out = raw
        for match in block.matches(in: raw, range: NSRange(raw.startIndex..., in: raw)).reversed() {
            let whole = Range(match.range, in: out)!
            let inverted = out[Range(match.range(at: 1), in: out)!] == "^"
            let inner = String(out[Range(match.range(at: 2), in: out)!])
            out.replaceSubrange(whole, with: (inverted ? !withStrava : withStrava) ? String(inner.drop { $0 == "\n" }) : "")
        }
        return out
    }

    private func matches(_ text: String, _ pattern: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { String(text[Range($0.range, in: text)!]) }
    }

    /// The visible words of a page: tags dropped, entities left as they are, spaces collapsed.
    private func words(_ html: String) -> String {
        var text = html
        for pattern in [#"<style.*?</style>"#, #"<[^>]+>"#] {
            text = text.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        return text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// only the publisher's own details are left to fill in, and the Strava blocks are closed
    func testOnlyThePublishersOwnDetailsAreLeftToFillInAndTheStravaBlocksAreClosed() throws {
        XCTAssertEqual(matches(try template, #"\{\{[#^]strava\}\}"#).count, matches(try template, #"\{\{/strava\}\}"#).count,
                       "unbalanced Strava blocks")
        for withStrava in [false, true] {
            let left = Set(matches(try render(withStrava: withStrava), #"\{\{[^}]*\}\}"#))
            XCTAssertEqual(left, ["{{DEVELOPER_NAME}}", "{{CONTACT_EMAIL}}", "{{EFFECTIVE_DATE}}"],
                           "something other than the three details is left (strava=\(withStrava))")
        }
    }

    /// the policy has what App Review requires of one
    func testThePolicyHasWhatAppReviewRequiresOfOne() throws {
        for withStrava in [false, true] {
            let page = try render(withStrava: withStrava)
            let text = words(page)
            // Who publishes it and how to reach them.
            XCTAssertTrue(text.contains("Published by {{DEVELOPER_NAME}}"))
            XCTAssertTrue(page.contains("mailto:{{CONTACT_EMAIL}}"))
            XCTAssertTrue(text.contains("Effective {{EFFECTIVE_DATE}}"))
            // The data it touches, how it is kept and removed, and the usual duties.
            for heading in ["What the app uses, and where it goes", "What the app does not do", "Backup",
                            "Keeping and deleting your information", "Security", "Children", "Changes", "Contact"] {
                XCTAssertTrue(page.contains("<h2>\(heading)</h2>"), "no '\(heading)' section (strava=\(withStrava))")
            }
        }
    }

    /// a build without Strava does not mention it, and one with Strava says what is sent
    func testABuildWithoutStravaDoesNotMentionItAndOneWithStravaSaysWhatIsSent() throws {
        XCTAssertFalse(words(try render(withStrava: false)).lowercased().contains("strava"))

        let with = words(try render(withStrava: true))
        for phrase in ["Strava's own privacy policy", "HTTPS", "DISCONNECT", "Keychain",
                       "Never the camera picture, the video or your pose"] {
            XCTAssertTrue(with.contains(phrase), "the Strava section lost: \(phrase)")
        }
        // What the consent sheet tells the athlete is sent, in the words the policy uses.
        let sheet = StravaConsent.words.joined(separator: " ")
        for phrase in ["every set with its reps", "paused and in real time"] {
            XCTAssertTrue(with.contains(phrase), "the policy no longer says: \(phrase)")
            XCTAssertTrue(sheet.contains(phrase), "the consent sheet no longer says: \(phrase)")
        }
        for phrase in ["if you have set a body weight", "heart-rate trace, if a watch recorded one", "a title and a short description"] {
            XCTAssertTrue(with.contains(phrase), "the policy no longer says: \(phrase)")
        }
    }

    /// the policy and Help give the same ways to delete
    func testThePolicyAndHelpGiveTheSameWaysToDelete() throws {
        let policy = words(try render(withStrava: false))
        let help = HelpBuilder.build(HelpInput(attempts: [], features: .all, versionName: "1.0.0", versionCode: "1")).text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        for phrase in ["DISCARD on a session's page", "REMOVE on the Account screen", "Videos in Photos are yours to delete"] {
            XCTAssertTrue(policy.contains(phrase), "the policy lacks: \(phrase)")
            XCTAssertTrue(help.contains(phrase), "Help lacks: \(phrase)")
        }
        XCTAssertTrue(help.contains("no ads, no analytics, no account"))
        XCTAssertTrue(policy.contains("no ads, no analytics, no tracking and no account"))
    }

    /// the policy address the app opens is the iPhone page, and a page for it exists
    func testThePolicyAddressTheAppOpensIsTheIPhonePage() throws {
        XCTAssertEqual(AppLinks.privacyPolicy, "https://alexxgalea.github.io/cindy-privacy/ios/")
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("appstore/privacy-policy.html").path))
    }
}
