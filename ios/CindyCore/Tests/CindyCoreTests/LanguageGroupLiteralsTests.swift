import XCTest
import CindyCore

/// Written for the port. The words `LanguageGroupModel` puts in its toasts and rows live in two
/// places in the Kotlin (`LanguageGroup.kt` and `VoiceLanguageText.kt`); this holds the ones the
/// Kotlin tests do not spell out to the Kotlin source, so a rewording on Android shows up here.
final class LanguageGroupLiteralsTests: XCTestCase {

    private static let root: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }()

    private func kotlin() throws -> String {
        try String(contentsOf: Self.root.appendingPathComponent("app/src/main/java/com/cindy/tracker/LanguageGroup.kt"),
                   encoding: .utf8)
    }

    /// the toasts that answer a tap on a row are the Kotlin's
    func testTheToastsThatAnswerATapOnARowAreTheKotlins() throws {
        let source = try kotlin()
        for literal in ["Downloading the ${pack.englishName} voice",
                        "Opening the voice engine to fetch ${pack.englishName}",
                        "This phone's voice engine doesn't offer ${pack.englishName}"] {
            XCTAssertTrue(source.contains("\"\(literal)\""), literal)
        }
    }

    /// the three spoken notices are produced by the code under test, word for word
    func testTheNoticesComeOutAsTheKotlinSaysThem() {
        let engine = FakeTtsEngine()
        let loop = TestLoop()
        engine.listed = []
        engine.answers["ru-RU"] = .missingData
        engine.answers["es-ES"] = .available
        var toasts: [String] = []
        let speaker = Speaker(engine: engine, background: { $0() }, main: loop.main)
        let model = LanguageGroupModel(speaker: speaker, initial: "en", toast: { toasts.append($0) },
                                       openEngineScreen: {}, schedule: loop.scheduler)
        engine.becomeReady()
        model.start()
        loop.idle()
        model.choose("ru")
        XCTAssertEqual(toasts, ["Opening the voice engine to fetch Russian"])
        model.stop()
    }
}
