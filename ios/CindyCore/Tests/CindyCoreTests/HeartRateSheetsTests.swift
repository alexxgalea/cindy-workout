import XCTest
@testable import CindyCore

/// What the heart-rate sheets say. `MenuActivity` builds these in code and no Kotlin test reads them
/// except through the screen, so these are written for the port, from the Kotlin's strings.
final class HeartRateSheetsTests: XCTestCase {

    private func fresh() -> Profile {
        let suite = "cindy.hrsheets.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return Profile(defaults: defaults)
    }

    /// every status has a line, and only the first two have a hint
    func testEveryStatusHasALineAndOnlyConnectingAndWaitingHaveAHint() {
        for status in HeartRateStatus.allCases {
            let line = HeartRateSheets.line(for: status)
            switch status {
            case .connected, .off: XCTAssertNil(line.message)
            default: XCTAssertNotNil(line.message, "\(status)")
            }
            XCTAssertEqual(line.hint != nil, status == .connecting || status == .waiting, "\(status)")
        }
    }

    /// connecting says so and then asks whether broadcast is on after fifteen seconds
    func testConnectingSaysSoAndThenAsksWhetherBroadcastIsOnAfterFifteenSeconds() {
        let line = HeartRateSheets.line(for: .connecting)
        XCTAssertEqual(line.message, "Connecting…")
        XCTAssertEqual(line.hint, HeartRateSheets.Hint(text: "Can't find it — is heart-rate broadcast on?", afterMs: 15_000))
    }

    /// waiting says connected, and falls back to the broadcast question after eight seconds
    func testWaitingSaysConnectedAndFallsBackToTheBroadcastQuestionAfterEightSeconds() {
        let line = HeartRateSheets.line(for: .waiting)
        XCTAssertEqual(line.message, "Connected — waiting for heart rate…")
        XCTAssertEqual(line.hint?.afterMs, 8_000)
    }

    /// the refusals name their cause
    func testTheRefusalsNameTheirCause() {
        XCTAssertEqual(HeartRateSheets.line(for: .noPermission).message, "Bluetooth permission is off")
        XCTAssertEqual(HeartRateSheets.line(for: .bluetoothOff).message, "Bluetooth is off")
        XCTAssertEqual(HeartRateSheets.line(for: .unsupported).message, "This phone has no Bluetooth LE")
        XCTAssertEqual(HeartRateSheets.line(for: .notAHeartRateDevice).message,
                       "No heart rate from it — is heart-rate broadcast on?")
        XCTAssertEqual(HeartRateSheets.reading(142), "142 bpm")
    }

    /// signal is a band, not a figure
    func testSignalIsABandNotAFigure() {
        XCTAssertEqual(HeartRateSheets.signalLabel(-40), "Strong")
        XCTAssertEqual(HeartRateSheets.signalLabel(-60), "Strong")
        XCTAssertEqual(HeartRateSheets.signalLabel(-61), "Good")
        XCTAssertEqual(HeartRateSheets.signalLabel(-75), "Good")
        XCTAssertEqual(HeartRateSheets.signalLabel(-76), "Weak")
    }

    /// a row says whether the phone is already linked to the device, and its signal when heard
    func testARowSaysWhetherThePhoneIsAlreadyLinkedToTheDeviceAndItsSignalWhenHeard() {
        XCTAssertEqual(HeartRateSheets.foundLabel(FoundDevice("A", "w", rssi: nil, connected: true)), "Connected to this phone")
        XCTAssertEqual(HeartRateSheets.foundLabel(FoundDevice("A", "w", rssi: -55, connected: true)),
                       "Connected to this phone · Strong")
        XCTAssertEqual(HeartRateSheets.foundLabel(FoundDevice("A", "w", rssi: -80)), "Weak")
        XCTAssertEqual(HeartRateSheets.foundLabel(FoundDevice("A", "w", rssi: nil)), "")
        XCTAssertEqual(HeartRateSheets.spoken(FoundDevice("A", "fenix", rssi: -70)), "fenix, Good")
        XCTAssertEqual(HeartRateSheets.spoken(FoundDevice("A", "fenix", rssi: nil)), "fenix")
    }

    /// pairing keeps the device, and asks for the details only when the formula still needs them
    func testPairingKeepsTheDeviceAndAsksForTheDetailsOnlyWhenTheFormulaStillNeedsThem() {
        let profile = fresh()
        let found = FoundDevice("11111111-2222-3333-4444-555555555555", "fenix 7X", rssi: -50)

        XCTAssertTrue(HeartRateSheets.adopt(found, into: profile, nowYear: 2026), "no age or sex yet")
        XCTAssertEqual(profile.heartRateDevice, HeartRateDevice(address: found.address, name: "fenix 7X"))

        profile.bodyWeightKg = 70
        profile.birthYear = 1990
        profile.sex = .female
        XCTAssertFalse(HeartRateSheets.adopt(found, into: profile, nowYear: 2026), "weight, age and sex are there")
    }

    /// the silent-watch warning names the watch, and only when a source is running and quiet
    func testTheSilentWatchWarningNamesTheWatchAndOnlyWhenASourceIsRunningAndQuiet() {
        let device = HeartRateDevice(address: "A", name: "fenix 7X")
        XCTAssertEqual(HeartRateSheets.silentWarning(device: device, sourceRunning: true, nowMs: 20_000, lastReadingAtMs: 0),
                       "No heart rate from fenix 7X yet — calories will use your reps until it arrives")
        XCTAssertNil(HeartRateSheets.silentWarning(device: device, sourceRunning: true, nowMs: 20_000, lastReadingAtMs: 15_000))
        XCTAssertNil(HeartRateSheets.silentWarning(device: device, sourceRunning: false, nowMs: 20_000, lastReadingAtMs: 0))
        XCTAssertNil(HeartRateSheets.silentWarning(device: nil, sourceRunning: true, nowMs: 20_000, lastReadingAtMs: 0))
    }

    /// the unpaired note is Help's advice, without the Android watch it names
    func testTheUnpairedNoteIsHelpsAdviceWithoutTheAndroidWatchItNames() {
        XCTAssertTrue(HeartRateSheets.unpairedNote.contains("Broadcast Heart Rate"))
        XCTAssertTrue(HeartRateSheets.unpairedNote.contains("Apple Watch and most smartwatches"))
        XCTAssertFalse(HeartRateSheets.unpairedNote.contains("Wear OS"))
    }
}
