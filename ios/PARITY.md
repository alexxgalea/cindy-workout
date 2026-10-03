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
| `VariationsTest`, `adaptive sessions count toward the streak` | P8 | It needs `Streak` |

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
| P4 | `Coach.kt` | CindyCore | not started |
| P4 | `Phrasebook.kt` | CindyCore | not started |
| P4 | `PhrasebookDe.kt` | CindyCore | not started |
| P4 | `PhrasebookEn.kt` | CindyCore | not started |
| P4 | `PhrasebookEs.kt` | CindyCore | not started |
| P4 | `PhrasebookFr.kt` | CindyCore | not started |
| P4 | `PhrasebookIt.kt` | CindyCore | not started |
| P4 | `PhrasebookNl.kt` | CindyCore | not started |
| P4 | `PhrasebookPl.kt` | CindyCore | not started |
| P4 | `PhrasebookPt.kt` | CindyCore | not started |
| P4 | `PhrasebookRo.kt` | CindyCore | not started |
| P4 | `PhrasebookRu.kt` | CindyCore | not started |
| P4 | `PhrasebookTr.kt` | CindyCore | not started |
| P4 | `Plurals.kt` | CindyCore | not started |
| P4 | `RecordedHud.kt` | CindyCore | not started |
| P4 | `TtsEngine.kt` | CindyCore (protocol) | not started |
| P4 | `VoiceChoice.kt` | CindyCore | not started |
| P4 | `VoiceDirector.kt` | CindyCore | not started |
| P4 | `VoiceHints.kt` | CindyCore | not started |
| P4 | `VoiceLanguageText.kt` | CindyCore | not started |
| P4 | `VoiceLine.kt` | CindyCore | not started |
| P4 | `VoicePacks.kt` | CindyCore | not started |
| P5 | `FrameHandoff.kt` | CindyCore | not started |
| P5 | `FrameLatency.kt` | split: `Rolling`/`RateMeter`/probe maths → CindyCore, camera timestamps → CindyTracker | not started |
| P5 | `OverlayTransform.kt` | CindyCore (pure maths, ported with its tests) | not started |
| P5 | `OverlayView.kt` | CindyTracker (iOS rewrite) | not started |
| P5 | `PoseDetector.kt` | CindyTracker (iOS rewrite) | not started |
| P5 | `YuvCrop.kt` | not ported — Android YUV path; Vision's `regionOfInterest` replaces it | not ported |
| P6 | `CindySheet.kt` | CindyTracker (iOS rewrite) | not started |
| P6 | `CindyViews.kt` | CindyTracker (iOS rewrite) | not started |
| P6 | `CountdownView.kt` | CindyTracker (iOS rewrite) | not started |
| P6 | `Dialogs.kt` | CindyTracker (iOS rewrite) | not started |
| P6 | `LaunchView.kt` | CindyTracker (iOS rewrite) | not started |
| P6 | `MainActivity.kt` | CindyTracker (iOS rewrite) | not started |
| P6 | `PlacementFacts.kt` | CindyTracker (iOS rewrite) | not started |
| P6 | `PlacementGuideView.kt` | CindyTracker (iOS rewrite) | not started |
| P6 | `StartPoseView.kt` | CindyTracker (iOS rewrite) | not started |
| P8 | `Avatar.kt` | CindyCore | not started |
| P8 | `Badges.kt` | CindyCore | not started |
| P8 | `CalendarGrid.kt` | CindyCore | not started |
| P8 | `Cheer.kt` | CindyCore | not started |
| P8 | `Equivalents.kt` | CindyCore | not started |
| P8 | `FirstRun.kt` | CindyCore (the flags) over `UserDefaults` | not started |
| P8 | `HudTour.kt` | CindyCore | not started |
| P8 | `Lifted.kt` | CindyCore | not started |
| P8 | `Onboarding.kt` | CindyCore | not started |
| P8 | `Peaks.kt` | CindyCore | not started |
| P8 | `Progress.kt` | CindyCore | not started |
| P8 | `Reminder.kt` | CindyCore | not started |
| P8 | `SpotlightMath.kt` | CindyCore | not started |
| P8 | `StatTiles.kt` | split: `SessionTiles` → CindyCore (P8), the tile views → CindyTracker (P11) | not started |
| P8 | `Streak.kt` | CindyCore | not started |
| P9 | `Calories.kt` | CindyCore | not started |
| P9 | `HeartRate.kt` | CindyCore (types, measurement parsing) | not started |
| P9 | `HeartRateRecorder.kt` | CindyCore | not started |
| P9 | `HeartRateStats.kt` | CindyCore | not started |
| P9 | `HeartRateStore.kt` | CindyCore (trace format) + CindyTracker (file I/O) | not started |
| P9 | `SessionTimeline.kt` | CindyCore | not started |
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
