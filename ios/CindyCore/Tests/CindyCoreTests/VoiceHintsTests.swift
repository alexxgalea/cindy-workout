import XCTest
import CindyCore

/// Keeps the voice's hint catalogue honest against the engine that produces the hints.
///
/// The engine words its hints as English string literals and the voice translates them by that
/// text, so the failure this guards against is quiet: someone adds a hint to `WorkoutEngine`, the
/// voice has no entry for it, and a Spanish-speaking athlete hears English in the middle of a
/// set — or hears the generic fallback where a specific instruction was meant. Nothing else would
/// notice, because the hint still shows on screen and still counts.
///
/// So the engine's own sources are read and every string literal in them has to be accounted for,
/// either as a `Hint` or as something known never to be spoken. Adding a literal to either file
/// fails this test until someone has said which.
///
/// Mirrors `VoiceHintsTest.kt`. The sources are Swift, so the reader below reads Swift: raw and
/// multi-line strings, `\( … )` interpolation, nested block comments.
final class VoiceHintsTests: XCTestCase {

    /// Where the hints are worded.
    private let engineFiles = ["WorkoutEngine.swift", "TrackingHealth.swift"]

    /// Literals in those files that are not hints: names and labels that have their own voice
    /// lines or are only ever shown, phase names in the debug readout, and failure text.
    private let notSpoken: Set<String> = [
        "PULL-UPS", "pull ups", "PUSH-UPS", "push ups", "SQUATS", "squats",
        "idle", "down", "up",
        "Frame dimensions must be positive",
        // The rejection reason is built as "Missing " + the joint names joined with ", ".
        "Missing ", ", ",
    ]

