import XCTest

/// The iPhone app draws Android's icons: `tools/ios_icons.py` turns each `ic_*` vector drawable
/// into an SVG imageset, and `CindyIcon` names them. Nothing here can render a vector, so what is
/// held in step is what the generator copies: the set of icons, each path's data and stroke width,
/// which icon keeps a colour of its own, and the enum that names them.
final class IconParityTests: XCTestCase {

    private static let root: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }()

    private static var drawables: URL { root.appendingPathComponent("app/src/main/res/drawable") }
    private static var icons: URL { root.appendingPathComponent("ios/CindyTracker/Assets.xcassets/Icons") }

    private func names(in directory: URL, suffix: String) -> Set<String> {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return Set(files.filter { $0.hasPrefix("ic_") && $0.hasSuffix(suffix) }
            .map { String($0.dropLast(suffix.count)) })
    }

    private var androidNames: Set<String> {
        names(in: Self.drawables, suffix: ".xml").subtracting(["ic_launcher_foreground"])
    }

    private var imagesetNames: Set<String> {
        names(in: Self.icons, suffix: ".imageset")
    }

    private func text(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    private func matches(_ pattern: String, in source: String) throws -> [[String]] {
        let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        let all = NSRange(source.startIndex..., in: source)
        return regex.matches(in: source, range: all).map { m in
            (1..<m.numberOfRanges).map { String(source[Range(m.range(at: $0), in: source)!]) }
        }
    }

    /// Android's icons became Phosphor's on the 256 grid (ADR 0008, #170) and lost two (`ic_music`,
    /// `ic_voice`). The iPhone app keeps the old hand-drawn set until its port (#155; ADR 0003), so
    /// the tests that hold the iPhone's artwork to Android's artwork are skipped, and say so, until
    /// that port lands. Delete this and the `XCTSkipIf` calls below when it does.
    private static let iPhoneKeepsTheOldSet =
        "Skipped until the iPhone port of the polished interface (#155): Android's icons are Phosphor's "
        + "(ADR 0008, #170) and the iPhone app keeps the old set until its port (ADR 0003)."

    /// Holds today: every icon Android still has also has an imageset, and has paths to draw.
    func testEveryAndroidIconStillHasAnImageset() throws {
        XCTAssertTrue(androidNames.isSubset(of: imagesetNames),
                      "no imageset for \(androidNames.subtracting(imagesetNames).sorted())")
        for name in androidNames.sorted() {
            XCTAssertFalse(try androidPaths(name).isEmpty, name)
        }
    }

    /// Holds today: each imageset is a well-formed file pair, its SVG draws at least one path, and
    /// every path says what it fills (SVG fills black unless told not to; Android's default is none).
    func testEveryImagesetIsWellFormed() throws {
        XCTAssertFalse(imagesetNames.isEmpty)
        for name in imagesetNames.sorted() {
            let folder = Self.icons.appendingPathComponent("\(name).imageset")
            XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Contents.json").path),
                          "\(name) has no Contents.json")
            let svg = try text(folder.appendingPathComponent("\(name).svg"))
            let paths = try matches("<path\\b(.*?)/>", in: svg)
            XCTAssertFalse(paths.isEmpty, "\(name) draws no path")
            for path in paths {
                XCTAssertTrue(path[0].contains("fill=\""), "\(name) leaves a path's fill to the default")
            }
        }
    }

    /// The exact set: one imageset per Android icon and no other. The count is the 22 Android had
    /// before #170; it has 20 now, and the iPhone still has `ic_music` and `ic_voice` as well, so
    /// there are 22 imagesets. The count is for the port to restate.
    func testEveryAndroidIconHasAnImageset() throws {
        try XCTSkipIf(true, Self.iPhoneKeepsTheOldSet)
        XCTAssertEqual(androidNames.count, 22)
        XCTAssertEqual(imagesetNames, androidNames)
    }

    /// One `(pathData, strokeWidth)` per `<path>`, in document order. A path with no stroke width
    /// has `"0"`, as the SVG does.
    private func androidPaths(_ name: String) throws -> [[String]] {
        let xml = try text(Self.drawables.appendingPathComponent("\(name).xml"))
        return try matches("<path\\b(.*?)/>", in: xml).map { tag in
            let data = try matches("android:pathData=\"([^\"]*)\"", in: tag[0]).first?.first ?? ""
            let width = try matches("android:strokeWidth=\"([^\"]*)\"", in: tag[0]).first?.first ?? "0"
            return [data, width]
        }
    }

    private func svgPaths(_ name: String) throws -> [[String]] {
        let svg = try text(Self.icons.appendingPathComponent("\(name).imageset/\(name).svg"))
        return try matches("<path\\b(.*?)/>", in: svg).map { tag in
            let data = try matches("\\sd=\"([^\"]*)\"", in: tag[0]).first?.first ?? ""
            let width = try matches("stroke-width=\"([^\"]*)\"", in: tag[0]).first?.first ?? "0"
            return [data, width]
        }
    }

    func testEachSvgDrawsTheVectorsPathsInOrder() throws {
        try XCTSkipIf(true, Self.iPhoneKeepsTheOldSet)
        for name in androidNames.sorted() {
            XCTAssertEqual(try svgPaths(name), try androidPaths(name), name)
        }
    }

    func testEachSvgFillsOnlyWhereAndroidFills() throws {
        // Only the fill rule is compared here: that every path states its fill, and that each SVG
        // has paths, are held by `testEveryImagesetIsWellFormed`, which runs.
        try XCTSkipIf(true, Self.iPhoneKeepsTheOldSet)
        for name in androidNames.sorted() {
            let xml = try text(Self.drawables.appendingPathComponent("\(name).xml"))
            let svg = try text(Self.icons.appendingPathComponent("\(name).imageset/\(name).svg"))
            XCTAssertEqual(xml.contains("evenOdd"), svg.contains("evenodd"), name)
        }
    }

    func testOnlyAnIconWithAColourOfItsOwnKeepsIt() throws {
        var original: Set<String> = []
        for name in imagesetNames.sorted() {
            let json = try text(Self.icons.appendingPathComponent("\(name).imageset/Contents.json"))
            let intent = try matches("\"template-rendering-intent\"\\s*:\\s*\"(\\w+)\"", in: json).first?.first
            XCTAssertTrue(intent == "template" || intent == "original", name)
            if intent == "original" { original.insert(name) }
        }
        XCTAssertEqual(original, ["ic_check_filled"])
        XCTAssertEqual(imagesetNames.count - original.count, 21)
    }

    func testCindyIconNamesEveryImageset() throws {
        let source = try text(Self.root.appendingPathComponent("ios/CindyTracker/CindyIcon.swift"))
        let literals = Set(try matches("\"(ic_[a-z_]+)\"", in: source).map { $0[0] })
        XCTAssertEqual(literals, imagesetNames)
    }
}
