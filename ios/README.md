# Cindy Tracker — iOS

A port of the Android app, sharing its counting logic in spirit and its behaviour exactly.

## What is verified and what is not

| | Status |
|---|---|
| `CindyCore` — counting, Cindy progression, setup check, bar gate, records, levels | **83 checks passing** (`swift run CindyCoreChecks`) |
| `CindyTracker` — camera, Vision, SwiftUI screens | **Never compiled.** No Xcode on the build machine, so no iOS SDK |

Only Command Line Tools were available, which ship `swiftc` but no iOS SDK, no simulator and no
XCTest. So the logic is a real, running, tested port; the app layer around it is written but
unproven. Expect to fix compile errors in `CindyTracker/` on first build — treat those files as a
careful draft, not working code.

That split is also why the checks are an executable rather than an XCTest target: `swift run
CindyCoreChecks` exits non-zero on failure and needs nothing but the command line tools.

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
│   └── Sources/CindyCoreChecks/  the harness and every check
└── CindyTracker/         the app — unproven
    ├── VisionPose.swift          Vision → the shared 17-point layout
    ├── CameraModel.swift         capture, pose, filming
    ├── WorkoutViewModel.swift    clock, setup, score, voice
    ├── ContentView.swift         camera, skeleton, HUD
    └── ResultsView.swift         score, level, splits
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

Then set a signing team in Signing & Capabilities and run **on a device** — the simulator has no
camera, so there is nothing for the pose detector to look at.

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

Filming currently writes to the app's temporary directory. Moving it into the photo library needs
`PHPhotoLibrary` and the usage description above.