    private func sourceOf(_ name: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // CindyCoreTests
            .deletingLastPathComponent()      // Tests
            .deletingLastPathComponent()      // CindyCore
            .appendingPathComponent("Sources/CindyCore/\(name)")
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func literalsIn(_ name: String) throws -> Set<String> {
        Set(try VoiceHintsTests.stringLiterals(sourceOf(name)))
    }

    /// every string in the engine is a catalogued hint or known not to be spoken
    func testEveryStringInTheEngineIsACataloguedHintOrKnownNotToBeSpoken() throws {
        let known = Set(Hint.allCases.map { $0.english }).union(notSpoken)
        for file in engineFiles {
            let unaccounted = try literalsIn(file).subtracting(known)
            XCTAssertTrue(unaccounted.isEmpty,
                          "\(file) has string(s) the voice does not know about: \(unaccounted.sorted()). If a hint, add it to Hint and to every phrasebook; if it is never spoken, add it to notSpoken in this test.")
        }
    }

    /// every catalogued hint is still in the engine
    func testEveryCataloguedHintIsStillInTheEngine() throws {
        let inEngine = try engineFiles.reduce(into: Set<String>()) { $0.formUnion(try literalsIn($1)) }
        let stale = Hint.allCases.filter { !inEngine.contains($0.english) }
        XCTAssertTrue(stale.isEmpty, "catalogued but no longer in the engine: \(stale)")
    }

    /// the start cues are catalogued
    func testTheStartCuesAreCatalogued() {
        for exercise in Exercise.allCases {
            XCTAssertNotNil(Hint.of(exercise.startCue), exercise.startCue)
        }
    }

    /// a hint is found by the engine's text
    func testAHintIsFoundByTheEnginesText() {
        XCTAssertEqual(Hint.of("Get on the bar"), .getOnBar)
        XCTAssertEqual(Hint.of("Can't see you — tap +1"), .cantSeeYou)
        XCTAssertNil(Hint.of("Something nobody catalogued"))
    }

    /// no two hints share their text
    func testNoTwoHintsShareTheirText() {
        XCTAssertEqual(Hint.allCases.count, Set(Hint.allCases.map { $0.english }).count)
    }

    // MARK: - the reader the checks above depend on

    /// the reader finds the engine's strings, so an empty result cannot pass
    func testTheReaderFindsTheEnginesStringsSoAnEmptyResultCannotPass() throws {
        XCTAssertGreaterThanOrEqual(try literalsIn("WorkoutEngine.swift").count, 15)
        XCTAssertGreaterThanOrEqual(try literalsIn("TrackingHealth.swift").count, 3)
    }

    /// the reader takes strings and skips comments
    func testTheReaderTakesStringsAndSkipsComments() {
        let source = [
            "// \"in a line comment\"",
            "/* \"in a /* nested \"block\" */ comment\" */",
            "let a = \"one\"",
            "let b = \"say \\\"hi\\\"\"",
            "let c = \"n=\\(items.joined(separator: \"; \")) end\"",
            "let d = \"\"\"",
            "    raw \"quoted\" text",
            "    \"\"\"",
            "let e = #\"hash \"quoted\" \\n text\"#",
            "let f = \"last\""
        ].joined(separator: "\n")

        XCTAssertEqual(VoiceHintsTests.stringLiterals(source), [
            "one",
            "say \\\"hi\\\"",
            "n=\\(items.joined(separator: \"; \")) end",
            "\n    raw \"quoted\" text\n    ",
            "hash \"quoted\" \\n text",
            "last"
        ])
    }

    /// Every string literal in Swift `source`, comments excluded.
    static func stringLiterals(_ source: String) -> [String] {
        let s = Array(source.unicodeScalars)
        var found: [String] = []
        var i = 0

        func starts(_ text: String, at i: Int) -> Bool {
            let t = Array(text.unicodeScalars)
            return i + t.count <= s.count && Array(s[i..<(i + t.count)]) == t
        }
        func string(_ scalars: ArraySlice<Unicode.Scalar>) -> String {
            var v = String.UnicodeScalarView(); v.append(contentsOf: scalars); return String(v)
        }

        /// Reads a string opening at `start` (at its first quote or hash), returning its text and
        /// the index after it. `hashes` is the number of `#` it was opened with.
        func readString(_ start: Int, hashes: Int) -> (String, Int) {
            let pounds = String(repeating: "#", count: hashes)
            let multiline = starts(pounds + "\"\"\"", at: start)
            let quote = multiline ? "\"\"\"" : "\""
            var i = start + hashes + quote.unicodeScalars.count
            let bodyStart = i
            let closing = quote + pounds
            let escape = "\\" + pounds
            while i < s.count {
                if starts(escape + "(", at: i) {
                    // An interpolation: its own expression, with strings of its own.
                    i += escape.unicodeScalars.count + 1
                    var depth = 1
                    while i < s.count && depth > 0 {
                        if s[i] == "\"" { i = readString(i, hashes: 0).1; continue }
                        if s[i] == "(" { depth += 1 }
                        if s[i] == ")" { depth -= 1 }
                        i += 1
                    }
                } else if starts(escape, at: i) {
                    i += escape.unicodeScalars.count + 1     // the escape and what it escapes
                } else if starts(closing, at: i) {
                    return (string(s[bodyStart..<i]), i + closing.unicodeScalars.count)
                } else {
                    i += 1
                }
            }
            preconditionFailure("unterminated string")
        }

        while i < s.count {
            if starts("//", at: i) {
                while i < s.count && s[i] != "\n" { i += 1 }
            } else if starts("/*", at: i) {
                var depth = 1
                i += 2
                while i < s.count && depth > 0 {
                    if starts("/*", at: i) { depth += 1; i += 2 }
                    else if starts("*/", at: i) { depth -= 1; i += 2 }
                    else { i += 1 }
                }
            } else if s[i] == "#" {
                var n = 0
                while i + n < s.count && s[i + n] == "#" { n += 1 }
                if i + n < s.count && s[i + n] == "\"" {
                    let (text, next) = readString(i, hashes: n)
                    found.append(text)
                    i = next
                } else {
                    i += n
                }
            } else if s[i] == "\"" {
                let (text, next) = readString(i, hashes: 0)
                found.append(text)
                i = next
            } else {
                i += 1
            }
        }
        return found
    }
}
