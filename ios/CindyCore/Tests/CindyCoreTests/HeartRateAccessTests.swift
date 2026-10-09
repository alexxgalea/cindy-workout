import XCTest
@testable import CindyCore

/// What FIND MY WATCH does about the permission it needs. Android 11 and older tie a Bluetooth scan to
/// location, so `HeartRatePermissionSheetTest` holds that Cindy explains the location prompt first and
/// asks only on CONTINUE; Android 12 and newer ask straight away. iOS has one Bluetooth permission and
/// never a location one, so this holds the iOS half of each fact. Ports `HeartRatePermissionsTest` (2)
/// and `HeartRatePermissionSheetTest` (3).
final class HeartRateAccessTests: XCTestCase {

    private func next(_ access: BluetoothAccess, _ radio: BluetoothRadio) -> FindWatchStep {
        HeartRateAccess.next(access: access, radio: radio)
    }

    /// sdk 31 and above needs the split Bluetooth permissions
    func testOnlyBluetoothIsNeededAndTheAppSaysWhatItIsFor() {
        // One permission, Bluetooth, in words the app gives iOS. There is no list to choose from by
        // version, and no location entry in it.
        XCTAssertFalse(HeartRateAccess.usageDescription.isEmpty)
        XCTAssertFalse(HeartRateAccess.usageDescription.lowercased().contains("location"))
        XCTAssertTrue(HeartRateAccess.usageDescription.contains("Nothing is uploaded"))
    }

    /// sdk 30 and below needs fine location instead
    func testNothingEverAsksForLocationOnAnyAnswer() {
        for access in [BluetoothAccess.notDetermined, .allowed, .denied, .restricted] {
            for radio in [BluetoothRadio.unknown, .resetting, .unsupported, .unauthorized, .poweredOff, .poweredOn] {
                let step = next(access, radio)
                XCTAssertTrue([FindWatchStep.scan, .askPermission, .openSettings, .bluetoothOff, .unsupported, .wait]
                                .contains(step), "\(access) \(radio)")
            }
        }
        XCTAssertFalse(HeartRateAccess.deniedSubtitle.contains("Location is"), "no Location-is-off case")
        XCTAssertTrue(HeartRateAccess.deniedSubtitle.contains("never reads your location"))
    }

    /// before Android 12 the location prompt is explained first, and not asked for until CONTINUE
    func testThePromptIsIOSsOwnAndComesStraightAwayWithNoExplanationFirst() {
        // Not asked yet: the next step is to ask, and there is no step for an explanation to sit in.
        XCTAssertEqual(next(.notDetermined, .unknown), .askPermission)
        XCTAssertEqual(next(.notDetermined, .poweredOn), .askPermission)
        XCTAssertFalse(String(describing: FindWatchStep.askPermission).lowercased().contains("explain"))
    }

    /// NOT NOW before Android 12 asks for nothing
    func testSayingNoLeavesItDeniedAndOnlySettingsCanChangeIt() {
        XCTAssertEqual(next(.denied, .poweredOn), .openSettings)
        XCTAssertEqual(next(.denied, .unauthorized), .openSettings)
        XCTAssertEqual(next(.restricted, .poweredOn), .openSettings)
        XCTAssertFalse(HeartRateAccess.canConnect(access: .denied, radio: .poweredOn))
    }

    /// from Android 12 the Bluetooth prompt comes straight away, with no explanation
    func testOnceAllowedTheRadioDecidesTheRest() {
        XCTAssertEqual(next(.allowed, .poweredOn), .scan)
        XCTAssertEqual(next(.allowed, .poweredOff), .bluetoothOff)
        XCTAssertEqual(next(.allowed, .resetting), .wait)
        XCTAssertEqual(next(.allowed, .unknown), .wait)
        XCTAssertEqual(next(.allowed, .unauthorized), .openSettings)
        XCTAssertTrue(HeartRateAccess.canConnect(access: .allowed, radio: .poweredOn))
    }

    // MARK: not in the Kotlin

    /// no radio at all is said first, before any permission is worth asking for
    func testNoRadioAtAllIsSaidFirst() {
        for access in [BluetoothAccess.notDetermined, .allowed, .denied, .restricted] {
            XCTAssertEqual(next(access, .unsupported), .unsupported)
        }
    }

    /// what a source reports when it cannot connect, and nothing when it can or must wait
    func testWhatASourceReportsWhenItCannotConnect() {
        XCTAssertEqual(HeartRateAccess.blocked(access: .denied, radio: .poweredOn), .noPermission)
        XCTAssertEqual(HeartRateAccess.blocked(access: .allowed, radio: .poweredOff), .bluetoothOff)
        XCTAssertEqual(HeartRateAccess.blocked(access: .allowed, radio: .unsupported), .unsupported)
        XCTAssertNil(HeartRateAccess.blocked(access: .allowed, radio: .poweredOn))
        XCTAssertNil(HeartRateAccess.blocked(access: .allowed, radio: .resetting))
    }

    /// the words are the Kotlin's where the fact is the same
    func testTheWordsAreTheKotlinsWhereTheFactIsTheSame() {
        XCTAssertEqual(HeartRateAccess.unsupportedToast, "This phone has no Bluetooth LE, so it cannot hear a watch")
    }
}
