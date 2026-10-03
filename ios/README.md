# Cindy Tracker — iOS

A port of the Android app, sharing its counting logic in spirit and its behaviour exactly.

## What is verified and what is not

| | Status |
|---|---|
| `CindyCore` — counting, Cindy progression, setup check, bar gate, heels-flat and smart squats, records, levels | **226 tests, passing** (`tools/ios/swift.sh test`), on Linux and in CI. **The engine reproduces the Kotlin's parity trace on all 1,639 frames, every column.** Records, progress, voice, heart rate and Strava are not ported yet: see [PARITY.md](PARITY.md) |
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
```

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
│   │   ├── Records.swift         attempts, splits, persistence
│   │   └── Levels.swift          the rank ladder
│   ├── Sources/CindyFixtures/    synthetic bodies and a rig that drives an engine with them
│   └── Tests/CindyCoreTests/     XCTest: every check, one class per area
└── CindyTracker/         the app — builds, never run on a device
    ├── PoseSource.swift          where the skeleton can come from
    ├── VisionPoseSource.swift    capture, Vision, filming: the real source
    ├── ReplayPoseSource.swift    a scripted body for the simulator (debug builds only)
    ├── VisionPose.swift          Vision → the shared 17-point layout
    ├── CameraModel.swift         what the screens watch, fed by a PoseSource
    ├── WorkoutViewModel.swift    clock, setup, score, voice
    ├── ContentView.swift         camera, skeleton, HUD
    └── ResultsView.swift         score, level, splits
└── CindyTrackerUITests/  drives the app in the simulator against the scripted body
```

## No model file

The one real difference from Android. iOS has `VNDetectHumanBodyPoseRequest` built into Vision,
and its joints map one-for-one onto COCO-17 — so there is no `.tflite` to ship, nothing to
download, and no 22 MB of model in the bundle. `VisionPose.swift` is the whole adapter.

Everything downstream of that file is the same logic as Android, arrived at the same way.

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
`Records.ranked` are already there and tested, so the screen is the only missing piece.

Filming currently writes the raw camera stream to the app's temporary directory. Two gaps against
Android:

- **Overlays are not burned in.** Android uses CameraX's `OverlayEffect` to draw the skeleton,
  score and watermark into the recorded buffer. `AVCaptureMovieFileOutput` has no equivalent, so
  iOS needs `AVAssetWriter` with the frames composited by hand — the pixel buffer is already in
  reach in `CameraModel.captureOutput`, which is where that work belongs.
- **It does not reach the photo library.** That needs `PHPhotoLibrary` and the usage description
  above.
