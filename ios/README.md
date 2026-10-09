# Cindy Tracker — iOS

A port of the Android app, sharing its counting logic in spirit and its behaviour exactly.

## What is verified and what is not

| | Status |
|---|---|
| `CindyCore` — counting, Cindy progression, setup check, bar gate, heels-flat and smart squats, records (format v1 to v7), sets, rep times, levels, the voice's words in eleven languages, voice choice and coaching, streaks, progress, peaks, badges, session tiles, the lifted-weight and equivalents card, the reminder's rules and the first-run flags, heart rate (its zones, hardest round and saved trace), the calorie estimate and the results timeline, the speaker and the voice language list, the results page (which cards show and what each says) and the touch, geometry and screen-reader stops of its four charts, the Progress screen (which cards show, what each says) with its chart, calendar and week strip, the profile, the menu and the account (their rows, sheets and badges), the first-launch pages, the camera-screen tour and Help (their pages, steps and every word) | **1,664 tests, passing** (`tools/ios/swift.sh test`), on Linux and in CI. **The engine reproduces the Kotlin's parity trace on all 1,639 frames, every column.** The Bluetooth link and Strava are not ported yet, and nothing here is on a screen yet: see [PARITY.md](PARITY.md) |
| `CindyClips` — scores the recorded clips with Vision, in the shape the Python harness scores them with MoveNet | **65 tests, passing** on Linux and in CI: the scoring is run through the real `run_batch.py` on the same frames and the reports are identical (see [Vision on the clips](#vision-on-the-clips)). **Not yet run on a clip**: it needs a Mac with the clips provisioned, which is yours to do |
| `CindyTracker` — camera, Vision, SwiftUI screens | **Builds, and one UI test passes** on CI (macOS, Xcode 16.4, iOS 18.5 simulator), against a scripted body. **Never run on a device** |

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
    ├── LanguageSheet.swift       the voice's language list
    ├── ContentView.swift         camera, skeleton, HUD, and the first run (pages, camera, tour)
    ├── TutorialScreen.swift      the five first-launch pages
    ├── SpotlightOverlay.swift    the tour of the camera screen
    ├── HelpScreen.swift          Help, and the licence texts
    ├── PlacementDiagram.swift    where to stand, drawn
    ├── Palette.swift             Android's colours and Manrope, for the screens written from P14 on
    ├── Resources/                Manrope's five files and its licence text
    └── ResultsView.swift         score, level, splits
└── CindyTrackerUITests/  drives the app in the simulator against the scripted body
```

## No model file

The one real difference from Android. iOS has `VNDetectHumanBodyPoseRequest` built into Vision,
and its joints map one-for-one onto COCO-17 — so there is no `.tflite` to ship, nothing to
download, and no 22 MB of model in the bundle. `CindyVision` (`VisionFrameAnalyser` and
`VisionPose`) is the whole adapter.

Everything downstream of that file is the same logic as Android, arrived at the same way.

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
