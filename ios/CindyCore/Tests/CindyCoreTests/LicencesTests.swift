import XCTest
@testable import CindyCore

/// The licences have to travel with the app, and Help has to credit what each one covers. These
/// hold the two lists to each other, so a credit cannot name a licence whose text is not shipped and
/// a shipped text cannot go uncredited. Port of `LicencesTest.kt`; the texts are read from the
/// folder the app bundles them from, which is what "ships" means here.
final class LicencesTests: XCTestCase {

    private static let root: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }()

    static func text(_ licence: Licences.Licence) throws -> String {
        let url = root.appendingPathComponent("ios/CindyTracker/Resources/licences/\(licence.resource).txt")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// every licence's full text ships in the app, and is that licence
    func testEveryLicencesFullTextShipsInTheAppAndIsThatLicence() throws {
        let markers: [Licences.Licence: [String]] = [
            Licences.ofl: ["SIL OPEN FONT LICENSE Version 1.1", "PERMISSION & CONDITIONS", "OTHER DEALINGS IN THE FONT SOFTWARE."]
        ]
        XCTAssertEqual(Set(Licences.all), Set(markers.keys), "a licence has no markers here")
        for (licence, expected) in markers {
            let text = try Self.text(licence)
            XCTAssertFalse(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(licence.name) is empty")
            for marker in expected {
                XCTAssertTrue(text.contains(marker), "\(licence.name) is missing '\(marker)'")
            }
        }
    }

    /// every credit names a licence that ships, and every shipped licence is credited
    func testEveryCreditNamesALicenceThatShipsAndEveryShippedLicenceIsCredited() {
        for credit in Licences.credits {
            if let licence = credit.licence {
                XCTAssertTrue(Licences.all.contains(licence), "\(credit.what) names a licence that is not shipped")
            }
        }
        for licence in Licences.all {
            XCTAssertTrue(Licences.credits.contains { $0.licence == licence }, "\(licence.name) ships but covers nothing")
        }
    }

    /// the font's notice in the credit is the notice its licence text opens with
    func testTheFontsNoticeInTheCreditIsTheNoticeItsLicenceTextOpensWith() throws {
        let manrope = try XCTUnwrap(Licences.credits.first { $0.licence == Licences.ofl })
        let firstLine = try Self.text(Licences.ofl).components(separatedBy: "\n").first
        XCTAssertEqual(manrope.by, firstLine)
    }

    // MARK: not in the Kotlin: what iOS changes

    /// what is part of iOS is credited to Apple, with no licence text to carry
    func testWhatIsPartOfIOSIsCreditedToAppleWithNoLicenceTextToCarry() {
        let apple = Licences.credits.filter { $0.licence == nil }
        XCTAssertFalse(apple.isEmpty)
        for credit in apple {
            XCTAssertEqual(credit.by, "Apple")
            XCTAssertEqual(credit.line, "\(credit.what). Apple. Part of iOS.")
        }
        XCTAssertTrue(apple.contains { $0.what.hasPrefix("Vision") }, "the model that finds the joints is credited")
        XCTAssertFalse(Licences.credits.contains { $0.what.contains("MoveNet") || $0.what.contains("LiteRT") },
                       "nothing Android ships and iOS does not is credited")
    }

    /// a credit with a licence reads as name, by, licence
    func testACreditWithALicenceReadsAsNameByLicence() {
        let manrope = Licences.credits.last!
        XCTAssertEqual(manrope.line, "\(manrope.what). \(manrope.by). SIL Open Font License 1.1.")
    }

    /// the font files the app registers are the ones that ship, five weights
    func testTheFontFilesTheAppRegistersAreTheOnesThatShipFiveWeights() throws {
        let folder = Self.root.appendingPathComponent("ios/CindyTracker/Resources/fonts")
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        XCTAssertEqual(names, ["manrope_bold.ttf", "manrope_extrabold.ttf", "manrope_medium.ttf",
                               "manrope_regular.ttf", "manrope_semibold.ttf"])
        let android = Self.root.appendingPathComponent("app/src/main/res/font")
        for name in names {
            XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent(name)),
                           try Data(contentsOf: android.appendingPathComponent(name)), "\(name) is Android's file")
        }
    }
}
