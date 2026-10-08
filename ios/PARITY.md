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
| `VariationsTest`, `adaptive sessions count toward the streak` | P8 | It needs `Streak`. Ported in P8, in `VariationsTests` |

### Kotlin tests that stay with their view or their phase

| Kotlin test | Stays with | Because |
|---|---|---|
| `HudTourTest` (17) | P14 | Robolectric, against the inflated camera layout and the spotlight view |
| `ProgressChartViewTest` (4) | P11 | Taps and drags on the chart's `View` |
| `ReminderDeliveryTest` (10) | P18 | Arms and cancels Android alarms |
| `HeartRateAdvertTest` (7), `BleHeartRateSourceTest`, `HeartRatePermissionsTest`, `HeartRatePermissionSheetTest` | P15 | The Bluetooth link and the permission sheet; the pure advert matching and `reconnectDelayMs` move to CindyCore there |
| `SessionTimelineViewTest` (13) | P11 | The chart's `View` and its accessibility; the numbers it draws are `SessionTimelineTest`, ported here |
| `ProfileHeartRateTest` (8) | P13 | The profile screen's heart-rate card |
| `StravaHeartRateTest` | P19 | Strava's heart-rate stream |

### What the Kotlin leans on, which Swift has no counterpart for

| Phase | Kotlin / JDK | Lands in | Status |
|---|---|---|---|
| P8 | `java.time` (`LocalDate`, `YearMonth`, `DayOfWeek`, `ZoneId`, `ZonedDateTime`) | CindyCore `LocalCalendar`: a day count, no `Calendar` and no locale data, with `java.time`'s rule for a local time the clock skips or repeats. Checked against `java.time` on 8 zones through 2025 and 2026 | tests written for the port |
| P8 | `String.format(Locale.US, "%,d" / "%.Nf")`, `Math.round`, `roundToInt`, `sortedBy`, `maxByOrNull` | CindyCore `JavaText`. `%.Nf` rounds the shortest digits half up, which is not what C does (this corrected P5's `javaFixed`), and was checked against a JVM on 326,044 values at five precisions | tests written for the port |
| P9 | `kotlin.random.Random(seed)`, which `CaloriesTimelineTest` draws its 250 generated traces from | CindyFixtures `KotlinRandom`: xorwow, and Kotlin's own rejection loops for `nextInt(from, until)` and `nextLong(from, until)`, so the Swift test sees the traces the Kotlin one did. Checked against a JVM for both seeds the tests use, and for powers of two | tests written for the port |
| P9 | `String.toIntOrNull` / `toLongOrNull` | `Records.toInt` / `toLong`, which now read any Unicode decimal digit, as Kotlin does (`Character.digit`). Swift's parsers read ASCII only, so a saved file with an Arabic-Indic number decoded on Android and not here. Found by the P9 cross-check; fixed for every codec at once | tests written for the port |

### Not a Kotlin file

| Phase | Python | Lands in | Status |
|---|---|---|---|
| P7 | `tools/video_regression/run_batch.py` (the scoring: setup engine, scoring engine, `cindy` mode with `setup` and `skipTo`, the report) | `ios/CindyClips` `ClipScoring`, which `ReportTests` hold to `run_batch.py`'s keys and which was run against `run_batch.py` itself on the same frames | tests ported |
| P7 | `tools/video_regression/cindy_sim/pose_detector.py` (MoveNet and its crop) | not ported: Vision is the model, through `CindyVision`; `run_batch.py`'s `dim` (the low-light model) is ported as `LightModel` | not ported |

| Phase | Kotlin file | Lands in | Status |
|---|---|---|---|
| P2 | `BarZone.kt` | CindyCore | tests ported |
| P2 | `CameraStability.kt` | CindyCore | tests ported |
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
| P3 | `RecordStore.kt` | CindyCore (`Records`, format v1 to v7) and a `RecordStore` over `UserDefaults` | tests ported |
| P3 | `RepLog.kt` | CindyCore | tests ported |
| P3 | `RepTimesStore.kt` | CindyCore (format + file store) | tests ported |
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
| P4 | `RecordedHud.kt` | CindyCore | tests ported |
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
| P6 | `CindySheet.kt` | CindyTracker (iOS rewrite): native `confirmationDialog`s for skip and stop; the styled sheet lands with P13's menu | behind |
| P6 | `CindyViews.kt` | CindyTracker (iOS rewrite) | not started |
| P6 | `CountdownView.kt` | CindyCore `Countdown` (the timing, ported with its tests); the ring and digit are drawn with filming | tests ported |
| P6 | `Dialogs.kt` | CindyTracker (iOS rewrite) | not started |
| P6 | `LaunchView.kt` | CindyTracker (iOS rewrite) | not started |
| P6 | `MainActivity.kt` | CindyCore `WorkoutSession` (the decisions) and CindyTracker `WorkoutViewModel`/`ContentView` (the plumbing); music, heart rate, filming, the tour, and camera-moved detection land in later phases | behind |
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
| P8 | `Onboarding.kt` | CindyCore | tests ported |
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
| P9 | `HeartRateStore.kt` | CindyCore: the trace format (`HeartRateTraces`) and the file store over a folder, as `RepTimesStore` is (nothing here needs the app target) | tests ported |
| P9 | `SessionTimeline.kt` | CindyCore. Kotlin's `Readout` is `TimelineReadout`, because P8's progress `Readout` already holds the name | tests ported |
| P10 | `AndroidTtsEngine.kt` | CindyTracker (iOS rewrite) | not started |
| P10 | `LanguageGroup.kt` | CindyTracker (iOS rewrite) | not started |
| P10 | `Speaker.kt` | CindyTracker (iOS rewrite) | not started |
| P11 | `ResultsActivity.kt` | CindyTracker (iOS rewrite) | not started |
| P11 | `RoundSplitsView.kt` | CindyTracker (iOS rewrite) | not started |
| P11 | `RoundTrackView.kt` | CindyTracker (iOS rewrite) | not started |
| P11 | `SessionTimelineView.kt` | CindyTracker (iOS rewrite) | not started |
| P11 | `ZoneBarView.kt` | CindyTracker (iOS rewrite) | not started |
| P12 | `CalendarView.kt` | CindyTracker (iOS rewrite) | not started |
| P12 | `ProgressChartView.kt` | CindyTracker (iOS rewrite) | not started |
| P12 | `RecordsActivity.kt` | CindyTracker (iOS rewrite) | not started |
| P12 | `WeekStripView.kt` | CindyTracker (iOS rewrite) | not started |
| P13 | `AccountActivity.kt` | CindyTracker (iOS rewrite) | not started |
| P13 | `AvatarStore.kt` | CindyTracker (image I/O); square-crop maths already in `Avatar` | not started |
| P13 | `AvatarView.kt` | CindyTracker (iOS rewrite) | not started |
| P13 | `MenuActivity.kt` | CindyTracker (iOS rewrite) | not started |
| P13 | `Profile.kt` | CindyCore (values, tidy rules) + `UserDefaults` | not started |
| P14 | `AppLinks.kt` | CindyCore | not started |
| P14 | `HelpActivity.kt` | CindyTracker (iOS rewrite) | not started |
| P14 | `Licences.kt` | CindyTracker (iOS rewrite) | not started |
| P14 | `SpotlightView.kt` | CindyTracker (iOS rewrite) | not started |
| P14 | `TutorialActivity.kt` | CindyTracker (iOS rewrite) | not started |
| P15 | `BleHeartRateSource.kt` | CindyTracker; `reconnectDelayMs` → CindyCore | not started |
| P15 | `HeartRatePermissions.kt` | CindyTracker (iOS needs only Bluetooth; no location path) | not started |
| P15 | `HeartRateScanner.kt` | CindyTracker; pure `HeartRateAdvert` matching → CindyCore | not started |
| P16 | `RecordingOverlay.kt` | CindyTracker (iOS rewrite) | not started |
| P16 | `VideoRecorder.kt` | CindyTracker (iOS rewrite) | not started |
| P17 | `MusicPlayer.kt` | CindyTracker (iOS rewrite) | not started |
| P18 | `ReminderNotifier.kt` | CindyTracker (iOS rewrite) | not started |
| P18 | `ReminderReceiver.kt` | CindyTracker (iOS rewrite) | not started |
| P18 | `ReminderScheduler.kt` | CindyTracker (iOS rewrite) | not started |
| P19 | `StravaActivityText.kt` | CindyCore | not started |
| P19 | `StravaApi.kt` | CindyCore | not started |
| P19 | `StravaAuth.kt` | CindyCore | not started |
| P19 | `StravaComposer.kt` | CindyCore | not started |
| P19 | `StravaConfig.kt` | CindyCore | not started |
| P19 | `StravaHeartRate.kt` | CindyCore | not started |
| P19 | `StravaHttp.kt` | CindyCore (`URLSession` behind a transport protocol) | not started |
| P19 | `StravaPayload.kt` | CindyCore | not started |
| P19 | `StravaTokens.kt` | CindyCore (logic) + Keychain store in CindyTracker | not started |
| P19 | `StravaUploads.kt` | CindyCore (state machine) + CindyTracker (scheduling) | not started |
| P20 | `StravaAuthActivity.kt` | CindyTracker (iOS rewrite) | not started |
| P20 | `StravaConsent.kt` | CindyTracker (iOS rewrite) | not started |
| P20 | `StravaUploadWorker.kt` | CindyTracker (iOS rewrite) | not started |
