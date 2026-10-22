# Cindy Tracker — iOS

A port of the Android app, sharing its counting logic in spirit and its behaviour exactly.

## What is verified and what is not

| | Status |
|---|---|
| `CindyCore` — counting, Cindy progression, setup check, bar gate, heels-flat and smart squats, records (format v1 to v7), sets, rep times, levels, the voice's words in eleven languages, voice choice and coaching, streaks, progress, peaks, badges, session tiles, the lifted-weight and equivalents card, the reminder's rules and the first-run flags, heart rate (its zones, hardest round and saved trace), the calorie estimate and the results timeline, the speaker and the voice language list, the results page (which cards show and what each says) and the touch, geometry and screen-reader stops of its four charts, the Progress screen (which cards show, what each says) with its chart, calendar and week strip, discarding one session at a time with everything filed beside it (there is no button that deletes them all), the watch-at-START rules, and the phone-moved check (the camera's direction from Core Motion's matrix, and what a knock does to the count), the profile, the menu and the account (their rows, sheets and badges), the first-launch pages, the camera screen (what each control is and says in each state, and the start figure's motion), the camera-screen tour and Help (their pages, steps and every word), and the heart-rate pairing (which adverts count, the list's order, what Bluetooth permits, what the sheets say), filming (what a tap on REC does and says, and where the burned-in words go), the music (how loud, when it plays, what its sheet says) and the reminder (the week of notifications to schedule, and what the sheet does about permission), and Strava's logic (the activity's JSON, name and description, the requests and how every answer is read, OAuth, the stored grant and its refresh, the upload ledger, and a `URLSession` transport that only speaks https and follows no redirect) | **2,105 tests, passing** (`tools/ios/swift.sh test`), on Linux and in CI. **The engine reproduces the Kotlin's parity trace on all 1,639 frames, every column.** Strava is connected and uploaded from the phone (the screens and the scheduling are built by the macOS job and have not met a phone): see [PARITY.md](PARITY.md) |
| `CindyClips` — scores the recorded clips with Vision, in the shape the Python harness scores them with MoveNet | **65 tests, passing** on Linux and in CI: the scoring is run through the real `run_batch.py` on the same frames and the reports are identical (see [Vision on the clips](#vision-on-the-clips)). **Not yet run on a clip**: it needs a Mac with the clips provisioned, which is yours to do |
| `CindyTracker` — camera, Vision, SwiftUI screens | **Builds, and its UI tests pass** on CI (macOS, Xcode 16.4, iOS 18.5 simulator), against a scripted body. **Never run on a device** |

The logic is a real, running, tested port. The app layer compiled on its first macOS build with
one error, and counts a replayed workout in the simulator, but nothing has pointed a real camera at
a real person yet, so what Vision makes of one is unknown.

`CindyCore` imports only Foundation, so it builds and tests on Linux with no Xcode. That is why the
checks are XCTest and run anywhere:

```sh
tools/ios/swift.sh test                          # Linux: fetches a pinned toolchain once (~880 MB)
tools/ios/swift.sh test --filter BarGateTests    # a single class
swift test --package-path ios/CindyCore          # on a Mac, with Xcode's swift
tools/ios/parse-app.sh                           # Linux: every app file parses (syntax only)
```

The app itself (`ios/CindyTracker`, SwiftUI and UIKit) needs Apple's SDK to compile, so on Linux
the most that can be checked is that it parses. Whatever is decided about what a screen shows is in
`CindyCore` for that reason, and tested there; the views only draw it. Compiling the app is the
macOS job in `.github/workflows/ios-app.yml`, or Xcode on a Mac.

[PLAN.md](PLAN.md) sets out how the app catches up with Android, and [PARITY.md](PARITY.md) tracks
which Kotlin file each Swift file mirrors.

## Layout

```
ios/
├── CindyCore/            Swift package — the logic, tested
│   ├── Sources/CindyCore/
│   │   ├── RepCounter.swift      trough tracking + self-calibrating band
│   │   ├── WorkoutEngine.swift   signals, Cindy progression, setup check
│   │   ├── BarZone.swift         where the bar is, learned from dead hangs
│   │   ├── Records.swift         attempts and the saved line format (v1 to v7)
│   │   ├── SplitBook.swift       each set's time, undone with the workout
│   │   ├── RepLog.swift          where each rep landed on the clock
│   │   ├── RepTimes.swift        the rep-times file format and its store
│   │   ├── StravaSets.swift      a session's sets, rebuilt from its record
│   │   ├── StravaPayload.swift   the activity's JSON; StravaActivityText, StravaComposer, StravaHeartRate
│   │   ├── StravaApi.swift       the upload and its poll, and how each answer is read (JsonObject)
│   │   ├── StravaAuth.swift      the consent URL, the redirect, the three token calls
│   │   ├── StravaTokens.swift    the stored grant and the session that keeps it fresh
│   │   ├── StravaUploads.swift   what happened to each attempt's upload
│   │   ├── StravaUploadWorker.swift  one upload's decisions, and the queue that drains the ledger
│   │   ├── StravaConnect.swift   the consent words, starting OAuth, reading the return, the sheets' words
│   │   ├── StravaRow.swift       the results screen's Strava row
│   │   ├── StravaHttp.swift      requests, bodies and the transport; URLSessionTransport is the real one
│   │   ├── RoundSplits.swift     what the round chart draws and says
│   │   ├── SessionStats.swift    a session as rounds and movements
│   │   ├── Comparisons.swift     best and last earlier attempt
│   │   ├── VoiceLine.swift       what the voice says, as facts
│   │   ├── Phrasebook*.swift     the same facts as words, in eleven languages
│   │   ├── VoiceDirector.swift   which voice speaks, and keeping words and voice in agreement
│   │   ├── Speaker.swift         the voice's switches, volume, and its main and background threads
│   │   ├── LanguageGroupModel.swift  the language list: rows, taps, downloads, previews
│   │   ├── AppleVoiceMapping.swift   what a system voice is called to the director
│   │   ├── OverlayTransform.swift  the frame onto the screen and the recording
│   │   ├── RoiTracker.swift      where to look next, and Vision's side of it
│   │   ├── FrameHandoff.swift    analysis thread to main thread without losing a rep
│   │   ├── FrameLatency.swift    how old a frame is, and the debug readout's maths
│   │   ├── WorkoutSession.swift  a whole Cindy as decisions: clock, setup, voice, saving
│   │   ├── Countdown.swift       the countdown to REC, timed without a view
│   │   ├── FilmFlow.swift        what a tap on REC does, says and saves
│   │   ├── MusicFlow.swift       how loud the music plays, when, and what its sheet says
│   │   ├── ReminderPlan.swift    the next week of reminders, scheduled beforehand
│   │   ├── RecordingLayout.swift where the film puts its words, inside the safe area
│   │   ├── Coach.swift           when to speak about position and the clock
│   │   ├── Streak.swift          days and weeks trained, runs and milestones
│   │   ├── LocalCalendar.swift   dates, months and zones with no locale data in them
│   │   ├── Progress.swift        the chart's series and readouts, the week card
│   │   ├── Peaks.swift           the personal-best board
│   │   ├── Cheer.swift           the encouraging lines
│   │   ├── Badges.swift          the 26 badges, replayed from the sessions
│   │   ├── Lifted.swift          body weight moved, and Equivalents.swift what that is the size of
│   │   ├── SessionTiles.swift    the six figures under the score
│   │   ├── Avatar.swift          names, initials, photo arithmetic
│   │   ├── Reminder.swift        when the reminder fires and what it says
│   │   ├── Onboarding.swift      who is shown around, and the flags (FirstRun)
│   │   ├── TutorialPages.swift   the five first-launch pages, their buttons, swipe and ending
│   │   ├── SpotlightTour.swift   the camera-screen tour: which controls, which step, where the card sits
│   │   ├── HelpPage.swift        every section of Help, as data; HelpFeatures says which parts exist
│   │   ├── Licences.swift        the credits and the licence texts that ship; AppLinks.swift the addresses
│   │   ├── HeartRateAdvert.swift which adverts count, the list's order, the reconnect backoff
│   │   ├── HeartRateAccess.swift what Bluetooth permits, and the step FIND MY WATCH takes
│   │   ├── HeartRateSheets.swift what the heart-rate sheets say
│   │   └── Levels.swift          the rank ladder
│   ├── Sources/CindyVision/      Vision → the 17 keypoints; the camera and the clip tool share it
│   ├── Sources/CindyFixtures/    synthetic bodies and a rig that drives an engine with them
│   └── Tests/CindyCoreTests/     XCTest: every check, one class per area
├── CindyClips/           Swift package — scores recorded clips with Vision (`cindy-clips`)
│   ├── Sources/ClipScoring/      scenarios, the engine's calls, the report; no Apple frameworks
│   ├── Sources/cindy-clips/      decodes a clip and runs Vision (macOS); elsewhere skips everything
│   └── Tests/ClipScoringTests/   XCTest, on Linux
└── CindyTracker/         the app — builds, never run on a device
    ├── PoseSource.swift          where the skeleton can come from
    ├── VisionPoseSource.swift    capture, Vision, filming: the real source
    ├── ReplayPoseSource.swift    a scripted body for the simulator (debug builds only)
    ├── CameraModel.swift         what the screens watch, fed by a PoseSource
    ├── WorkoutViewModel.swift    clock, setup, score, voice
    ├── VoiceSheet.swift          the voice sheet, and its language list
    ├── ContentView.swift         camera, skeleton, and the first run (pages, camera, tour)
    ├── CameraHud.swift           the two bands of the camera screen, and HudButtons.swift its marks
    ├── StartPoseView.swift       the start-position figure and the coach card
    ├── LaunchView.swift          the arcs the app opens on
    ├── TutorialScreen.swift      the five first-launch pages
    ├── SpotlightOverlay.swift    the tour of the camera screen
    ├── HelpScreen.swift          Help, and the licence texts
    ├── CoreBluetoothHeartRateSource.swift  the paired watch, over Core Bluetooth
    ├── HeartRateScanner.swift    the search behind FIND MY WATCH
    ├── HeartRateSheet.swift      the Heart rate sheet and the search sheet
    ├── PlacementDiagram.swift    where to stand, drawn, and the three facts under it
    ├── PlacementGuideView.swift  the sheet that asks where to stand before the first setup check
    ├── Palette.swift             Android's colours and Manrope, which every screen draws from
    ├── ProgressScreen.swift      the record board: its title, its order, its sheets
    ├── ProgressCards.swift       its cards: the habit, this week, the chart card, peaks, the calendar, the leaderboard
    ├── ProgressCharts.swift      the week strip, the month grid and the chart
    ├── ProgressViewModel.swift   its state for SwiftUI
    ├── Resources/                Manrope's five files and its licence text
    ├── ResultsView.swift         the session page: its order, its questions
    ├── ResultsCards.swift        the page's cards: score, level, tiles, movements, lifted, compared with
    ├── ResultsHeart.swift        the heart-rate block
    └── ResultsCharts.swift       the four charts
└── CindyTrackerUITests/  drives the app in the simulator against the scripted body
```

## No model file

The one real difference from Android. iOS has `VNDetectHumanBodyPoseRequest` built into Vision,
and its joints map one-for-one onto COCO-17 — so there is no `.tflite` to ship, nothing to
download, and no 22 MB of model in the bundle. `CindyVision` (`VisionFrameAnalyser` and
`VisionPose`) is the whole adapter.

Everything downstream of that file is the same logic as Android, arrived at the same way.

## Strava

Off unless the build is given credentials, exactly as Android is without `strava.properties`: put
`STRAVA_CLIENT_ID` and `STRAVA_CLIENT_SECRET` in `ios/Config/Strava.xcconfig` (gitignored, picked up
by `Config/Base.xcconfig` through an optional include) and regenerate the project. A build without
that file has no Strava row, no Help section, no tutorial bullet, and uploads nothing.

Strava's authorization callback domain stays `localhost`; the redirect scheme is the bundle
identifier. The athlete is asked first (a sheet that says what each workout sends), connects in the
Strava app if it is installed and in a web sheet if not, and the tokens go in the Keychain, this device
only. There is no scheduler that runs an upload while the app is closed: it is sent as the session is
saved, and again when the app comes forward, when a network appears, and when iOS grants a background
refresh, so **an upload can wait until the app is next opened**. Help says so.

## Vision on the clips

The engine's thresholds were tuned on MoveNet's keypoints, and the app uses Vision's, so whether
Vision counts as well on the angles this app exists for is a question for the clips, not for
reasoning (decision D1 in [PLAN.md](PLAN.md)). `cindy-clips` scores the catalogues in
`tests/scenarios/` with Vision, in the shape `tools/video_regression/run_batch.py` scores them with
MoveNet, and `compare_reports.py` lays the two beside each other:

```sh
python3 tools/video_regression/fetch_youtube.py                    # the clips; they are not in git
python3 tools/video_regression/run_batch.py                        # MoveNet  -> tests/reports/python-regression.json
swift run --package-path ios/CindyClips cindy-clips                # Vision   -> tests/reports/ios/vision-regression.json
python3 tools/video_regression/compare_reports.py --markdown table.md
```

A scenario whose clip is missing is **skipped, with the reason**, and counts as neither a pass nor a
fail; `--require-fixtures` makes a run with any skip exit 3. On a machine that is not a Mac every
scenario is skipped. The clip tool runs Vision through the same `VisionFrameAnalyser` the camera
does, on every frame at the file's own rate, upright, as `run_batch.py` does.

## Building it

The project is generated, not committed — `project.yml` is the source of truth, and it already
wires up the local `CindyCore` package, the camera usage string and the portrait/dark settings.

```sh
brew install xcodegen          # once
cd ios && xcodegen generate    # writes CindyTracker.xcodeproj
open CindyTracker.xcodeproj
```

Then set a signing team in Signing & Capabilities and run **on a device** to use the camera.

### In the simulator

The simulator has no camera, so a debug build launched with `-CindyReplay pullups` takes its
skeleton from a scripted body instead (`ReplayPoseSource`): hanging, then pull-ups for ever. In
Xcode, add it under Product → Scheme → Edit Scheme → Run → Arguments. A release build has no such
branch. The UI test launches the app this way and counts a workout through to the results screen:

```sh
cd ios && xcodegen generate
xcodebuild test -project CindyTracker.xcodeproj -scheme CindyTracker \
  -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO
```

CI runs the same, in `.github/workflows/ios-app.yml`, but only for changes under `ios/`: macOS
minutes count ten times against the month's included minutes.

Re-run `xcodegen generate` after adding or moving files.

## Getting it onto a phone

There is no equivalent of the Android APK link. iOS will not install an app that is not signed for
the target device, so a build cannot simply be downloaded from a URL. The routes that exist:

| Route | Cost | Over the air? |
|---|---|---|
| Xcode → Run, wireless | free Apple ID | after one USB pairing; app expires every 7 days |
| TestFlight | $99/yr Developer Program | yes — an install link, the closest thing to the APK flow |
| Ad Hoc + Firebase App Distribution / Diawi | $99/yr | yes, but every device UDID must be registered first |

For one phone, Xcode wireless is enough. For sending builds to anyone else, it is TestFlight.

### TestFlight and the App Store

The project is ready to archive (version 1.0.0, build 1, the 1024 px icon, a privacy manifest per
build, `ITSAppUsesNonExemptEncryption` false), and the listing, the policy and the App Store Connect
answers are in [../appstore/](../appstore/README.md), which also has the steps: choose your team,
Product → Archive on **Any iOS Device**, Distribute App → App Store Connect. Each upload needs a new
`CURRENT_PROJECT_VERSION`. A build with Strava and one without are different uploads with different
App Privacy answers; the build is chosen by whether `Config/Strava.xcconfig` exists.

What is the owner's: the Developer Program membership, the bundle ID (`com.cindy.tracker` unless it is
taken), signing, the upload, the screenshots, publishing the policy page at
`https://alexxgalea.github.io/cindy-privacy/ios/`, and the testers.

## Still to port

The record board (history list and progress chart) and the music picker. `RecordStore` and
`Records.ranked` are already there and tested, so the screen is the only missing piece. The
workout does not yet file set times or rep times as it runs, so a session saved from the phone has
neither: the engine-to-record wiring comes with the app phases.

Filming currently writes the raw camera stream to the app's temporary directory. Two gaps against
Android:

- **Overlays are not burned in.** Android uses CameraX's `OverlayEffect` to draw the skeleton,
  score and watermark into the recorded buffer. `AVCaptureMovieFileOutput` has no equivalent, so
  iOS needs `AVAssetWriter` with the frames composited by hand — the pixel buffer is already in
  reach in `CameraModel.captureOutput`, which is where that work belongs.
- **It does not reach the photo library.** That needs `PHPhotoLibrary` and the usage description
  above.
