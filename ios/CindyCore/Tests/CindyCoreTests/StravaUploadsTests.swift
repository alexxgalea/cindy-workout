import XCTest
import CindyCore

/// The upload ledger: its codec, and the decisions made on top of it.
///
/// The first seven mirror `StravaUploadsTest.kt`. The rest are written here, because the part of
/// `StravaUploads` that Android hands to WorkManager and `SharedPreferences` is covered there only
/// through the screens (P20).
final class StravaUploadsTests: XCTestCase {

    private func roundTrips(_ status: StravaUploadStatus, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(StravaUploads.decode(StravaUploads.encode(status)), status, file: file, line: line)
    }

    /// a queued entry round-trips with nothing else set
    func testAQueuedEntryRoundTripsWithNothingElseSet() {
        roundTrips(StravaUploadStatus(.queued))
    }

    /// every field round-trips once it is known
    func testEveryFieldRoundTripsOnceItIsKnown() {
        roundTrips(StravaUploadStatus(.done, uploadId: "12345", activityId: 987654321, message: nil))
    }

    /// a failed entry keeps its message
    func testAFailedEntryKeepsItsMessage() {
        roundTrips(StravaUploadStatus(.failed, message: "duplicate of nothing sensible"))
    }

    /// every state round-trips
    func testEveryStateRoundTrips() {
        for state in StravaUploadState.allCases { roundTrips(StravaUploadStatus(state)) }
    }

    /// null decodes to null
    func testNilDecodesToNil() {
        XCTAssertNil(StravaUploads.decode(nil))
    }

    /// garbage decodes to null rather than guessing
    func testGarbageDecodesToNilRatherThanGuessing() {
        XCTAssertNil(StravaUploads.decode("not the format at all"))
        XCTAssertNil(StravaUploads.decode("QUEUED|only|two"))
    }

    /// an unknown state name decodes to null
    func testAnUnknownStateNameDecodesToNil() {
        XCTAssertNil(StravaUploads.decode("SOMETHING_NEWER||||"))
    }

    // ---- beyond the Kotlin -----------------------------------------------------------------

    private let storage = InMemoryStravaStorage()
    private var ledger: StravaUploads { StravaUploads(storage: storage) }
    private var tokens: StravaTokenStore { StravaTokenStore(storage: storage) }
    private let config = StravaConfig(clientId: "1", clientSecret: "s", applicationId: "com.cindy.tracker")
    private let connected = StravaGrant(accessToken: "a", refreshToken: "r", expiresAtEpochS: 1, scopes: [], athleteName: nil)

    /// a failure message with a bar in it survives, since only four pieces are cut
    func testAFailureMessageWithABarInItSurvivesSinceOnlyFourPiecesAreCut() {
        roundTrips(StravaUploadStatus(.failed, message: "a | b || c"))
    }

    /// an entry is kept per attempt, and an attempt never queued has none
    func testAnEntryIsKeptPerAttemptAndAnAttemptNeverQueuedHasNone() {
        ledger.write(atMillis: 1_000, StravaUploadStatus(.done, activityId: 7))
        XCTAssertEqual(ledger.status(atMillis: 1_000), StravaUploadStatus(.done, activityId: 7))
        XCTAssertNil(ledger.status(atMillis: 2_000))
        XCTAssertEqual(StravaUploads.uniqueWorkName(atMillis: 1_000), "strava-upload-1000")
    }

    /// queueing keeps the upload id Strava already accepted, so the file is polled and not sent again
    func testQueueingKeepsTheUploadIdStravaAlreadyAcceptedSoTheFileIsPolledAndNotSentAgain() {
        ledger.write(atMillis: 1_000, StravaUploadStatus(.processing, uploadId: "555"))
        ledger.queue(atMillis: 1_000)
        XCTAssertEqual(ledger.status(atMillis: 1_000), StravaUploadStatus(.queued, uploadId: "555"))

        ledger.write(atMillis: 2_000, StravaUploadStatus(.failed, message: "no"))
        ledger.queue(atMillis: 2_000)
        XCTAssertEqual(ledger.status(atMillis: 2_000), StravaUploadStatus(.queued))
    }

    /// a saved attempt uploads on its own only when available, connected and automatic
    func testASavedAttemptUploadsOnItsOwnOnlyWhenAvailableConnectedAndAutomatic() {
        let noCredentials = StravaConfig(clientId: "", clientSecret: "", applicationId: "com.cindy.tracker")

        // Not available: nothing else matters.
        tokens.grant = connected
        XCTAssertFalse(ledger.attemptSaved(atMillis: 1, config: noCredentials, tokens: tokens))
        XCTAssertNil(ledger.status(atMillis: 1))

        // Available but not connected.
        tokens.clearGrant()
        XCTAssertFalse(ledger.attemptSaved(atMillis: 2, config: config, tokens: tokens))
        XCTAssertNil(ledger.status(atMillis: 2))

        // Connected, automatic upload off.
        tokens.grant = connected
        tokens.autoUpload = false
        XCTAssertFalse(ledger.attemptSaved(atMillis: 3, config: config, tokens: tokens))
        XCTAssertNil(ledger.status(atMillis: 3))

        // All three.
        tokens.autoUpload = true
        XCTAssertTrue(ledger.attemptSaved(atMillis: 4, config: config, tokens: tokens))
        XCTAssertEqual(ledger.status(atMillis: 4), StravaUploadStatus(.queued))
    }

    /// reconnecting queues the attempts that were waiting for it, oldest first, and no others
    func testReconnectingQueuesTheAttemptsThatWereWaitingForItOldestFirstAndNoOthers() {
        ledger.write(atMillis: 300, StravaUploadStatus(.needsReconnect))
        ledger.write(atMillis: 100, StravaUploadStatus(.needsReconnect))
        ledger.write(atMillis: 200, StravaUploadStatus(.done, activityId: 1))
        ledger.write(atMillis: 400, StravaUploadStatus(.failed, message: "x"))
        storage.set("not a ledger entry", forKey: "upload_500")
        storage.set("x", forKey: "upload_notanumber")

        XCTAssertEqual(ledger.requeueNeedingReconnect(), [100, 300])
        XCTAssertEqual(ledger.status(atMillis: 100), StravaUploadStatus(.queued))
        XCTAssertEqual(ledger.status(atMillis: 300), StravaUploadStatus(.queued))
        XCTAssertEqual(ledger.status(atMillis: 200), StravaUploadStatus(.done, activityId: 1))
        XCTAssertEqual(ledger.status(atMillis: 400), StravaUploadStatus(.failed, message: "x"))
        XCTAssertTrue(ledger.requeueNeedingReconnect().isEmpty)
    }

    /// clearing forgets the ledger and nothing else
    func testClearingForgetsTheLedgerAndNothingElse() {
        tokens.grant = connected
        tokens.pendingState = "s"
        ledger.write(atMillis: 1, StravaUploadStatus(.done, activityId: 1))
        ledger.write(atMillis: 2, StravaUploadStatus(.queued))

        ledger.clear()

        XCTAssertNil(ledger.status(atMillis: 1))
        XCTAssertNil(ledger.status(atMillis: 2))
        XCTAssertTrue(tokens.connected)
        XCTAssertEqual(tokens.pendingState, "s")
    }
}
