# What the Swift port mirrors

One row per Kotlin source file, with the phase of `PLAN.md` that ports it and where it stands.
A phase updates the rows it moves, in its own pull request.

| Status | Meaning |
|---|---|
| not started | No Swift counterpart yet |
| behind | A Swift counterpart exists from the September sync and has not been brought level with the Kotlin |
| ported | Swift counterpart written and level with the Kotlin |
| tests ported | Ported, and every Kotlin test for it has a Swift test (the count is in the phase's pull request) |
| not ported | Deliberately has no counterpart, with the reason in the Lands in column |

The Swift engine reproduces `tests/parity/trace_jvm.csv` from P2 onward, so any Android change to a
file marked `CindyCore` below changes that trace and fails `core` until the Swift side follows.

`PoseGeometry` and `StartPoses` have no Kotlin test of their own: the first is covered through the
engine tests and the parity trace, and the second has tests written for the port, which read the
Kotlin table and compare every number.

### Kotlin tests that moved to the phase that owns what they test

| Kotlin test | Moved to | Because |
|---|---|---|
| `StravaSetsTest`, all but the last (`the adaptive profile on the attempt reaches StravaPayload's mapping`) | P3 (from P19) | `RoundSplits` and `SessionStats` read `StravaSets.from`, so it cannot wait for the Strava phase. The last test feeds the result to `StravaPayload`, and stays with it |
| `StravaSessionTest` (6) | P19 (from P20) | Robolectric on Android only because its store is `SharedPreferences`. `StravaSession` is in `StravaTokens.kt`, which is P19's, and over an in-memory `StravaStorage` the six are plain tests |
| `VariationsTest`, `adaptive sessions count toward the streak` | P8 | It needs `Streak`. Ported in P8, in `VariationsTests` |

### Kotlin tests that stay with their view or their phase

| Kotlin test | Stays with | Because |
|---|---|---|
| `ReminderDeliveryTest` (10) | P18 | Arms and cancels Android alarms |
| `StravaHeartRateTest` | P19 | Strava's heart-rate stream (ported in P19, below) |

### Kotlin tests that were ported in P11, and the ones that were not

| Kotlin test | Lands in | Because |
|---|---|---|
| `RoundTrackViewTest` (7), `ZoneBarViewTest` (9), `RoundSplitsViewTest` (10), `SessionTimelineViewTest` (13) | CindyCore `RoundTrackModelTests`, `ZoneBarModelTests`, `RoundSplitsChartModelTests`, `SessionTimelineChartModelTests` | Robolectric drives each chart as a `View` with `MotionEvent`s. Each chart's touch, selection, geometry and screen-reader stops are a pure model here, which the `Canvas` view only paints, so the same 39 tests run on Linux against the same numbers. The drawing itself is not under test |
| `ScreenSmokeTest`, the results parts | CindyCore `ResultsPageTests` (30) and `ResultsChartsTests` (23) | The assertions read facts off the inflated screen (which cards exist, what each says). `ResultsPageBuilder` decides those facts and the tests read them off the `ResultsPage` it returns |
| `ScreenSmokeTest`, the Strava row | CindyCore `StravaConfigTests` and `MenuPageTests` (P19, P13) | The test only keeps Strava out of the screens it lays out (`NoStravaCredentials`). Here a build with no credentials is a `StravaConfig` that is not `available`, and the menu's row is a `StravaStatus` that is nil |

### Kotlin tests that were ported in P12

| Kotlin test | Lands in | Because |
|---|---|---|
| `CalendarViewTest` (4), `ProgressChartViewTest` (4) | CindyCore `CalendarModelTests`, `ProgressChartModelTests` | Robolectric drives each as a `View` with `MotionEvent`s. Touch, selection, geometry and screen-reader stops are a pure model here, which the `Canvas` view only paints, so the same 8 tests run on Linux against the same numbers |
| `ScreenSmokeTest`, the Progress parts: the records screen builds (empty, with history, across categories), the chart card switches metric and range and handles a range with no sessions, a trained day opens its sessions, a leaderboard row, a day-sheet row and the chart's OPEN button each open that session | CindyCore `ProgressPageTests` (9) | The assertions read facts off the inflated screen. `ProgressPageBuilder` and `ProgressModel` decide those facts, and the tests read them off the `ProgressPage` they return; "opens that session" is the `atMillis` a row or button asks to reopen |

### Kotlin tests that were ported in P13

The 58 screen tests of `AccountScreenTest` (34), `HeelsFlatScreensTest` (11), `ProfileHeartRateTest` (8) and `ProfileVoiceLanguageTest` (5), plus the menu parts of `ScreenSmokeTest`. Robolectric inflated each screen and read its views; the same facts are read off the page the core builds, each test named after the Kotlin one, and the part that is a platform's (a view drawn or measured, a picker started, a screen opened) stays with the SwiftUI layer.

| Kotlin test | Lands in | Because |
|---|---|---|
| `ProfileHeartRateTest` (8), `ProfileVoiceLanguageTest` (5) | CindyCore `ProfileTests` | Pure settings over `UserDefaults` instead of `SharedPreferences`, in a throwaway suite |
| `HeelsFlatScreensTest` (11) | CindyCore `HeelsFlatScreensTests` | The sheet's setting is `MovementsForm`, the row `MenuBuilder`, the results sheet `HeelsFlatSheet` |
| `AccountScreenTest`, 25 of 35 | CindyCore `AccountPageTests` and `AvatarFilesTests` | The page is `AccountBuilder`, the name `NameForm`, the photo's sheet `PhotoSheet`, its file `AvatarFiles`, the menu's card `MenuBuilder`, and the badges on the results page `ResultsPageBuilder` |
| `AccountScreenTest`, 3 of 35: the leaderboard says "You" until there is a name; Progress has no way to delete everything at once; Progress redraws when it comes back, so a discarded session is gone from it | CindyCore `ProgressDetailTests` (P12, S1) and `ProgressPageTests` | They open `RecordsActivity`, which P12 ported. The last two replaced the CLEAR sheet's test and the clearing test on 12 October; the badge test that follows them is among the 25 |
| `AccountScreenTest`, 7 of 35: choosing a photo opens the system picker; DONE closes the screen; the profile card opens the profile screen; the four `AvatarView` tests (it draws, it is a row's size, it is square, it is decoration until made a button) | CindyTracker, built by the macOS job | They start a screen or measure and draw a view. The same facts are held in the SwiftUI: a `PhotosPicker`, a `dismiss`, a `NavigationLink`, an `AvatarView` that is a square and hidden from VoiceOver |
| `ScreenSmokeTest`, the menu builds (also mid-workout, with a track chosen, with a watch paired, with the reminder on) and the voice row names its language | CindyCore `MenuPageTests` | Every row's subtitle, for every state |
| `ScreenSmokeTest`, the body-weight and heart-rate details sheets | CindyCore `ProfileFormsTests` | `BodyWeightForm`, `HeartRateDetailsForm` and `MovementsForm` hold what each asks, refuses and keeps |
| `ScreenSmokeTest`, the heart-rate sheet (with and without a watch) | P15 | The sheets are `HeartRateSheet` and `HeartRateScanSheet`, built by the macOS job; what they say is `HeartRateSheetsTests` |
| `ScreenSmokeTest`, the reminder row's sheet, the voice sheet's language list | P18, P10 | The scheduler and the language list (`LanguageGroupModelTests`, P10) |

### Kotlin tests that were ported in P14

The 59 screen tests of `TutorialScreenTest` (29), `HelpScreenTest` (10) and `LicencesTest` (3), and the 17 of `HudTourTest`, which Robolectric ran against the inflated screens. The same facts are read off what the core returns for the screen to draw, each test named after the Kotlin one, and the part that is a platform's (a view laid out and drawn, a button pressed, a screen started) stays with the SwiftUI layer and the UI tests the macOS job runs.

| Kotlin test | Lands in | Because |
|---|---|---|
| `TutorialScreenTest` (29) | CindyCore `TutorialPagesTests` (29, and 3 for the model's edges) | The pages, buttons, dots, swipe rule and what ending does are `TutorialModel`. "Each page builds and lays out at phone size" is a layout pass on Android; here it holds that every page has a title and something to draw. The back button is the two-finger escape gesture on iOS. The four flag tests are `FirstRun`'s, which `OnboardingTests` also holds |
| `HelpScreenTest` (10) | CindyCore `HelpPageTests` (10, and 8 for the tiers and for a build without each part) | `HelpBuilder` writes every section and the tests read the strings off the `HelpPage`. One Kotlin expectation is inverted on iOS: Android pins "Hold +1" as stale because SKIP is a button there; the iOS camera screen has no SKIP button, so Help says to hold +1 and the test pins that |
| `LicencesTest` (3) | CindyCore `LicencesTests` (3, and 3 for what iOS changes) | The credits and the shipped texts are held to each other, reading the texts from the folder the app bundles them from. Apache-2.0 is not shipped (nothing under it is in the iOS app) and Apple's frameworks are credited without a licence text |
| `HudTourTest` (17) | CindyCore `SpotlightTourTests` (17, and 2 for the arithmetic) | `SpotlightTour` is the tour's state and `SpotlightMath` its card; the Android layout is stood in for by two bands of controls on a 1080 by 2400 screen. `HudTourTests` (P8) still holds the seven steps to `HudTour.kt` word for word |
| The five parts of the app that arrive in later phases (heart rate, filming, music, the reminder, Strava) | `HelpFeatures` | Help describes a part only when it is switched on; `HelpPageTests` holds that each is described exactly when it is |

### Kotlin tests that were ported in P15

The 12 pure tests (`HeartRateAdvertTest` 9, `BleHeartRateSourceTest` 1, `HeartRatePermissionsTest` 2) and the 3 Robolectric tests of `HeartRatePermissionSheetTest`.

| Kotlin test | Lands in | Because |
|---|---|---|
| `HeartRateAdvertTest` (9), `BleHeartRateSourceTest` (1) | CindyCore `HeartRateAdvertTests` (10, and 3 more) | The same facts, line for line; `reconnectDelayMs` is `HeartRateReconnect.delayMs` |
| `HeartRatePermissionsTest` (2), `HeartRatePermissionSheetTest` (3) | CindyCore `HeartRateAccessTests` (5, and 3 more) | The Kotlin pins which Android permission is asked for by SDK, and that the location prompt is explained first before Android 12 and not after. iOS has one permission and nothing about location, so each is held as its iOS half: only Bluetooth, never location on any answer, no explanation before iOS asks, a denial goes to Settings |
| (none) | CindyCore `HeartRateSheetsTests` (9) | `MenuActivity` builds the heart-rate sheets in code and no Kotlin test reads them except through the screen: the status line and its hints, the signal bands, the row labels, what pairing keeps, the silent-watch warning |

### Tests written for P16

Android has no test of its own for the recording overlay or the recorder; `MainActivity`'s REC flow is covered only through `CountdownTest` (ported in P6) and the transform through `OverlayTransformTest` and `RecordedHudTest` (ported in P5 and P4).

| Lands in | What it holds |
|---|---|
| CindyCore `FilmFlowTests` (15) | A tap in the Android screen's order: a count is called off, a film is stopped, a camera that cannot film says so, then Photos is asked and refused or agreed before the count. What the far side of the count and a finished film say, and which of them are said aloud. What leaving does. The control's words in each state. A film's name |
| CindyCore `RecordingLayoutTests` (12) | Every panel and word is inside the safe area and none in the strip fill-centre crops (with the same layout on the whole frame shown to fail it), the corners, the sizes, the banner centred in the safe area, the watermark |
| CindyCore `SessionRecordedHudTests` (8) | The session feeds the film's HUD: fresh, setup check, both banners and their three seconds, a rep, a round, an undo, a reset |

### Tests written for P17

Android has no test of `MusicPlayer`, `syncMusic` or the music sheet beyond the menu row's two subtitles (`ScreenSmokeTest`, already in `MenuPageTests`) and the Help text (`HelpPageTests`).

| Lands in | What it holds |
|---|---|
| CindyCore `MusicFlowTests` (16) | The voice leaves 18% and ducking multiplies, never raises; a level is held to 0 to 1; the track starts with the clock if it is on, is held by a pause and put back at the top by the end or a reset; what returning from the menu does; a loaded track is not reloaded; a track is named without its last extension; the sheet's card and buttons; the menu row and the sheet agree about a track that cannot be opened |

**iOS deviation from the plan:** the plan says "tap to pick or mute, long press to change", which is how Android's HUD chip behaved until the music moved into the menu. Android now has a Music row and a sheet (a toggle, a volume, CHANGE TRACK and LISTEN), and iOS follows that, as the Kotlin is the specification.

### Kotlin tests that were ported in P18

The 10 Robolectric `ReminderDeliveryTest`s ran the real scheduler, receiver and notifier against Robolectric's alarm manager and notification manager. iOS has neither, so each is held as the plan that replaces it.

| Kotlin test | Lands in | Because |
|---|---|---|
| `turning the reminder on arms one alarm at the chosen time` | CindyCore `ReminderPlanTests` (`TurningTheReminderOnArmsTheFirstAtTheChosenTime`) | The first request is at the chosen time |
| `opening the app does not postpone a reminder that is due`, `opening the app arms a reminder when none is armed` | `OpeningTheAppDoesNotPostponeAReminderThatIsDue`, `OpeningTheAppArmsAReminderWhenNoneIsArmed` | Planning again holds the same requests, by id |
| `turning it off cancels the alarm` | `TurningItOffCancelsThemAll` | An off setting plans nothing, and the centre removes what was held |
| `a day with no session gets a reminder`, `a day already trained stays quiet but re-arms` | `ADayWithNoSessionGetsAReminder`, `ADayAlreadyTrainedStaysQuietButTheRestAreStillPlanned` | |
| `a live workout silences it` | `ALiveWorkoutSilencesIt` | `willPresent` shows nothing during one |
| `without notification permission it stays quiet but still re-arms` | `WithoutPermissionNothingIsScheduledUntilItIsGiven` | Coming forward asks iOS again and plans again |
| `a reminder hours late is dropped`, `boot re-arms the reminder` | (none) | iOS delivers on time and keeps scheduled notifications across a restart |

The rest of `ReminderPlanTests` (8) holds what iOS adds: a week of requests with stable ids, the week starting tomorrow once today's time has passed, tomorrow's words knowing today was trained, a saved session taking today's request away, a time zone change, a clock change, the sheet's permission steps and words, and the menu row's honesty.

### Kotlin tests that were ported in P19

| Kotlin test | Kotlin | Swift | In |
|---|---|---|---|
| `StravaHttpTest` | 16 | 16 | `StravaHttpTests` |
| `StravaPayloadTest` | 15 | 15 | `StravaPayloadTests` |
| `StravaSetsTest`, the one that stayed (`the adaptive profile on the attempt reaches StravaPayload's mapping`) | 1 | 1 | `StravaPayloadTests` |
| `StravaActivityTextTest` | 23 | 23 | `StravaActivityTextTests` |
| `StravaHeartRateTest` | 6 | 6 | `StravaHeartRateTests` |
| `StravaApiTest` | 25 | 25 | `StravaApiTests` |
| `StravaAuthTest` | 23 | 23 | `StravaAuthTests` |
| `StravaSessionTest` | 6 | 6 | `StravaSessionTests` |
| `StravaUploadsTest` | 7 | 7 | `StravaUploadsTests` |
| | **122** | **122** | |

Written for the port, with no Kotlin test behind them (49): `StravaConfigTests` (4), `StravaTokenStoreTests` (9), `URLSessionTransportTests` (6), the composer's five and one past-the-start sample in `StravaHeartRateTests`, one on the instant's text in `StravaPayloadTests`, six on how replies are read, and on a transport that refuses a request, in `StravaApiTests`, seven on the redirect's edges, on no attempt being in flight and on an unreadable token reply in `StravaAuthTests`, four on the refresh window, on failures that must not disconnect and on a caller cancelled while it waits in `StravaSessionTests`, and six on the ledger's decisions in `StravaUploadsTests`.

`FakeTransport` is `FakeTransport.kt`, and is the double for all of it.

**What iOS does differently, and why:**

- **Calls are `async`.** `URLSession` is, and the worker thread Android blocks on has no twin. `StravaAccessToken.get()`, `StravaApi`, `StravaAuth` and `HttpTransport.execute` all `async throws`.
- **`StravaConfig` is a value**, built once from the app's `Strava.xcconfig` (P20), not an `object` over `BuildConfig`. `authorizeUri` and `StravaAuth` take it. The `availableForTest` seam has nothing to do: a test builds a config with credentials, or without.
- **The grant is one stored item**, not five prefs keys. Android writes them in one `commit()`, which is atomic; five Keychain items are not, and a new access token beside the old refresh token (already invalidated by Strava) would strand the athlete.
- **The session's lock is an async lock**, shared by every session in the process. Android's `synchronized` cannot be held across the network call.
- **`StravaStorage`** (strings by key) is what the Keychain fills in P20. The ledger and the grant share it, as Android's share the `strava` prefs file, and for the same reason: out of backups.
- **`require` throws** (`StravaPayloadError`); `IOException` is `HttpTransportError`; `StravaAuthException` is `StravaAuthError`; Android's `JSONException` out of the token calls is `StravaResponseError`, which the upload treats as worth retrying.
- **The redirect is read by rules checked against `java.net.URI`**, not `URL(string:)`, which on current Apple systems repairs a string (a space becomes `%20`) that Android refuses.
- **No attempt in flight cannot match.** `parseRedirect` takes the expected state as optional, and nil or empty is a mismatch. Android's handler drops the redirect before it gets there; this does not rely on the caller, because an empty expectation would match a crafted `state=` and bind the athlete's account to someone else's Strava.
- **A request the transport refuses** (not https, not a URL) is `HttpRequestRefused`, which escapes `StravaApi` as Android's `ClassCastException` escapes the worker. It is not an `HttpTransportError`, which means the network failed and is retried.
- **A caller cancelled while it waits for the refresh lock** throws `CancellationError` instead of going on to refresh; a suspended app's background time runs out mid-wait.
- **Not here:** the upload's scheduling. `StravaUploads` is the ledger and its decisions; WorkManager's part (a network, a backoff, surviving a restart) is the app's, from the ledger, in P20.

**Worth knowing** (Android behaviour that is ported as it is, not fixed):

- `optString` on a JSON `null` is the word "null" on Android, so a token reply with `"firstname": null` names the athlete "null Smith". Strava sends strings. Kotlin's unit tests run on the `org.json` Maven artifact, which says "" for the same input; the shipped app does not.
- A refresh reply carries no athlete and no scope, so after the first refresh (about six hours after connecting) the stored grant has no name and no scopes, and the menu says "Connected · Strava" instead of the athlete's name. Android does the same; nothing reads the scopes.
- Every 4xx but 401 and 429 is a permanent rejection, so a 408 or 425 marks the upload failed. Android does the same.
- Android's parser reads some things this one refuses (single quotes, text after the closing brace). Strava sends strict JSON, so no real reply tells them apart.
- A repeated response header reaches Kotlin as a list and `URLSession` as one comma-joined value. Only `Retry-After` is read, and it is sent once.

### Kotlin tests that were ported in P20

| Kotlin test | Kotlin | Swift | In |
|---|---|---|---|
| `StravaScreenTest` | 18 | 18 | `StravaScreenTests` |
| `StravaConsentTest` | 7 | 7 | `StravaConsentTests` |
| `StravaUploadWorkerTest` | 18 | 18 | `StravaUploadWorkerTests` |
| | **43** | **43** | |

(`StravaSessionTest`, the plan's fourth file, is P19's: see above.) Robolectric built each activity and read its views; the same facts are read off the models the screens draw from (`MenuPage`, `StravaSheet`, `StravaRow`, `StravaRedirectHandler`), so they run on Linux. `NoStravaCredentials` is a `StravaConfig` that is not `available`, and `availableForTest` is gone. The manifest test that holds the redirect scheme to the application id reads `ios/project.yml`.

Written for the port, with no Kotlin test behind them (20): `StravaUploadQueueTests` (12: what WorkManager did for Android), five in `StravaScreenTests` (a good redirect through to a connected athlete, a redirect that cannot be exchanged, one without the write scope, disconnecting offline, the sheet's words), two in `StravaConsentTests`, one in `HelpPageTests`. Two UI tests run in the simulator: a build with no credentials has no Strava on its menu, and with `-CindyStrava` (debug builds only) the row asks first and NOT NOW starts nothing.

**What iOS does differently, and why:**

- **No WorkManager.** The ledger is the persisted queue and `StravaUploadQueue` drains it (see the `StravaUploadWorker.kt` row). A drain interrupted by the system leaves the attempt pending, never failed.
- **The consent page opens in the Strava app** when it is installed, otherwise in `ASWebAuthenticationSession`, which also catches the redirect. Closing the web sheet without an answer takes back the state that was minted.
- **The Keychain outlives the app** and Android's prefs do not, so a fresh install wipes it (and the ledger with it).
- **The forced refresh after a 401 takes the session's lock**, which Android's worker does not.
- **A request the transport refuses is not retried** (`HttpRequestRefused`), and neither is an upload that cannot be prepared: it is marked failed where the athlete can see it.
- **Help's upload paragraph** says it is sent when the workout is saved and tried again when Cindy is open or a connection returns, instead of "carries on in the background".
- **Credentials** come from `ios/Config/Strava.xcconfig`, gitignored, through an optional include; the values reach `Info.plist`. Without the file the build has none.

### Kotlin tests that were ported in S1

The tests Android added or changed on 12 October (S1 in `PLAN.md`): 39 of them, 30 ported now.

| Kotlin test | Lands in | Because |
|---|---|---|
| `CameraStabilityTest`, the 4 new (11) | CindyCore `CameraStabilityTests` | The same rotation matrices, built with the same helpers; the tremor test also shows the old azimuth moving more than 8 degrees |
| `WatchLinkTest` (10) | CindyCore `WatchLinkTests` | Pure rules. One more test, written for the port, holds the flag under Android's key in `OnboardingTests` |
| `RecordStoreTest`, 2 new (4) | CindyCore `RecordStoreTests` | |
| `HeartRateStoreTest`, 1 new (4); `RepTimesStoreTest`, 1 new (4) | CindyCore `HeartRateStoreTests`, `RepTimesStoreTests` | |
| `SessionDiscardTest`, 2 of 3 | CindyCore `SessionDiscardTests` | The third cancels the queued Strava upload and forgets the ledger entry: P19 |
| `ScreenSmokeTest`, 1 renamed and 4 new (67): reopening shows DISCARD beside DONE; after a workout the page offers DISCARD; a result never saved has nothing to discard; DISCARD asks first and KEEP IT leaves the session; confirming removes it | CindyCore `ResultsPageTests` (2 new, 1 renamed) and `ResultsDiscardTests` (the two that ask and confirm) | The assertions read the bar and the sheet off the inflated screen; here they read `ResultsPage.actions` and `DiscardQuestion`. That KEEP IT is the filled button and that confirming closes the page are the SwiftUI layer's, and `testASessionCanBeDiscardedFromItsPage` holds them in the simulator |
| `StravaScreenTest`, 2 new (20) | CindyCore `ResultsDiscardTests`, the sheet's wording | `onStrava` is false until P20 feeds it from the ledger |
| `AccountScreenTest`, 3 of 35 (see P13) | CindyCore `ProgressDetailTests`, `ProgressPageTests`, `AccountPageTests` | |
| `HelpScreenTest`, `PlayPolicyTest` (a phrase each) | P14, P21 | Help and the listing do not exist on iOS yet |
| `StravaUploadsTest`, `reachedStrava` | P19 | Strava |
| `HeartRateSheetCopyTest` (3) | P15 | The heart-rate sheet is built there |

### Kotlin tests with no Swift counterpart

| Kotlin test | Because |
|---|---|
| `ExecutorReleaseTest` (2) | `ExecutorRelease` closes a native model after the frame using it, which only Android needs: see its row below |
| `AndroidTtsEngineTest` (13) | Robolectric's shadow of Android's `TextToSpeech`: what its constants mean. iOS has none of them; the translation it does have is `AppleVoiceMapping`, held by `AppleVoiceMappingTests` (written for the port) |
| `SpeakerTest`, `the default stack says something once Android says it is ready` | Drives the real Android engine. `AVSpeechTtsEngine` needs a device |
| `SpeakerTest`, `an engine that fails to answer does not stop the questions after it`; `LanguageGroupTest`, `an engine that stays silent is asked less often` | Kotlin's engine could throw from `getVoices`. A Swift `TtsEngine` cannot throw, so both are held with an engine that answers nothing (and one that never connects) instead, as their doc comments say |

### What the Kotlin leans on, which Swift has no counterpart for

| Phase | Kotlin / JDK | Lands in | Status |
|---|---|---|---|
| P8 | `java.time` (`LocalDate`, `YearMonth`, `DayOfWeek`, `ZoneId`, `ZonedDateTime`) | CindyCore `LocalCalendar`: a day count, no `Calendar` and no locale data, with `java.time`'s rule for a local time the clock skips or repeats. Checked against `java.time` on 8 zones through 2025 and 2026 | tests written for the port |
| P8 | `String.format(Locale.US, "%,d" / "%.Nf")`, `Math.round`, `roundToInt`, `sortedBy`, `maxByOrNull` | CindyCore `JavaText`. `%.Nf` rounds the shortest digits half up, which is not what C does (this corrected P5's `javaFixed`), and was checked against a JVM on 326,044 values at five precisions | tests written for the port |
| P9 | `kotlin.random.Random(seed)`, which `CaloriesTimelineTest` draws its 250 generated traces from | CindyFixtures `KotlinRandom`: xorwow, and Kotlin's own rejection loops for `nextInt(from, until)` and `nextLong(from, until)`, so the Swift test sees the traces the Kotlin one did. Checked against a JVM for both seeds the tests use, and for powers of two | tests written for the port |
| P9 | `String.toIntOrNull` / `toLongOrNull` | `Records.toInt` / `toLong`, which now read any Unicode decimal digit, as Kotlin does (`Character.digit`). Swift's parsers read ASCII only, so a saved file with an Arabic-Indic number decoded on Android and not here. Found by the P9 cross-check; fixed for every codec at once | tests written for the port |
| P19 | `org.json` (`has`, `isNull`, `getString`, `getLong`, `optString`) | CindyCore `JsonObject`, over `JSONSerialization`, answering as Android's does (a `null` is the text "null", a numeric string is a number, a boolean is not) |
| P19 | `java.net.URI`, `URLDecoder`, `URLEncoder` | `StravaAuth`'s redirect reader, checked against `java.net.URI` on 19 strings, and `FormBody.encodePart` (a space is a plus, `~` is escaped, `.-*_` stay) |
| P19 | `Instant.toString()` | `StravaPayload.isoInstant`, from the day count, so no platform formatter is involved |
| P19 | `HttpsURLConnection` | `URLSessionTransport`: https only, no redirects followed, no cookies or cache |
| P19 | `synchronized`, `SharedPreferences` | `AsyncLock` and `StravaStorage` |
| P20 | `WorkManager` (unique work, a network constraint, exponential backoff, resuming after a process death), `LiveData` of work info | `StravaUploadQueue` over the ledger, driven by `StravaCenter`: `beginBackgroundTask`, `NWPathMonitor`, `BGAppRefreshTask`, and a redraw when the storage is written to |
| P20 | `Intent.ACTION_VIEW` on Strava's authorize URL, the manifest's intent filter | `strava://oauth/mobile/authorize` or `ASWebAuthenticationSession`, `CFBundleURLTypes`, `onOpenURL` |

### Not a Kotlin file

| Phase | Python | Lands in | Status |
|---|---|---|---|
| P7 | `tools/video_regression/run_batch.py` (the scoring: setup engine, scoring engine, `cindy` mode with `setup` and `skipTo`, the report) | `ios/CindyClips` `ClipScoring`, which `ReportTests` hold to `run_batch.py`'s keys and which was run against `run_batch.py` itself on the same frames | tests ported |
| P7 | `tools/video_regression/cindy_sim/pose_detector.py` (MoveNet and its crop) | not ported: Vision is the model, through `CindyVision`; `run_batch.py`'s `dim` (the low-light model) is ported as `LightModel` | not ported |

| Phase | Kotlin file | Lands in | Status |
|---|---|---|---|
| P2 | `BarZone.kt` | CindyCore | tests ported |
| P2 | `CameraStability.kt` | CindyCore, with `CameraLook` (S1: the heading and elevation of the axis the camera looks along, from Android's rotation matrix). S2 feeds it: CindyCore `CameraMotion` reads Core Motion's matrix (its layout picked by gravity, with the elevation from gravity returned beside it for the debug readout), CindyTracker `PhoneMotion` runs `CMMotionManager` at 16 Hz and `WorkoutSession.cameraMoved` decides what a knock does. Built by the macOS job; the angles want an iPhone | tests ported |
| P2 | `PoseGeometry.kt` | CindyCore | ported |
| P2 | `PosePrediction.kt` | CindyCore | tests ported |
| P2 | `RepCounter.kt` | CindyCore | tests ported |
| P2 | `SmartSquatCounter.kt` | CindyCore | tests ported |
| P2 | `StartPoses.kt` | CindyCore | ported |
| P2 | `TrackingHealth.kt` | CindyCore | tests ported |
| P2 | `Variations.kt` | CindyCore | tests ported |
| P2 | `WorkoutEngine.kt` | CindyCore | tests ported |
| P3 | `Comparisons.kt` | CindyCore | tests ported |
| P3 | `Levels.kt` | CindyCore | tests ported |
| P3 | `LiveWorkout.kt` | CindyCore | ported |
| P3 | `RecordStore.kt` | CindyCore (`Records`, format v1 to v7) and a `RecordStore` over `UserDefaults`, with `remove(atMillis:)` (S1) | tests ported |
| P3 | `RepLog.kt` | CindyCore | tests ported |
| P3 | `RepTimesStore.kt` | CindyCore (format + file store), with `remove(atMillis:)` (S1) | tests ported |
| P3 | `RoundSplits.kt` | CindyCore | tests ported |
| P3 | `SessionStats.kt` | CindyCore | tests ported |
| P3 | `SplitBook.kt` | CindyCore | tests ported |
| P3 | `StravaSets.kt` (with `WorkoutSet`, from `StravaPayload.kt`) | CindyCore | ported |
| P4 | `Coach.kt` | CindyCore | tests ported |
| P4 | `Phrasebook.kt` | CindyCore | ported |
| P4 | `PhrasebookDe.kt` | CindyCore | tests ported |
| P4 | `PhrasebookEn.kt` | CindyCore | tests ported |
| P4 | `PhrasebookEs.kt` | CindyCore | tests ported |
| P4 | `PhrasebookFr.kt` | CindyCore | tests ported |
| P4 | `PhrasebookIt.kt` | CindyCore | tests ported |
| P4 | `PhrasebookNl.kt` | CindyCore | tests ported |
| P4 | `PhrasebookPl.kt` | CindyCore | tests ported |
| P4 | `PhrasebookPt.kt` | CindyCore | tests ported |
| P4 | `PhrasebookRo.kt` | CindyCore | tests ported |
| P4 | `PhrasebookRu.kt` | CindyCore | tests ported |
| P4 | `PhrasebookTr.kt` | CindyCore | tests ported |
| P4 | `Plurals.kt` | CindyCore | tests ported |
| P4 | `RecordedHud.kt` | CindyCore. From P16 `WorkoutSession` feeds it itself (the round and count from `apply`, the banners from the two ways the setup check ends) instead of the screen doing it | tests ported |
| P4 | `TtsEngine.kt` | CindyCore (protocol) | ported |
| P4 | `VoiceChoice.kt` | CindyCore | tests ported |
| P4 | `VoiceDirector.kt` | CindyCore | tests ported |
| P4 | `VoiceHints.kt` | CindyCore | tests ported |
| P4 | `VoiceLanguageText.kt` | CindyCore | tests ported |
| P4 | `VoiceLine.kt` | CindyCore | ported |
| P4 | `VoicePacks.kt` | CindyCore | tests ported |
| P5 | `FrameHandoff.kt` | CindyCore | tests ported |
| P5 | `FrameLatency.kt` | split: `Rolling`/`RateMeter`/probe maths → CindyCore, camera timestamps → CindyTracker (one host clock on iOS) | tests ported |
| P5 | `OverlayTransform.kt` | CindyCore (pure maths, ported with its tests) | tests ported |
| P5 | `OverlayView.kt` | CindyTracker (iOS rewrite: `SkeletonOverlay`) | ported |
| P5 | `PoseDetector.kt` | CindyCore `RoiTracker` (crop decisions), CindyVision `VisionFrameAnalyser` (the crop, Vision, following the body) and CindyTracker `VisionPoseSource`; the model, the model-input fill and the brightness lift (`softGain`) are not ported | ported |
| P5 | `YuvCrop.kt` | not ported — Android YUV path; Vision's `regionOfInterest` replaces it | not ported |
| P6 | `CindySheet.kt` | CindyTracker (iOS rewrite): native `confirmationDialog`s for skip and stop, and system sheets (`NavigationStack` with Save and Cancel) for the menu's choices; the Android sheet's own styling is not copied | ported as native |
| P6 | `CindyViews.kt` | CindyTracker (iOS rewrite) | not started |
| P6 | `CountdownView.kt` | CindyCore `Countdown` (the timing, ported with its tests) and, from P16, CindyTracker `CountdownOverlay` (the vignette, ring, digit and caption) driven by `FilmModel` | tests ported |
| P6 | `Dialogs.kt` | CindyCore `ProfileForms` (`BodyWeightForm`, `HeartRateDetailsForm`, `MovementsForm`; what each sheet asks, refuses and keeps) and CindyTracker `ProfileSheets` (the fields and lists). A comma is accepted for the point in a weight, because the number pad of a phone set to many languages types one | tests written for the port |
| P6 | `LaunchView.kt` | CindyTracker (iOS rewrite) | not started |
| P6 | `MainActivity.kt` | CindyCore `WorkoutSession` (the decisions) and CindyTracker `WorkoutViewModel`/`ContentView` (the plumbing); music, heart rate, filming and the tour land in later phases. The phone-moved check (`onCameraMoved`) is S2's: `WorkoutSession.cameraMoved` decides, `PhoneMotion` over `CMMotionManager` feeds the monitor and `WorkoutViewModel.cameraMoved` performs | behind |
| P6 | `PlacementFacts.kt` | CindyCore (the three facts) | ported |
| P6 | `PlacementGuideView.kt` | CindyTracker (iOS rewrite): `PlacementGuideView` | ported |
| P6 | `StartPoseView.kt` | CindyTracker (iOS rewrite) | not started |
| P8 | `Avatar.kt` | CindyCore | tests ported |
| P8 | `Badges.kt` | CindyCore | tests ported |
| P8 | `CalendarGrid.kt` | CindyCore | tests ported |
| P8 | `Cheer.kt` | CindyCore | tests ported |
| P8 | `Equivalents.kt` | CindyCore; whether an emoji can be drawn is the `EmojiFont` protocol | tests ported |
| P8 | `FirstRun.kt` | CindyCore (the flags) over `UserDefaults`; the Kotlin has no test, so the Swift ones are new | ported |
| P8 | `HudTour.kt` | CindyCore (the list of seven steps: control, title, words); the spotlight that draws it is P14. `HudTourTest` inflates the Android layout, so what is held to the Kotlin is the list, read from `HudTour.kt` | ported |
| P8 | `Lifted.kt` | CindyCore | tests ported |
| P8 | `Onboarding.kt` | CindyCore, with the watch offer's "Don't ask again" flag, `watch_offer_silenced` (S1) | tests ported |
| P8 | `Peaks.kt` | CindyCore | tests ported |
| P8 | `Progress.kt` | CindyCore | tests ported |
| P8 | `Reminder.kt` | CindyCore | tests ported |
| P8 | `SpotlightMath.kt` | CindyCore | tests ported |
| P8 | `StatTiles.kt` | split: `SessionTiles` → CindyCore (P8, tests ported), the tile views → CindyTracker (P11) | tests ported |
| P8 | `Streak.kt` | CindyCore | tests ported |
| P9 | `Calories.kt` | CindyCore | tests ported |
| P9 | `HeartRate.kt` | CindyCore (the types, the Bluetooth profile's UUIDs, measurement parsing, the `HeartRateSource` protocol). `HeartRateSources.forProfile` builds the Android Bluetooth source, so it comes with the Core Bluetooth one in P15 | tests ported |
| P9 | `HeartRateRecorder.kt` | CindyCore | tests ported |
| P9 | `HeartRateStats.kt` | CindyCore | tests ported |
| P9 | `HeartRateStore.kt` | CindyCore: the trace format (`HeartRateTraces`) and the file store over a folder, as `RepTimesStore` is (nothing here needs the app target), with `remove(atMillis:)` (S1) | tests ported |
| P9 | `SessionTimeline.kt` | CindyCore. Kotlin's `Readout` is `TimelineReadout`, because P8's progress `Readout` already holds the name | tests ported |
| P10 | `AndroidTtsEngine.kt` | CindyTracker `AVSpeechTtsEngine` over CindyCore `AppleVoiceMapping` (what a system voice is called to the director). iOS lists only installed voices, so a voice is never "not fetched" and none is online; the engine itself needs a device and is built by the macOS job | ported |
| P10 | `LanguageGroup.kt` | CindyCore `LanguageGroupModel` (every decision: rows, taps, settling, downloads, previews, polling) and CindyTracker `LanguageSheet` (the SwiftUI list over it). "Manage voices" explains Settings → Accessibility → Spoken Content → Voices instead of opening an engine's screen | tests ported |
| P10 | `Speaker.kt` | CindyCore `Speaker`, with its main-thread and background dispatchers injected; the workout now speaks through it | tests ported |
| P11 | `ResultsActivity.kt` | CindyCore `ResultsPageBuilder` / `ResultsModel` (which cards show, what each says, the comparison chosen, the lines that follow the fingers) and CindyTracker `ResultsView` over `ResultsViewModel` (the SwiftUI page). The Strava row (P19) and the PROGRESS button (P12) are not drawn; a reopened session offers DISCARD and DONE, a page that has just ended PROGRESS, DISCARD and DONE, and DISCARD is absent for a result that was never saved (S1: `ResultsPage.actions`, `DiscardQuestion`, `ResultsModel.discard`; the dialog is the system's `confirmationDialog` with KEEP IT as the cancel role, and the screen underneath says "Session discarded", since a dismissed sheet takes its own overlay with it). Whether a copy is on Strava is fed by the ledger in P20 | tests ported; the screen is built by the macOS job and still wants a real session on an iPhone at the smallest and largest text sizes |
| P11 | `RoundSplitsView.kt` | CindyCore `RoundSplitsChartModel` and CindyTracker `RoundSplitsView` (`Canvas`) | tests ported |
| P11 | `RoundTrackView.kt` | CindyCore `RoundTrackModel` and CindyTracker `RoundTrackView` (`Canvas`) | tests ported |
| P11 | `SessionTimelineView.kt` | CindyCore `SessionTimelineChartModel` and CindyTracker `SessionTimelineView` (`Canvas`) | tests ported |
| P11 | `SessionTimelineView.kt`, `snapPoints` | **Deliberate difference.** The Kotlin starts `lastKept` at `Long.MIN_VALUE`, and `clockMs - Long.MIN_VALUE` overflows, so on a lane that is not stepped (a heart rate with no reps) it keeps no point and the scrub never ticks. Swift keeps the first point, as the Kotlin comment says it should. Found by the P11 mutation check; the Android app still has it | tested in `ChartDetailTests` |
| P11 | `ZoneBarView.kt` | CindyCore `ZoneBarModel` and CindyTracker `ZoneBarView` (`Canvas`) | tests ported |
| P12 | `CalendarView.kt` | CindyCore `CalendarModel` (the month's cells, taps, stops and words) and CindyTracker `CalendarGridView` (`Canvas`) | tests ported |
| P12 | `ProgressChartView.kt` | CindyCore `ProgressChartModel` (points, bars, the best-so-far steps, touch, stops) and CindyTracker `ProgressChartView` (`Canvas`) | tests ported |
| P12 | `RecordsActivity.kt` | CindyCore `ProgressPageBuilder` and `ProgressModel` (which cards show and what each says: the habit, this week, the chart card and its chips, peaks, the calendar's paging, the leaderboard, a day's sessions) and CindyTracker `ProgressScreen` over `ProgressViewModel`. Since S1 there is no CLEAR, as on Android: a session is discarded from its own page, and `ProgressModel.reloadIfChanged` builds the page again when the sheet of a session opened from here goes and the board changed. Reached from the results page's PROGRESS button and, until the menu (P13), a PROGRESS chip on the camera screen | tests ported; the screen is built by the macOS job and still wants a look on an iPhone |
| P12 | `WeekStripView.kt` | CindyCore `WeekStrip` and CindyTracker `WeekStripView` (`Canvas`) | tests written for the port (`WeekStripView` has none) |
| P13 | `AccountActivity.kt` | CindyCore `AccountBuilder` (the header, the 26 badges by family, each tile's spoken sentence and its sheet) and `NameForm` / `PhotoSheet`, and CindyTracker `AccountScreen` with `PhotosPicker` for the photo | tests ported |
| P13 | `AvatarStore.kt` | CindyCore `AvatarFiles` (exists, load, clear with its partial, store whole or not at all, by `rename(2)`), and CindyTracker `AvatarImporter`: ImageIO decodes no bigger than the short side needs and stands the picture upright from its orientation tag, so `Avatar.upright` and `Avatar.sampleSize` are not used on iOS; the square and the 320 px are `Avatar`'s. The file is `avatar.jpg` in Application Support, which iCloud backup carries | file handling tested; the decoding is built by the macOS job |
| P13 | `AvatarView.kt` | CindyTracker `AvatarView` (SwiftUI): the photo, else the letters of the name, else a neutral figure; the initials are `Avatar`'s | built by the macOS job |
| P13 | `MenuActivity.kt` | CindyCore `MenuBuilder` (the profile card, every row and what it says underneath, the live-workout refusal, the stagger of the entrance) and `VoiceForm`, and CindyTracker `MenuScreen`. A **MENU** chip on the camera screen opens it (the VOICE, LANG and PROGRESS chips are gone: the voice's switch, volume and language are one sheet now, as on Android). Only the rows that can be opened are shown: Movements, Progress, Body weight, Voice, Help (P14) and, from P15, Heart rate. Music (P17), Daily reminder (P18) and Strava (P20) are built and tested in the builder and are switched on with their screens | tests ported |
| P13 | `Profile.kt` | CindyCore `Profile` over `UserDefaults`, under Android's keys (the movement choice is `movement_profile`; the iOS app's own earlier `cindy.movementProfile` is not read, as no build was ever released). `WorkoutViewModel` reads every setting from it, and the session now gets `smartSquats`, which P6 had left unwired | tests ported |
| S1 | `SessionDiscard.kt` | CindyCore `SessionDiscard` over the three stores (the attempt first, then the heart-rate trace and the rep times). Strava's ledger joins it in P19, where `StravaUploads.forget` and `reachedStrava` are ported | tests ported but one: the Strava test is P19's |
| S1 | `WatchLink.kt` | CindyCore `WatchLinks`: whether a paired watch is sending, what START asks and why a silent watch is silent. Nothing asks the question until the Bluetooth link exists (P15) | tests ported |
| S1 | `ExecutorRelease.kt` | **Not ported.** It closes the TFLite interpreter on the analysis thread, after the frame in flight, because freeing it under that frame crashed Android. iOS frees nothing by hand: `VisionFrameAnalyser` is touched only on `VisionPoseSource`'s serial `queue`, `stop()` is queued behind the frame in flight, and ARC frees Vision's objects when the last reference goes. Read in `VisionPoseSource`, `CameraModel` and `CindyVision`: no `deinit`, no `close`, no unsafe pointer | not ported |
| S2 | `MainActivity.kt`, the rotation-vector listener | CindyTracker `PhoneMotion` (device motion at 16 Hz, started with the camera screen and stopped when it goes, when the app is backgrounded, or while the menu or the results are open over it, as `onResume`/`onPause` do; a matrix that matches gravity in neither layout is not fed to the monitor) over CindyCore `CameraMotion`. Android's rotation vector is magnetometer-corrected, so the corrected reference frame is used where the phone has it. Device motion needs no permission | built by the macOS job; the angles and the matrix layout want an iPhone |
| P14 | `AppLinks.kt` | CindyCore `AppLinks`, and the CrossFit address of `HelpActivity.SOURCE` beside it | tests ported |
| P14 | `HelpActivity.kt` | CindyCore `HelpBuilder` (every section, written as data) and CindyTracker `HelpScreen`. The words differ only where the app does: Photos for Movies/Cindy, iCloud Backup for Android's backup, Settings for the speech engine's own screen, a hold on +1 for the SKIP button. Heart rate, filming, music, the reminder and Strava are described only once their phase switches them on (`HelpContent.features`) | tests ported; the screen is built by the macOS job and still wants a look on an iPhone |
| P14 | `Licences.kt` | CindyCore `Licences`. The credits name Vision and Apple's frameworks (no licence text to carry) and Manrope under the OFL, whose text and five font files ship in the app. The Apache-2.0 text is not shipped: MoveNet, LiteRT, AndroidX, CameraX and Kotlin are not in the iOS app | tests ported |
| P14 | `SpotlightView.kt` | CindyCore `SpotlightTour` (which controls are lit, the step, the one-time end, the window and where the card sits) and CindyTracker `SpotlightOverlay`. The iOS camera screen has no SKIP button, so that step is left out, as the tour leaves out any control that is not showing | tests ported; the overlay is built by the macOS job |
| P14 | `TutorialActivity.kt` | CindyCore `TutorialModel` (the five pages and what each says, the buttons, the dots, the swipe, what ending does) and CindyTracker `TutorialScreen`. A first run asks for the camera when the pages end (`CameraModel.ensureAccess`); the second page opens the movement sheet; the placement diagram is drawn by `PlacementDiagram` | tests ported; the screen is built by the macOS job and still wants a look on an iPhone |
| P15 | `BleHeartRateSource.kt` | CindyTracker `CoreBluetoothHeartRateSource` (Core Bluetooth over the Heart Rate profile; a device's address is its identifier on this phone; a moved watch is found by name; Android's cache drop has no equivalent and a watch with no service is reported as not sending heart rate; the source waits for Bluetooth to come back instead of giving up), and `reconnectDelayMs` → CindyCore `HeartRateReconnect` | tests ported; the source is built by the macOS job and wants a watch and a strap on an iPhone |
| P15 | `HeartRatePermissions.kt` | CindyCore `HeartRateAccess` (what Bluetooth permits, in the order the Kotlin checks: no radio, permission, radio, scan). iOS has one Bluetooth permission and no location case, so Android's explanation sheet and Location-off sheet have no counterpart; `NSBluetoothAlwaysUsageDescription` is set in `project.yml` and a test holds it to the core's words | tests ported |
| P15 | `HeartRateScanner.kt` | CindyCore `HeartRateAdvert` and `FoundDevice` (matching, the list's order, rows relabelled not rebuilt) and CindyTracker `HeartRateScanner` (an unfiltered scan matched in software, plus peripherals already connected with the Heart Rate service, marked "Connected to this phone") | tests ported; the scanner is built by the macOS job |
| P16 | `RecordingOverlay.kt` | CindyCore `RecordingLayout` (every panel and word of the burned-in HUD, laid out inside `OverlayTransform.visibleSource` with the width of words handed in) and CindyTracker `FilmRecorder` (the skeleton and the words painted with Core Graphics). The buffer that feeds the analysis feeds the film, upright and mirrored as the preview is, so the map from the analysis frame onto the film is the identity; the Android matrix juggling for a differently sized, rotated or mirrored recording stream has nothing to do | `RecordingLayout` tested; the painting is built by the macOS job and wants a film watched from each camera |
| P16 | `VideoRecorder.kt` | CindyTracker `FilmRecorder` (`AVAssetWriter`, H.264, video only, so no microphone) and `FilmLibrary` (Photos, add-only, no album: D6), with CindyCore `FilmFlow` deciding what a tap does and says. Photos is asked before the count and not after the film. A film that cannot be written is reported when it ends, and counting carries on | `FilmFlow` tested; the recorder is built by the macOS job and wants a film watched from each camera |
| P17 | `MusicPlayer.kt` | CindyCore `MusicFlow` (the volume rules, 18% under the voice and multiplied not replaced; when it plays, holds and stops; what is done about the chosen track; the sheet's words) and CindyTracker `MusicPlayer` (`AVAudioPlayer`, looped, `.playback`), `MusicLibrary` (the picked file is remembered as a security-scoped bookmark, Android's persistable URI grant; the name is the file's, as `substringBeforeLast('.')` takes it) and `MusicSheet` (the Files picker through `fileImporter`). The workout plays it, pauses with it, and ducks it from `Speaker.onSpeakingChanged` | `MusicFlow` tested; the player and the sheet are built by the macOS job and want a track from Files, and a lapsed one, on an iPhone |
| P18 | `ReminderNotifier.kt` | CindyTracker `ReminderCenter` (permission, the requests, the words as a notification) and CindyCore `ReminderPlan` (what the sheet does about permission). iOS has no channels, so the channel's description has no counterpart | `ReminderPlan` tested; the centre is built by the macOS job and wants a notification delivered on an iPhone |
| P18 | `ReminderReceiver.kt` | Nothing runs when a notification fires on iOS, so the receiver's work (the text, the trained-today rule, the live-workout rule) is done beforehand: CindyCore `ReminderPlan` words each of the next seven days from the records, drops a day already trained and plans again after each session; the live-workout rule is `ReminderPlan.showsInApp`, used by `willPresent`. The "more than two hours late" rule has nothing to do, because iOS delivers on time; boot and update re-arms have no counterpart, because scheduled notifications survive both | tests ported |
| P18 | `ReminderScheduler.kt` | CindyCore `ReminderPlan` (the seven requests, with stable ids, so planning again never doubles or postpones one) and CindyTracker `ReminderCenter` (adds and removes them: on launch, whenever the app comes forward, after a saved session, on a time zone or clock change, and when the setting changes) | tests ported |
| P19 | `StravaActivityText.kt` | CindyCore `StravaActivityText` and `CalorieBasis` | tests ported |
| P19 | `StravaApi.kt` | CindyCore `StravaApi` (`async`; `UploadOutcome` has the same seven cases) and `JsonObject`, which reads a reply the way Android's `org.json` does | tests ported |
| P19 | `StravaAuth.kt` | CindyCore `StravaAuth`. `authorizeUri` and the three token calls take a `StravaConfig`; the redirect is read by rules checked against `java.net.URI` | tests ported |
| P19 | `StravaComposer.kt` | CindyCore `StravaComposer`, which throws where Kotlin's `require` fails. No Kotlin test; five written | ported |
| P19 | `StravaConfig.kt` | CindyCore `StravaConfig`, a value the app builds from `Strava.xcconfig` (P20), with `available` and `redirectUri`. No `BuildConfig`, no `availableForTest` | tests ported |
| P19 | `StravaHeartRate.kt` | CindyCore | tests ported |
| P19 | `StravaHttp.kt` | CindyCore `HttpRequest`, `HttpResponse`, `HttpTransport`, `FormBody`, `Multipart`, `StravaAuthError`, `StravaAccessToken`, and `URLSessionTransport` (`FoundationNetworking` on Linux) | tests ported; a real 3xx through Apple's `URLSession` wants a device |
| P19 | `StravaPayload.kt` | CindyCore `StravaExercises`, `StravaPayload`, `HrPoint`, `startMillisOf` | tests ported |
| P19 | `StravaTokens.kt` | CindyCore `StravaGrant`, `StravaTokenStore` and `StravaSession` over a `StravaStorage` protocol; the Keychain store behind it is `StravaKeychainStorage` in CindyTracker (P20) | tests ported |
| P19 | `StravaUploads.kt` | CindyCore `StravaUploads`: the ledger, the auto-upload decision, requeueing after a reconnect, clearing. The scheduling is P20's | tests ported |
| P20 | `StravaAuthActivity.kt` | CindyCore `StravaConnect` (mints the state and gives Strava's URL only once Strava's own button is tapped; clears the attempt a menu connect is not about) and `StravaRedirectHandler` (what the return meant, the exchange, the grant stored, what waited requeued, the attempt that sent the athlete queued), and CindyTracker `StravaCenter` (the Strava app by `strava://oauth/mobile/authorize` when `LSApplicationQueriesSchemes` finds it, otherwise `ASWebAuthenticationSession`; the Strava app's redirect arrives by `onOpenURL`). The redirect scheme is the bundle identifier, declared once in `project.yml` | tests ported; the round trip wants an iPhone |
| P20 | `StravaConsent.kt` | CindyCore `StravaConsent` (every word of the sheet, and `StravaSheet` for the connected one) and CindyTracker `StravaConsentSheet` and `StravaConnectedSheet`. Strava's two images are its own SVG path data, copied from the Android drawables into an asset catalog | tests ported; the sheets are built by the macOS job |
| P20 | `StravaUploadWorker.kt` | CindyCore `StravaUploadRun` (the worker's decisions, unchanged) and `StravaUploadQueue` (what WorkManager did: the ledger is the persisted queue; oldest first, one drain at a time, Android's backoff from 30 s to five hours). CindyTracker `StravaCenter` drains it right after a saved session inside `beginBackgroundTask`, when the app comes forward, when `NWPathMonitor` finds a network, when a retry falls due, and from a `BGAppRefreshTask`. An upload may wait until the app is next opened, and Help says so | tests ported; the scheduling wants an iPhone |
