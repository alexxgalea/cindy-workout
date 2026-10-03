# Bringing iOS level with Android

The plan for making the iOS app do what the Android app does, phase by phase. It is written to be
handed to an agent that executes it one phase at a time, and to the person reviewing each phase's
pull request.

Everything under **Where things stand** was measured on 2026-10-03 against `main` at `0922a8c`
(Release 1.0.0), not recalled. Re-measure if `main` has moved a long way.

---

## The goal, and when it is reached

The Android app is the specification. The iOS app is done when an athlete cannot tell from
behaviour which phone they used: the same reps count, the same screens say the same things, the
same records, badges and uploads come out of the same sessions.

That splits cleanly into two kinds of work, and the plan treats them differently.

- **Logic** (counting, records, progress, badges, voice wording, heart-rate maths, Strava payloads)
  has no platform in it. In Kotlin it is 65 files with no Android import, covered by **1,203 plain
  JVM tests**. On iOS it lives in the `CindyCore` Swift package, which builds and tests **on
  Linux** (verified below), so every one of those tests can be ported and run where the agent
  works. Behaviour is proven, not argued.
- **Platform** (camera, Vision, SwiftUI screens, speech, Bluetooth, filming, notifications,
  Strava's OAuth, background uploads) is a rewrite against Apple's frameworks. It can only be
  compiled and UI-tested on macOS, so CI does that, and what needs a real iPhone is listed under
  **Still owed** in each pull request for the owner to check.

Done means:

1. Every pure Kotlin test has a Swift test with the same intent, and they pass (`swift test`).
2. The Swift engine reproduces `tests/parity/trace_jvm.csv` on **all 1,639 frames, all 19
   columns, byte for byte**.
3. Every Android screen and control has an iOS counterpart, or a written reason it cannot have one
   on iOS (the **iOS deviations** of each phase).
4. The app builds on CI, its UI tests pass on the simulator, and the owner has run a full Cindy on
   an iPhone.

---

## Where things stand

| | |
|---|---|
| Kotlin app | 122 source files, ~25,000 lines; 1,566 JVM tests (1,203 pure, 363 Robolectric screen tests) |
| `ios/CindyCore` | 9 files ported: engine, counter, bar zone, tracking health, geometry, variations, records (format v4), levels |
| `ios/CindyTracker` | 6 files: camera, Vision adapter, view model, two screens. **Never compiled** |
| Last sync | The Swift engine was last brought level on 2026-09-28 (`b996b6d`). About 18,000 lines of Kotlin have landed since: heels-flat squats, smart squats, sessions, heart rate, Strava, badges, tutorial, help, Play release work |

### Measured while writing this plan

- **CindyCore builds and passes on Linux.** With the Swift 6.1.2 toolchain for Ubuntu 24.04,
  `swift run CindyCoreChecks` prints `143 checks, 0 failed` (the iOS README still says 83; it is
  stale). An XCTest target also builds and runs there (`swift test`), so real XCTest works without
  Xcode.
- **The engine is already close.** A throwaway replay of `tests/parity/plan.csv` through today's
  Swift engine matched `trace_jvm.csv` on **1,331 of 1,639 frames**. Every pull-up and push-up
  trace matched on every frame.
- **Two numeric bugs explain the rest outside heels-flat squats.** With both fixed, **1,355 of
  1,639** match, and **all 15 traces that do not use heels-flat or smart squats match on every
  frame and column**. The remaining 284 frames are all in the 5 heels-flat and smart-squat traces,
  which is the feature Swift does not have yet.
  1. `PoseGeometry.swift` converts to degrees in Float: `acosf(cosine) * 180 / .pi`. Kotlin does
     `Math.toDegrees(acos(cos).toDouble()).toFloat()`: `acos` in Float, the conversion in Double,
     by Java's constant. The fix is
     `return Float(Double(acosf(cosine)) * 57.29577951308232)`. This is a real engine bug, one
     ulp at a time, and it moved pull-up signals in the third decimal.
  2. The Swift test fixtures do their trigonometry in Float (`sinf(rad(...))`); Kotlin's
     `PoseFixtures.kt` does it in Double and converts at the end:
     `(LIMB * sin(Math.toRadians(deg.toDouble()))).toFloat()`. That is what the trace's `kpSum`
     column is there to catch. Fixing (2) without (1) makes the squats match and breaks four
     pull-up frames, because the two errors were cancelling each other.

  With fix (1) applied, the original 143 checks still pass. None of this was committed; P2 does it
  properly.

---

## Ground rules for every phase

### Where the plans live

Android's plans are kept in `/docs/`, which `.gitignore` keeps out of git. iOS is an agreed
exception for two files, because the sessions that execute this plan start from a fresh clone and
would otherwise lose them:

- **This plan**, `ios/PLAN.md`, committed. It changes only when the owner agrees a change; a
  phase that finds the plan wrong says so in its PR and asks, rather than editing it.
- **The parity table**, `ios/PARITY.md`, committed, and updated in the pull request of every
  phase that moves a row.

**Each phase's own working plan stays local**, in `docs/ios-pN-<slug>.md`, as on Android. Never
commit it or `git add -f` it; the PR body says what it needs to on its own.

### Identity, commits and pull requests

Set once per clone, before the first commit:

```sh
git config user.name  alexxgalea
git config user.email alexandru.galea2000@gmail.com
git config core.hooksPath .githooks
```

- **No attribution of any kind.** No `Co-Authored-By`, no `Claude-Session`, no `Signed-off-by`,
  no "Generated with" line, in commits or in pull request titles and bodies. `.githooks/commit-msg`
  strips `Co-Authored-By` but **not** `Claude-Session`, so do not rely on it: write messages
  without trailers, and check before every push:
  ```sh
  git log --format='%an <%ae>%n%B' origin/main..HEAD | grep -iE 'co-authored|claude-session|generated with|anthropic' && echo "FIX THE MESSAGES"
  git log --format='%an <%ae>' origin/main..HEAD | sort -u   # must be exactly: alexxgalea <alexandru.galea2000@gmail.com>
  ```
  **The GitHub tool adds its own footer** ("Generated by Claude Code", with the session link) to a
  pull request body when it creates one, even if the body you sent has none. After creating a PR,
  read the body back and, if the footer is there, update the body without it, then read it back
  again. Do this for every PR; #66 needed it.
- **Small commits.** One behaviour per commit, and the package builds and `swift test` passes at
  every commit. A phase is typically 4 to 10 commits. Never a "fix CI" or "address review"
  commit with a vague subject; say what changed.
- **Commit messages in the house style** (see `git log` on `main`): a plain-English subject in
  the imperative that says what the app now does, no `feat:`-style prefix, about 70 characters at
  most (*"Count squats with the heels flat on iOS"*, *"Replay the parity plan and compare it with
  the JVM trace"*). A body wrapped at about 72 columns that says why, what was checked, and
  anything surprising.
- **One pull request per phase**, from a branch named `ios-pN-<slug>` (the slugs are below) off
  `main`, titled the same way as a commit subject. When a phase has to build on one that is not
  merged yet, branch from it and open the body with a **Merge #N first** section, as #63 did.
- **Branches are always named for what they do**, `ios-pN-<slug>`, never `ccr-…`. The owner has
  said so, which is the permission the session's default branch name otherwise asks for. A PR's
  head branch cannot be renamed, so create the descriptive branch before opening the PR; if a PR
  was opened first, push the same commits under the right name, open a new PR, and close the old
  one with a note saying it is superseded (#58 → #59, #67 → #68).
- **Open the PR as a draft early when CI is the only way to see a result**, as the macOS build is,
  and stop pushing while a run is in progress: a newer push cancels it.
- **The PR body follows the house template** (Appendix C): What changes, Tested, Verified by
  hand, Needs you, Not in this PR, Still owed. Numbers, not adjectives: test counts from the
  output, frames matched, mutation checks run.

### The loop: plan, execute, test, review

Every phase runs the same four steps, in order.

1. **Plan.** Read every Kotlin file and test the phase lists, in full, and the Swift files they
   touch. Write a short phase plan to `docs/ios-pN-<slug>.md` before any code: the files to
   create, the commits in order, the Kotlin test count to match, and the iOS deviations, each with
   its reason. If it touches a **decision** (below) that is not settled, stop and ask.
2. **Execute.** Commit by commit. Port tests alongside the code they cover, in the same commit or
   the next, never in a batch at the end.
3. **Test.**
   - `swift test` on Linux for anything in `CindyCore` (`tools/ios/swift.sh test`, from P0).
   - The parity replay from P2 onward, which must stay at 1,639 of 1,639.
   - **Count parity**: for each Kotlin test file the phase ports, Kotlin's `@Test` count and
     Swift's test count, in a table in the PR. Any difference is explained (a Kotlin test that
     only exists because of Android, say), never silent.
   - **A mutation check**: break the behaviour the phase adds in one obvious way (a threshold, a
     guard, a branch), show which tests fail, restore it. Say in the PR what was broken and how
     many failed. A suite that does not fail when the code is wrong proves nothing.
   - For `CindyTracker` changes: push and wait for the macOS CI job (P1 onward). Never claim the
     app compiles without a green run on the commit you are describing.
4. **Review.** Before opening the PR:
   - Re-read the whole diff against the Kotlin, side by side, function by function. The question
     is not "does this look right" but "does this do exactly what the Kotlin does on every input".
   - Run the `code-review` skill on the branch at `high` if the session has it, and fix every
     confirmed finding.
   - Check the attribution and author rules above.
   - Then open the PR, watch CI to green, and answer every review comment.

### How Kotlin turns into Swift

The mechanical rules, decided once so that each phase does not decide them again.

| Kotlin | Swift | Why it matters |
|---|---|---|
| `Float` | `Float`, never `Double` | Thresholds are exact comparisons; a 64-bit port diverges on the frame that lands on one. |
| `Double` | `Double` | Including intermediate Double maths inside a Float function: follow the Kotlin line by line (see the `acos` bug above). |
| `Math.toDegrees(x)` | `x * 57.29577951308232` (Double) | Not `* 180 / .pi`, which rounds differently. |
| `Long` / `Int` | `Int64` / `Int` | Timestamps are `Int64` milliseconds everywhere. |
| `x.roundToInt()` | `Int((x + 0.5).rounded(.down))` | Kotlin rounds half up (`Math.round`); Swift's `.rounded()` rounds half away from zero, so `-2.5` differs. Put one helper in CindyCore and use it everywhere. |
| `String.format(Locale.US, …)` | `String(format: …, locale: Locale(identifier: "en_US_POSIX"))` | Where Kotlin formats with the default locale, decide per call and say so. |
| `Float.toString()` in user text | Match the Kotlin output explicitly | `"\(Float(1))"` and Kotlin's `1.0f.toString()` agree, but exponents and long fractions do not. |
| `when` without `else` | `switch` without `default` | The phrasebooks rely on a missing line failing the build. Keep that. |
| `enum class` + `name` | `enum: String` with the Kotlin `name` as raw value | Raw values are what the records and the parity plan store (`STRICT_PULL_UP`). |
| `data class` | `struct: Equatable` | |
| `object` | `enum` with static members | |
| `java.time` | `Calendar(identifier: .gregorian)` with an injected `TimeZone` and `firstWeekday` | Never `Calendar.current` inside CindyCore; the Linux Foundation's locale data differs from Apple's, and tests must not depend on either. |
| `org.json` | `JSONSerialization` (`.sortedKeys` when writing) | Tests compare parsed values, not strings, unless Kotlin's test compares strings. |
| `java.net` / HTTP | `URLSession` behind a protocol, with `#if canImport(FoundationNetworking)` | So it builds on Linux. |
| KDoc | `///` | Keep the comments. They are the reasons; translate them, do not drop them. |

Further rules:

- **CindyCore imports Foundation only.** No UIKit, AVFoundation, Vision or Combine, or Linux
  breaks, and with it the agent's ability to test.
- **File names follow Kotlin**: `Badges.kt` → `Badges.swift`, `BadgesTest.kt` →
  `BadgesTests.swift`. Test methods are the Kotlin backtick sentence in camel case
  (`` `a session counts` `` → `testASessionCounts`), with the original sentence as a `///` line
  above it so a grep for the Kotlin wording finds the Swift test.
- **Never stub forward.** If a file needs a type from a later phase, port the smallest real piece
  of that type now, with its tests. A placeholder that returns a constant is how ports go quietly
  wrong.
- **This plan does not change Android code.** The only Kotlin touched is a scratch copy of a test
  to prove a format (P3), which is never committed.
- **Never "improve" while porting.** If the Kotlin looks wrong, port it as is, note it in the PR
  under **Worth knowing**, and leave fixing it to an Android PR that fixes both.
- **The screens stay thin.** Anything a screen decides (which rows show, what a tile says, when
  a card hides) goes into a pure function in CindyCore with a test, mirroring the Robolectric test
  that pins it on Android. SwiftUI views only lay out what those functions return. This is what
  turns 363 Robolectric tests into tests that run on Linux.

### What can be tested where

| Where | What runs | Who |
|---|---|---|
| Linux (the agent's container) | `swift test` on CindyCore: all logic, parity, screen models | Agent, every commit |
| Linux CI (`ios.yml` → `core`) | The same, on every push | CI |
| macOS CI (`ios.yml` → `app`) | `xcodegen`, build for the simulator, XCUITest smoke flows against a replayed pose stream | CI, on changes under `ios/` |
| Owner's Mac with clips | The Vision clip harness (P7) | Owner |
| Owner's iPhone | Camera, real counting, speech, Bluetooth, filming, notifications, Strava | Owner, from each PR's **Still owed** |

---

## Decisions

Each has a recommendation, used unless the owner says otherwise. The phase that first depends on
it asks before going past it.

| | Decision | Recommendation | Needed by |
|---|---|---|---|
| **D1** | **Pose model.** Apple's Vision (`VNDetectHumanBodyPoseRequest`; no model shipped; what the current port uses) or MoveNet Thunder/Lightning converted to Core ML (the same network as Android and the Python harness, ~20 MB in the bundle, conversion through TensorFlow and `coremltools`). | **Vision, behind a `PoseSource` protocol, then measured in P7.** The engine's thresholds were tuned on MoveNet's keypoints, so Vision's may count differently on the floor-phone angles this app exists for. If P7 shows Vision undercounts the clean-valid clips where Android does not, add a MoveNet Core ML source as its own phase. | P5, revisited after P7 |
| **D2** | **Minimum iOS.** 16 (today's `project.yml`) or 17. | **17.** `@Observable`, Swift Charts' `chartXSelection` (the scrubbable charts on Results and Progress), `videoRotationAngle`. iOS 17 runs on every iPhone from the XS/XR (2018). | P1 |
| **D3** | **macOS CI minutes.** The repository is private, and GitHub bills macOS minutes at 10× Linux. | **Linux `core` job on every push; macOS `app` job only when `ios/**` or the workflow changes, plus manual dispatch, with in-progress runs cancelled.** | P0, P1 |
| **D4** | **Test framework.** Keep the `CindyCoreChecks` executable, XCTest, or Swift Testing. | **XCTest.** Proven on Linux here, familiar, and Xcode runs it unchanged. The executable existed only because the machine it was written on had no XCTest. | P0 |
| **D5** | **Bundle identifier.** `project.yml` says `com.cindy.tracker`. Apple's bundle IDs are global; someone else may already hold it. | Keep `com.cindy.tracker` if the owner's Apple Developer account can register it; otherwise `io.github.alexxgalea.cindy`. The Strava redirect scheme follows it, as on Android. | P20, P21 |
| **D6** | **Where a film goes.** Android writes to `Movies/Cindy`. On iOS, an album needs full photo-library access; saving without an album needs only add-only access. | **Add-only, no album.** A smaller permission for a feature the athlete has to tap. | P16 |
| **D7** | **Strava in the first iOS release.** | Build it (P19, P20), keep it behind a gitignored `Strava.xcconfig` exactly like `strava.properties`, so a build without credentials has no Strava at all. Ship it when the Strava app is raised past one athlete. | P20 |
| **D8** | **Distribution.** TestFlight only, or the App Store. Both need the $99/year Apple Developer Program. | **TestFlight first** (the closest thing to the APK link), the App Store listing in P21. | P21 |

---

## Phases

Ordered so that each screen comes after all the logic it shows, and so that a real workout runs on
an iPhone as early as possible (milestone A). Phases inside a track can run in parallel once their
dependencies are merged.

```
P0 tests on Linux ─┬─ P1 app builds on CI ──────────────┐
                   ├─ P2 engine parity ─┐                │
                   ├─ P3 records ───────┼─ P4 voice core ┼─ P5 camera & pose ─ P6 workout screen ══ A
                   │                    │                │                        └─ P7 Vision on the clips
                   ├─ P8 progress & badges maths ────────┤
                   └─ P9 heart-rate & timeline maths ────┤
                                                         ├─ P10 voice languages
                                                         ├─ P11 results ─ P12 progress ─ P13 menu & account ─ P14 first run & help ══ B
                                                         ├─ P15 heart rate (BLE) ─ P16 filming ─ P17 music ─ P18 reminders ══ C
                                                         └─ P19 Strava core ─ P20 Strava app ══ D ─ P21 App Store & TestFlight
```

- **A**: a full Cindy on an iPhone, counted, voiced and saved.
- **B**: every screen of the Android app.
- **C**: parity without Strava.
- **D**: full parity.

Kotlin test counts per phase come from Appendix B. "Pure" tests are ported one for one; "screen"
tests become screen-model tests in CindyCore plus UI tests, as described in that phase.

---

### P0 · `ios-p0-tests-on-linux` · Run CindyCore's tests on Linux and on CI

**Depends on:** nothing. **Decisions:** D3, D4.

The foundation every later phase stands on: the agent must be able to run Swift where it works.

- `tools/ios/swift.sh`: fetches the pinned Linux toolchain once into
  `${CINDY_SWIFT_HOME:-$HOME/.cache/cindy-swift}` and runs `swift` from it with the arguments
  given, defaulting to `--package-path ios/CindyCore`. The archive is
  `https://download.swift.org/swift-6.1.2-release/ubuntu2404/swift-6.1.2-RELEASE/swift-6.1.2-RELEASE-ubuntu24.04.tar.gz`
  (~880 MB download, 2.8 GB unpacked). It refuses to run on anything but Linux x86_64 and says
  what to do on a Mac instead (use Xcode's `swift`). No setup hook: it is too heavy to download
  on every session start.
- Convert the 143 checks in `Sources/CindyCoreChecks/main.swift` into an XCTest target,
  `Tests/CindyCoreTests/`, one test class per Kotlin test class they mirror. Keep every check's
  wording as the test's doc line. Delete the executable and `Harness.swift`.
- Move `PoseFixtures.swift` to a library target `CindyFixtures` (tests and, from P1, the app's
  replay source both use it).
- `.github/workflows/ios.yml`, job `core`: `ubuntu-latest`, `container: swift:6.1.2-noble` (check
  the tag exists on Docker Hub; fall back to `swift:6.1-noble`), `swift test --package-path
  ios/CindyCore`. Runs on every push and pull request. The Android workflow is left alone.
- `ios/PARITY.md`: Appendix A as a living table, with a status column (`not started`, `ported`,
  `tests ported`), updated by every later phase.
- `ios/README.md`: tests instead of checks, Linux, the script, the real count.

**Commits, roughly:** run the checks as XCTest · move the fixtures into a library · fetch a pinned
toolchain · test CindyCore on CI · track what the port mirrors · README.

**Done when:** `tools/ios/swift.sh test` passes locally with 143 tests (not one lost in the move;
the PR lists any that merged or split), and `core` is green on the PR.

---

### P1 · `ios-p1-app-builds-on-ci` · Build the iOS app on CI, and let the simulator run a workout

**Depends on:** P0. **Decisions:** D2, D3.

The app layer has never been compiled. This phase makes it compile, and gives the simulator, which
has no camera, something to count.

- `ios.yml`, job `app`: `macos-15`; `brew install xcodegen` if missing; `cd ios && xcodegen
  generate`; `xcodebuild -project CindyTracker.xcodeproj -scheme CindyTracker -destination
  'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`. Path-filtered and cancellable
  per D3.
- Raise the deployment target to iOS 17 (D2) and fix every compile error in `CindyTracker/`. The
  agent cannot compile iOS locally, so this is a loop on CI: read the log, fix a whole file's
  errors at once, push. Group the fixes by file into meaningful commits ("Make the camera model
  compile against the iOS 17 SDK"), not one per CI run.
- A `PoseSource` protocol in the app, with `VisionPoseSource` (the current code) and
  `ReplayPoseSource`, which plays a scripted session built from `CindyFixtures` at 15 fps. The
  launch argument `-CindyReplay <script>` picks it; only DEBUG builds honour it.
- A `CindyTrackerUITests` target in `project.yml` with one smoke test: launch with replay, START,
  SKIP, two replayed reps count, STOP, the results screen appears. Run it in the `app` job on an
  iPhone simulator.

**Done when:** `app` is green with the build and the smoke test. The PR says how many compile
errors there were and in which files, because that is the measure of how far the draft was off.

**Still owed:** the first run on a real iPhone (Signing & Capabilities needs the owner's team), and
the camera permission prompt.

---

### P2 · `ios-p2-engine-parity` · Count exactly what Android counts

**Depends on:** P0.

**Port:** `RepCounter`, `WorkoutEngine`, `Variations`, `BarZone`, `TrackingHealth`,
`PoseGeometry` (resync), and new: `SmartSquatCounter`, `PosePrediction`, `StartPoses`,
`CameraStability`.

**Kotlin tests: 213 pure.** `WorkoutEngineTest`, `RepCounterTest`, `RepCounterMarginsTest`,
`BarGateTest`, `BarGuideTest`, `PullupOcclusionTest`, `AssistedPullupTest`,
`LimitedExtensionPullupTest`, `KneePushupTest`, `HeelsFlatSquatTest`, `SmartSquatTest`,
`SetupTest`, `SkippedRepsTest`, `StartPositionTest`, `PosePredictionTest`, `TrackingHealthTest`,
`CameraStabilityTest`, `VariationsTest`, `EngineParityTraceTest`.

In order:

1. **Fix the two numeric bugs** measured above, each in its own commit: the degrees conversion in
   `PoseGeometry.swift`, and the fixtures' trigonometry in Double (every builder, matching
   `PoseFixtures.kt` line for line, including `onTheFloor`, which Swift does not have yet).
2. **The parity test**, `EngineParityTests`: reads `tests/parity/plan.csv`, builds the same
   engine per trace (`fixedExercise`, `CindyProfile(pull:squat:)`, `smartSquats`), formats every
   value exactly as `EngineParityTraceTest.kt` does (`%.3f`, `nan`, quoted CSV, event names in
   capitals) and compares every row with `tests/parity/trace_jvm.csv`. On a mismatch it fails
   with the first divergent frame of each trace and the columns that differ, which localises a bug
   to one frame. It writes its own trace to the test's temporary directory, never into the
   repository. It locates the repository from `#filePath`. Expect 1,355 of 1,639 at this point,
   and say so in the commit.
3. **Re-read every engine file against Kotlin**, function by function. A diff of Kotlin history
   since `b996b6d` is a guide, not the method; three Kotlin commits touched the engine since then
   and others may predate the sync.
4. **Heels-flat squats**: `SquatVariant.HEELS_FLAT` and whatever else `Variations.kt` has gained,
   `RepCounter`'s `bottomMargin` and `minTravel`, the heels-flat counter's constants
   (`HEELS_FLAT_MIN_TRAVEL = 35`, `HEELS_FLAT_BOTTOM_MARGIN = 0.6`, `HEELS_FLAT_DOWN_BELOW = 120`),
   the profile's labels and record category.
5. **Smart squats**: `SmartSquatCounter` (matching by ascent, the credit of three, the cap at the
   squats' target, a `+1` dropping what is pending), `heelsFlatSpotted`, `effectiveProfile`,
   pending squats kept across a recalibration.
6. **`PosePrediction`, `StartPoses`, `CameraStability`**, with their tests.
7. Port the remaining tests file by file.

**Done when:** **1,639 of 1,639 frames** match, and the Swift test count for these files equals
213 (plus the checks P0 already carried over, which must not be counted twice: the PR's table
says which Kotlin test each one now stands for).

**Mutation check:** set `HEELS_FLAT_MIN_TRAVEL` to 33 and show which parity traces and which
tests fail; put the degrees conversion back to Float and show the parity failure names the frame.

**Worth knowing for later:** once this lands, any Android PR that changes a file in P2's list
changes `trace_jvm.csv`, and `core` will fail until the Swift side follows. That is the point.
`ios/PARITY.md` should say so.

---

### P3 · `ios-p3-records-and-sets` · Keep the same records, sets and rep times as Android

**Depends on:** P0 (P2 for `SkippedReps`, which is already in P2).

**Port:** `RecordStore.kt`'s `Attempt` and `Records` (format **v1 to v7**, from Swift's v4),
`RepLog`, `RepTimesStore` (format and store), `SplitBook`, `RoundSplits`, `SessionStats`,
`Comparisons`, `Levels` (resync), `LiveWorkout`.

**Kotlin tests: 134 pure + 5 store tests.** `RecordsTest`, `RoundSplitsTest`, `SessionStatsTest`,
`ComparisonsTest`, `LevelsTest`, `RepLogTest`, `RepTimesTest`, `SplitBookTest`; the
Robolectric `RecordStoreTest` and `RepTimesStoreTest` become XCTest against a throwaway
`UserDefaults(suiteName:)` and a temporary directory, both of which work on Linux.

- **The line format is Kotlin's, byte for byte**, so `RecordsTest`'s literal lines port
  verbatim. The iOS app never shipped, so no phone holds a Swift-only line: check whether Swift's
  current v3 and v4 encodings are Kotlin's, and if one is not, replace it rather than keeping a
  decoder for it.
- `RecordStore` over `UserDefaults` with the same key names as the Android `SharedPreferences`.
  Rep times as files in Application Support, one per attempt, named as Android names them.
- Records go in `CindyCore`; only the `UserDefaults` and file locations are injected.

**Done when:** counts match, and a v7 line written by Swift decodes in Kotlin's test (copy one
into the PR as proof: paste the Swift-encoded line into a scratch copy of `RecordsTest` and run
the JVM test, then discard the change).

---

### P4 · `ios-p4-voice-core` · Say the same things, in the same eleven languages

**Depends on:** P0. **Port:** `VoiceLine`, `Phrasebook` and all eleven phrasebooks, `Plurals`,
`VoicePacks`, `VoiceChoice`, `VoiceHints`, `VoiceLanguageText`, `VoiceDirector`, `Coach` (with
its clock), `TtsEngine` (as a protocol), `RecordedHud`.

**Kotlin tests: 231 pure.** `VoiceDirectorTest`, `CoachTest`, `CoachClockTest`,
`PhrasebooksTest`, `PhrasebookEnTest` and the ten language tests, `PluralsTest`,
`VoicePacksTest`, `VoiceChoiceTest`, `VoiceHintsTest`, `VoiceLanguageTextTest`,
`RecordedHudTest`, with `FakeTtsEngine` and `VoiceLineSamples` as test support.

- **The English golden.** `PhrasebookEnTest` pins English as byte-identical to what the app said
  before phrasebooks; port the expected strings verbatim.
- **Every phrasebook is an exhaustive `switch`**, so a missing line fails the build.
- **`VoiceHintsTest` reads the engine's source** and fails on a hint the catalogue does not know.
  The Swift test reads `Sources/CindyCore/WorkoutEngine.swift` by path from `#filePath`.
- Copy the translations exactly, including the no-digit-before-a-full-stop rule and the
  gendered numbers. Do not retranslate.

**Done when:** counts match; the mutation check deletes one line from one phrasebook and shows the
build fails.

---

### P5 · `ios-p5-camera-and-pose` · See the athlete the way the Android app does

**Depends on:** P1, P2. **Decision:** D1.

**Port:** `OverlayTransform` (pure, to CindyCore), `FrameHandoff` (to CindyCore), the `Rolling`
and `RateMeter` maths of `FrameLatency` (to CindyCore); `PoseDetector`'s crop tracking and
`OverlayView` as iOS code. `YuvCrop` is not ported (see Appendix A).

**Kotlin tests: 43 pure** (`OverlayTransformTest`, `UprightTransformTest`, `FrameHandoffTest`,
`LatencyTest`).

- `CameraModel`: `AVCaptureVideoDataOutput` with `alwaysDiscardsLateVideoFrames` (CameraX's
  `KEEP_ONLY_LATEST`), upright portrait frames (`videoRotationAngle`), mirrored for the selfie
  camera, at a resolution chosen to match the Android analysis frame's role.
- **Crop tracking as `PoseDetector` does it**: a square around where the body was last seen, fed
  through Vision's `regionOfInterest`, following it, and falling back to the whole frame after the
  same number of misses. The decision logic (when to crop, where, when to give up) is pure: put it
  in CindyCore as `RoiTracker` with tests derived from `PoseDetector.kt`'s behaviour, so P7 can
  reuse it.
- **The tracking flag is read after detection, for the same frame**, as `MainActivity.analyse`
  does (not as the Python harness does; see `tests/README.md`).
- `VisionPose`: Vision's normalised coordinates have their origin at the **bottom left**; convert
  to upright frame pixels with the origin at the top left. Map Vision's joints to COCO-17 as the
  current file does, and keep Vision's confidence as the score; P7 measures whether that is good
  enough.
- The skeleton drawn through `OverlayTransform` with the preview's `resizeAspectFill` (Android's
  `FILL_CENTER`), bones 0.45% and joints 0.55% of the frame's height.
- The debug readout on a long press of the status line: source (`Vision`), inference time, crop
  state, signal, learned range, phase.

**Still owed:** on an iPhone, the skeleton sits on the body with both cameras; inference time on
the debug readout; the crop follows someone stepping sideways.

---

### P6 · `ios-p6-workout-screen` · Run a whole Cindy on an iPhone

**Depends on:** P3, P4, P5. **Milestone A.**

**Port:** `MainActivity`'s behaviour, plus `CountdownView`, `PlacementGuideView`,
`PlacementFacts`, `StartPoseView`, `CindyViews`, `Dialogs`, `CindySheet`, `LaunchView`.

Everything in the README's **Interface**, **Setting up before the clock starts** and **Voice**
sections, in English (other languages are P10):

- The HUD: clock, round, movement, reps against target; the status line with its dot, red when
  the body is not tracked.
- `START`/pause/resume/`RESET`; `+1`, and a long press to skip to the next movement; `−1` across
  movement and round boundaries; `STOP` in place of `FLIP` during a workout; `FLIP`; `VOICE`;
  the menu entry (the menu itself is P13).
- **The setup check**: framing (naming the missing joints), calibration (two slow reps), the
  verdict, the twenty-second "barely registers" message, `SKIP`. Recalibration on pause and on
  flip, and `Recalibrating…`.
- The placement guide before the first setup check, with "Don't show this again"; the start pose.
- Haptics: short per rep, longer per movement, longest per round (`UIImpactFeedbackGenerator`).
- The screen stays awake (`isIdleTimerDisabled`) while the camera screen is up.
- Voice through `Coach`/`VoiceDirector` and an `AVSpeechSynthesizer` engine that conforms to
  `TtsEngine`: rep numbers interrupt (`stopSpeaking(at: .immediate)`, Android's `QUEUE_FLUSH`), the
  cues that must not be dropped queue after. Silent while VoiceOver runs, where Android is silent
  under TalkBack.
- At 00:00, freeze `N rounds + M reps`, save the attempt with its sets and rep times (P3), and
  open the results screen (the existing `ResultsView` until P11).
- **Move the orchestration that lives in `MainActivity` into a pure `WorkoutSession` in
  CindyCore** where it is decision rather than plumbing (clock ticks, when to recalibrate, what to
  save), tested on Linux. Say in the PR which parts of `MainActivity` went where.
- UI tests on the replay source: a whole scripted session, the setup check's three outcomes, `+1`,
  `−1` across a boundary, skip, pause and resume.

**Kotlin tests:** the 3 `CountdownTest`s, and the parts of `ScreenSmokeTest` that cover the camera
screen. List in the PR which of those behaviours each Swift test covers.

**Still owed:** a full twenty-minute Cindy on an iPhone, propped on the floor, with the voice on.
The count against a count by eye. This is the first real measure of D1.

---

### P7 · `ios-p7-vision-on-the-clips` · Measure Vision against MoveNet on the same clips

**Depends on:** P2, P5. **Decision:** D1.

The Python harness in `tools/video_regression/` scores clips with MoveNet; this scores the same
clips with Vision, so D1 is decided on numbers.

- `ios/CindyClips/`, a macOS-only Swift package (Vision and AVFoundation exist on macOS): decode
  each clip at the harness's analysed rate (every second frame of a 30 fps source), run Vision
  with P5's `RoiTracker`, feed `WorkoutEngine` exactly as `run_batch.py` does (a setup engine and a
  fixed-exercise scoring engine; `cindy` mode with `setup` and `skipTo`), and write reports in
  `run_batch.py`'s JSON schema to `tests/reports/ios/`.
- `tools/video_regression/compare_reports.py`: per clip, MoveNet's count, Vision's count, and the
  truth, grouped by the evaluation categories in `tests/README.md` (clean-valid,
  difficult-but-valid, must-not-count).
- The `app` CI job builds `CindyClips`, and runs it with no fixtures to check it reports every
  scenario as skipped with a reason, never as a pass.

**Needs you:** run it on a Mac with the clips provisioned (`fetch_youtube.py`), and the Python
harness on the same clips. The PR carries the table and a recommendation for D1. If Vision loses,
the next phase is a MoveNet Core ML `PoseSource`, planned then.

---

### P8 · `ios-p8-progress-and-badges` · Work out progress, streaks and badges the same way

**Depends on:** P3. **Port:** `Progress`, `Peaks`, `Streak`, `Cheer`, `CalendarGrid`, `Badges`,
`Avatar`, `Lifted`, `Equivalents`, `StatTiles` (its pure parts), `Onboarding`, `FirstRun` (the
flags' logic), `HudTour`, `SpotlightMath`, `Reminder`.

**Kotlin tests: 300 pure.** `BadgesTest` (75), `ProgressTest`, `PeaksTest`, `StreakTest`,
`CheerTest`, `CalendarGridTest`, `AvatarTest`, `LiftedTest`, `EquivalentsTest`, `StatTilesTest`,
`OnboardingTest`, `SpotlightMathTest`, `ReminderTest`.

- **Calendars are injected.** Streaks and weeks depend on the time zone and on the locale's first
  day of the week; every test passes both explicitly. Do not trust Linux Foundation's locale data
  for `firstWeekday`.
- **Equivalents' "an animal the emoji font cannot draw is never picked"**: the check of the font
  is a platform question. Put it behind a protocol, and test the choice with a fake.
- If `Calories` turns out to be needed here (by `Lifted` or `StatTiles`), port it here with
  `CaloriesTest` rather than waiting for P9.

---

### P9 · `ios-p9-heart-rate-and-timeline` · Work out heart rate, calories and the timeline the same way

**Depends on:** P3. **Port:** `Calories` (the MET model and Keytel), `HeartRate` (types,
measurement parsing, plausibility), `HeartRateRecorder`, `HeartRateStats`, `HeartRateStore` (the
trace format; file I/O as in P3), `SessionTimeline`.

**Kotlin tests: 123 pure + 3 store.** `SessionTimelineTest` (37), `HeartRateStatsTest`,
`SessionTimelineCaloriesTest`, `HeartRateRecorderTest`, `CaloriesTest`, `CaloriesHeartRateTest`,
`CaloriesTimelineTest`, `HeartRateMeasurementTest`, `HeartRateTracesTest`, and
`HeartRateStoreTest` as XCTest against a temporary directory.

- The coverage rule (a reading holds for at most five seconds), the Tanaka maximum, the five zones,
  "the hardest round", and the calorie line ending on the Calories row's figure by construction:
  all of it is pinned by the Kotlin tests, so port them first and make them pass.

---

### P10 · `ios-p10-voice-languages` · Choose the voice's language on iOS

**Depends on:** P4, P6. **Port:** `Speaker`, `AndroidTtsEngine` (as the AVSpeech engine),
`LanguageGroup` (the language list sheet).

**Kotlin tests: 58 screen** (`SpeakerTest`, `AndroidTtsEngineTest`, `LanguageGroupTest`):
`Speaker`'s and the engine's decisions become CindyCore tests against `FakeTtsEngine`; the sheet's
behaviour becomes a screen model plus UI tests.

**iOS deviations, to be stated in Help and the PR:**

- iOS cannot be asked to download a voice. Most languages ship a compact voice; enhanced voices
  are downloaded by the athlete in Settings → Accessibility → Spoken Content → Voices. **Manage
  voices** says that, instead of opening an engine's screen.
- So the "online preview" path mostly disappears: a language with any installed voice previews
  locally. Keep the online-preview wording only if a language turns out to have none.
- Availability comes from `AVSpeechSynthesisVoice.speechVoices()`.

**Still owed:** each of the eleven languages previewed on an iPhone; a workout counted in one
that is not English.

---

### P11 · `ios-p11-results` · Show the same results page

**Depends on:** P6, P8, P9. **Port:** `ResultsActivity`, `RoundTrackView`, `RoundSplitsView`,
`SessionTimelineView`, `ZoneBarView`.

**Kotlin tests: 39 screen** (`RoundSplitsViewTest`, `SessionTimelineViewTest`,
`RoundTrackViewTest`, `ZoneBarViewTest`) **plus** the results parts of `ScreenSmokeTest`.

Everything under **Records, levels and statistics** in the README, on the results page: score,
level, the six tiles, the round pills (ten to a row, split 5:10:15, tap and drag), one card per
movement in the session's own words, round splits stacked by movement with the compared round,
the session timeline (reps stepped, heart rate below, one cursor across both, the calories line,
"at least"), the lifted-and-burned card, the heart-rate card with the zone bar, badges just
earned, the streak celebration, COMPARED WITH and reopening a past session, Details. Charts in
Swift Charts with `chartXSelection` (D2); custom drawing in `Canvas`.

- **A results screen model in CindyCore** decides which cards show and what each says, from an
  attempt and its records. That is where the Robolectric tests' assertions go.
- VoiceOver reads a round as one stop, as TalkBack does.

**Still owed:** the page on an iPhone after a real session, at the smallest and largest text
sizes.

---

### P12 · `ios-p12-progress` · Show the same Progress screen

**Depends on:** P8, P11. **Port:** `RecordsActivity`, `ProgressChartView`, `CalendarView`,
`WeekStripView`. **Kotlin tests: 8 screen** plus the Progress parts of `ScreenSmokeTest`.

The opening line, streaks with the week strip, this week against last, the chart (Score, Pace,
Volume over 1M, 3M, 1Y, All; scrub; running best; record points; a hollow ring for a lower bound),
peaks, the calendar and its day sheet, the leaderboard against Tom Holland, the category chip,
OPEN on a chart point, CLEAR.

---

### P13 · `ios-p13-menu-and-account` · Give the menu, the movements and the account their screens

**Depends on:** P8, P10. **Port:** `MenuActivity`, `AccountActivity`, `AvatarStore`,
`AvatarView`, `Profile`. **Kotlin tests: 58 screen** (`AccountScreenTest`,
`HeelsFlatScreensTest`, `ProfileVoiceLanguageTest`, `ProfileHeartRateTest`) plus the menu parts of
`ScreenSmokeTest`.

- The menu card (name or "You", photo or initials), Movements (with Heels flat and Spot heels-flat
  squats, and the results screen's offer to make it the default), Voice (P10), Heart rate (the
  sheet arrives with P15), Daily reminder (P18), Strava (P20), Progress, Help.
- Account: the name (trimmed, one space, 30 characters), the photo from `PhotosPicker` (no
  permission needed), turned upright, cut square, reduced to 320 px, saved as `avatar.jpg` in
  Application Support; the 26 badges and their sheet.
- The body-weight, birth-year and sex sheet, with the third option averaging the other two.

**iOS deviation:** Android's backup is iCloud backup here. The app's files and `UserDefaults`
are in it by default; say so where Android's text says Google Drive.

---

### P14 · `ios-p14-first-run-and-help` · Show a new athlete around, and say what the app does

**Depends on:** P6, P8, P13. **Milestone B.** **Port:** `TutorialActivity`, `SpotlightView`,
`HelpActivity`, `Licences`, `AppLinks`.

**Kotlin tests: 59 screen** (`TutorialScreenTest`, `HelpScreenTest`, `LicencesTest`) and the
17 `HudTourTest` screen tests.

- The five pages, then the camera permission, then the spotlight tour over the camera screen;
  each once, by `Onboarding.shouldShowTutorial`'s rules. iOS's "permission already held" signal is
  `AVCaptureDevice.authorizationStatus(for: .video) == .authorized`.
- Help with every section, adjusted for iOS: Vision instead of MoveNet and LiteRT in LICENCES
  (unless D1 changes), Manrope's OFL shipped, the PRIVACY section saying iCloud backup and naming
  the iOS controls, the privacy policy row, the version at the foot, the CrossFit and medical
  disclaimers, Take the tour.
- Manrope copied from `app/src/main/res/font/` and registered in `UIAppFonts`; the palette from
  `res/values/colors.xml` as one Swift `Palette`; icons from SF Symbols where one matches, the
  rest converted from the vector drawables (their path data is SVG path syntax).

---

### P15 · `ios-p15-heart-rate-ble` · Pair a watch or strap over Bluetooth

**Depends on:** P9, P13. **Port:** `BleHeartRateSource`, `HeartRateScanner`,
`HeartRatePermissions`; the pure `HeartRateAdvert` matching and `reconnectDelayMs` to CindyCore.

**Kotlin tests: 12 pure + 3 screen.**

- CoreBluetooth: an unfiltered scan matched in software (service `0x180D`, or Garmin's
  manufacturer ID), plus `retrieveConnectedPeripherals(withServices:)` for a watch already
  connected through Garmin Connect, marked "Connected to this phone". Reconnect with the same
  backoff while the camera screen is open.
- **iOS deviations:** no location permission and no Location-off case (iOS ties a scan only to
  Bluetooth); `NSBluetoothAlwaysUsageDescription` instead. Android's "drop the cached service list
  and look again" has no CoreBluetooth equivalent; say what happens instead.

**Still owed:** a chest strap and a Garmin with Broadcast Heart Rate, on an iPhone.

---

### P16 · `ios-p16-filming` · Film the workout with the overlay burned in

**Depends on:** P5, P6. **Decision:** D6. **Port:** `VideoRecorder`, `RecordingOverlay`.

- `AVAssetWriter` fed from the same video data output, each frame composited with the skeleton,
  clock, round, movement, count and the **CINDY** watermark. `RecordedHud` (P4) decides every
  label, including SETUP, CALIBRATION, `PULL-UPS · NOT SCORED`, and the three-second CALIBRATED
  and CALIBRATION SKIPPED banners. Drawn in the analysis frame's upright space through
  `OverlayTransform`.
- Video only, no audio, so no microphone permission. The voice: "Recording in 3", "Recording",
  "Recording didn't start", queued.
- Saved with add-only photo access (D6). If writing fails, counting carries on, as Android's
  binding degrades.

**Still owed:** a film from each camera, watched end to end; the overlay lands on the body and the
text is the right way up.

---

### P17 · `ios-p17-music` · Play the athlete's own track under the workout

**Depends on:** P6. **Port:** `MusicPlayer`.

`UIDocumentPicker` for an audio file with a security-scoped bookmark (Android's persistable URI
permission), forgotten quietly when it no longer resolves; looping, paused with the workout,
ducked to 18% while the voice speaks; `AVAudioSession` `.playback`. Tap to pick or mute, long
press to change.

---

### P18 · `ios-p18-reminders` · Remind once a day, never on a day already trained

**Depends on:** P8. **Milestone C.** **Port:** `ReminderScheduler`, `ReminderReceiver`,
`ReminderNotifier`. **Kotlin tests:** the 10 `ReminderDeliveryTest`s, as screen-model and
scheduling tests.

**iOS deviation, the main one:** iOS runs no code when a notification fires, so the text cannot be
worked out at that moment. Instead, schedule the next seven days as separate one-off requests,
each with the text `Reminder` gives for that day; remove today's when a session finishes; and plan
them again on launch, after each session, on a time-zone change and when the setting changes. iOS
delivers on time, so the "more than two hours late" rule has nothing to do. During a live workout
`willPresent` shows nothing. TRY IT; "Blocked" when permission is denied.

---

### P19 · `ios-p19-strava-core` · Build the same Strava uploads

**Depends on:** P3, P9. **Port:** `StravaPayload`, `StravaActivityText`, `StravaSets`,
`StravaHeartRate`, `StravaApi`, `StravaHttp`, `StravaAuth`, `StravaTokens`, `StravaUploads`,
`StravaComposer`, `StravaConfig`.

**Kotlin tests: 125 pure**, with `FakeTransport`.

- `StravaHttp` over `URLSession` behind a transport protocol; `FoundationNetworking` on Linux.
- The payload and activity text identical to Android's for the same attempt: compare parsed JSON
  in the tests, field by field.
- The tokens' logic here; their storage in the Keychain comes with P20.

---

### P20 · `ios-p20-strava-app` · Connect Strava, ask first, and upload in the background

**Depends on:** P19, P11, P13. **Decisions:** D5, D7. **Milestone D.** **Port:**
`StravaAuthActivity`, `StravaConsent`, `StravaUploadWorker`.

**Kotlin tests: 49 screen** (`StravaScreenTest`, `StravaConsentTest`, `StravaSessionTest`,
`StravaUploadWorkerTest`).

- **The consent sheet first, from every road that starts OAuth**, with Strava's own Connect
  button and the "Compatible with Strava" mark, copied from the official artwork as Android did.
  Nothing is stored or opened until the button is tapped.
- OAuth through the Strava app when it is installed (`strava://oauth/mobile/authorize`,
  `LSApplicationQueriesSchemes`), otherwise `ASWebAuthenticationSession`. The redirect scheme is
  the bundle ID (D5), as Android's is the application ID.
- Tokens in the Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, which keeps them
  out of backups and device transfer, as Android excludes them.
- **Background uploads, iOS deviation:** no WorkManager. A persisted queue, sent at once after the
  session (inside `beginBackgroundTask`), again whenever the app comes forward, and when a
  `BGAppRefreshTask` runs; `NWPathMonitor` to wait for a network; `StravaUploads`' backoff. The
  README and Help say an upload may wait until the app is next opened.
- **No `Strava.xcconfig`, no Strava**: no menu row, no Help section, no tutorial bullet, nothing
  uploaded. A test pins that, as `NoStravaCredentials` does.

---

### P21 · `ios-p21-app-store` · Put it on TestFlight, and write the App Store listing

**Depends on:** milestone C (and D if Strava ships). **Decisions:** D5, D7, D8. Mirrors the
`play/` work (#62 to #65).

- `PrivacyInfo.xcprivacy` with every required-reason API actually used (`UserDefaults` at least;
  audit for file timestamps and `systemUptime`).
- `ITSAppUsesNonExemptEncryption = NO` (HTTPS only).
- `appstore/`: name (30), subtitle (30), promotional text (170), description (4,000), keywords
  (100), release notes; the privacy nutrition labels for each build, with and without Strava; the
  age rating answers; App Review notes (SKIP past the setup check, `+1` to book reps). Rendered
  with `tools/play/render.py`'s `{{#strava}}` blocks, extended rather than copied.
- A test like `PlayListingTest`, which holds the listing to Apple's limits and to the app's own
  facts (the language count from `VoicePacks`), runs in `core`.
- The 1024 px icon from the launcher mark, no transparency.
- Version 1.0.0, build 1; the README's iOS section says how to archive and upload.

**Needs you:** the Developer Program membership, the bundle ID, signing, the upload to App Store
Connect, the screenshots, and TestFlight testers.

---

## After parity

Once P2 lands, the two apps share a specification enforced by `trace_jvm.csv`. From then on, an
Android PR that changes any file in Appendix A whose destination is CindyCore should either port
the change to Swift in the same PR or open an issue for it, and `ios/PARITY.md` says which.

---

## Appendix A · Every Kotlin file, and the phase that ports it

"In Swift today" means a Swift file of that name exists, at the September sync; it does not mean
it is current.

| Phase | Kotlin file | Lines | Lands in | In Swift today |
|---|---|---|---|---|
| P2 | `BarZone.kt` | 127 | CindyCore | partly |
| P2 | `CameraStability.kt` | 116 | CindyCore |  |
| P2 | `PoseGeometry.kt` | 168 | CindyCore | partly |
| P2 | `PosePrediction.kt` | 161 | CindyCore |  |
| P2 | `RepCounter.kt` | 279 | CindyCore | partly |
| P2 | `SmartSquatCounter.kt` | 163 | CindyCore |  |
| P2 | `StartPoses.kt` | 233 | CindyCore |  |
| P2 | `TrackingHealth.kt` | 277 | CindyCore | partly |
| P2 | `Variations.kt` | 266 | CindyCore | partly |
| P2 | `WorkoutEngine.kt` | 1247 | CindyCore | partly |
| P3 | `Comparisons.kt` | 64 | CindyCore |  |
| P3 | `Levels.kt` | 41 | CindyCore | partly |
| P3 | `LiveWorkout.kt` | 9 | CindyCore |  |
| P3 | `RecordStore.kt` | 360 | CindyCore (`Records` format) + CindyTracker-free `RecordStore` over `UserDefaults` |  |
| P3 | `RepLog.kt` | 59 | CindyCore |  |
| P3 | `RepTimesStore.kt` | 118 | CindyCore (format + file store) |  |
| P3 | `RoundSplits.kt` | 229 | CindyCore |  |
| P3 | `SessionStats.kt` | 206 | CindyCore |  |
| P3 | `SplitBook.kt` | 51 | CindyCore |  |
| P4 | `Coach.kt` | 192 | CindyCore |  |
| P4 | `Phrasebook.kt` | 40 | CindyCore |  |
| P4 | `PhrasebookDe.kt` | 112 | CindyCore |  |
| P4 | `PhrasebookEn.kt` | 77 | CindyCore |  |
| P4 | `PhrasebookEs.kt` | 107 | CindyCore |  |
| P4 | `PhrasebookFr.kt` | 111 | CindyCore |  |
| P4 | `PhrasebookIt.kt` | 108 | CindyCore |  |
| P4 | `PhrasebookNl.kt` | 107 | CindyCore |  |
| P4 | `PhrasebookPl.kt` | 137 | CindyCore |  |
| P4 | `PhrasebookPt.kt` | 119 | CindyCore |  |
| P4 | `PhrasebookRo.kt` | 117 | CindyCore |  |
| P4 | `PhrasebookRu.kt` | 133 | CindyCore |  |
| P4 | `PhrasebookTr.kt` | 97 | CindyCore |  |
| P4 | `Plurals.kt` | 54 | CindyCore |  |
| P4 | `RecordedHud.kt` | 109 | CindyCore |  |
| P4 | `TtsEngine.kt` | 91 | CindyCore (protocol) |  |
| P4 | `VoiceChoice.kt` | 138 | CindyCore |  |
| P4 | `VoiceDirector.kt` | 284 | CindyCore |  |
| P4 | `VoiceHints.kt` | 53 | CindyCore |  |
| P4 | `VoiceLanguageText.kt` | 114 | CindyCore |  |
| P4 | `VoiceLine.kt` | 148 | CindyCore |  |
| P4 | `VoicePacks.kt` | 79 | CindyCore |  |
| P5 | `FrameHandoff.kt` | 80 | CindyCore |  |
| P5 | `FrameLatency.kt` | 234 | split: `Rolling`/`RateMeter`/probe maths → CindyCore, camera timestamps → CindyTracker |  |
| P5 | `OverlayTransform.kt` | 249 | CindyCore (pure maths, ported with its tests) |  |
| P5 | `OverlayView.kt` | 247 | CindyTracker (iOS rewrite) |  |
| P5 | `PoseDetector.kt` | 464 | CindyTracker (iOS rewrite) |  |
| P5 | `YuvCrop.kt` | 141 | not ported — Android YUV path; Vision's `regionOfInterest` replaces it |  |
| P6 | `CindySheet.kt` | 354 | CindyTracker (iOS rewrite) |  |
| P6 | `CindyViews.kt` | 453 | CindyTracker (iOS rewrite) |  |
| P6 | `CountdownView.kt` | 199 | CindyTracker (iOS rewrite) |  |
| P6 | `Dialogs.kt` | 313 | CindyTracker (iOS rewrite) |  |
| P6 | `LaunchView.kt` | 215 | CindyTracker (iOS rewrite) |  |
| P6 | `MainActivity.kt` | 1939 | CindyTracker (iOS rewrite) |  |
| P6 | `PlacementFacts.kt` | 48 | CindyTracker (iOS rewrite) |  |
| P6 | `PlacementGuideView.kt` | 202 | CindyTracker (iOS rewrite) |  |
| P6 | `StartPoseView.kt` | 273 | CindyTracker (iOS rewrite) |  |
| P8 | `Avatar.kt` | 144 | CindyCore |  |
| P8 | `Badges.kt` | 415 | CindyCore |  |
| P8 | `CalendarGrid.kt` | 25 | CindyCore |  |
| P8 | `Cheer.kt` | 129 | CindyCore |  |
| P8 | `Equivalents.kt` | 148 | CindyCore |  |
| P8 | `FirstRun.kt` | 53 | CindyCore (the flags) over `UserDefaults` |  |
| P8 | `HudTour.kt` | 45 | CindyCore |  |
| P8 | `Lifted.kt` | 205 | CindyCore |  |
| P8 | `Onboarding.kt` | 51 | CindyCore |  |
| P8 | `Peaks.kt` | 142 | CindyCore |  |
| P8 | `Progress.kt` | 322 | CindyCore |  |
| P8 | `Reminder.kt` | 114 | CindyCore |  |
| P8 | `SpotlightMath.kt` | 36 | CindyCore |  |
| P8 | `StatTiles.kt` | 278 | split: `SessionTiles` → CindyCore (P8), the tile views → CindyTracker (P11) |  |
| P8 | `Streak.kt` | 186 | CindyCore |  |
| P9 | `Calories.kt` | 285 | CindyCore |  |
| P9 | `HeartRate.kt` | 158 | CindyCore (types, measurement parsing) |  |
| P9 | `HeartRateRecorder.kt` | 150 | CindyCore |  |
| P9 | `HeartRateStats.kt` | 176 | CindyCore |  |
| P9 | `HeartRateStore.kt` | 112 | CindyCore (trace format) + CindyTracker (file I/O) |  |
| P9 | `SessionTimeline.kt` | 518 | CindyCore |  |
| P10 | `AndroidTtsEngine.kt` | 152 | CindyTracker (iOS rewrite) |  |
| P10 | `LanguageGroup.kt` | 298 | CindyTracker (iOS rewrite) |  |
| P10 | `Speaker.kt` | 177 | CindyTracker (iOS rewrite) |  |
| P11 | `ResultsActivity.kt` | 1349 | CindyTracker (iOS rewrite) |  |
| P11 | `RoundSplitsView.kt` | 505 | CindyTracker (iOS rewrite) |  |
| P11 | `RoundTrackView.kt` | 313 | CindyTracker (iOS rewrite) |  |
| P11 | `SessionTimelineView.kt` | 650 | CindyTracker (iOS rewrite) |  |
| P11 | `ZoneBarView.kt` | 342 | CindyTracker (iOS rewrite) |  |
| P12 | `CalendarView.kt` | 261 | CindyTracker (iOS rewrite) |  |
| P12 | `ProgressChartView.kt` | 503 | CindyTracker (iOS rewrite) |  |
| P12 | `RecordsActivity.kt` | 748 | CindyTracker (iOS rewrite) |  |
| P12 | `WeekStripView.kt` | 105 | CindyTracker (iOS rewrite) |  |
| P13 | `AccountActivity.kt` | 340 | CindyTracker (iOS rewrite) |  |
| P13 | `AvatarStore.kt` | 149 | CindyTracker (image I/O); square-crop maths already in `Avatar` |  |
| P13 | `AvatarView.kt` | 127 | CindyTracker (iOS rewrite) |  |
| P13 | `MenuActivity.kt` | 1208 | CindyTracker (iOS rewrite) |  |
| P13 | `Profile.kt` | 283 | CindyCore (values, tidy rules) + `UserDefaults` |  |
| P14 | `AppLinks.kt` | 14 | CindyCore |  |
| P14 | `HelpActivity.kt` | 870 | CindyTracker (iOS rewrite) |  |
| P14 | `Licences.kt` | 48 | CindyTracker (iOS rewrite) |  |
| P14 | `SpotlightView.kt` | 307 | CindyTracker (iOS rewrite) |  |
| P14 | `TutorialActivity.kt` | 356 | CindyTracker (iOS rewrite) |  |
| P15 | `BleHeartRateSource.kt` | 434 | CindyTracker; `reconnectDelayMs` → CindyCore |  |
| P15 | `HeartRatePermissions.kt` | 58 | CindyTracker (iOS needs only Bluetooth; no location path) |  |
| P15 | `HeartRateScanner.kt` | 263 | CindyTracker; pure `HeartRateAdvert` matching → CindyCore |  |
| P16 | `RecordingOverlay.kt` | 310 | CindyTracker (iOS rewrite) |  |
| P16 | `VideoRecorder.kt` | 159 | CindyTracker (iOS rewrite) |  |
| P17 | `MusicPlayer.kt` | 136 | CindyTracker (iOS rewrite) |  |
| P18 | `ReminderNotifier.kt` | 58 | CindyTracker (iOS rewrite) |  |
| P18 | `ReminderReceiver.kt` | 47 | CindyTracker (iOS rewrite) |  |
| P18 | `ReminderScheduler.kt` | 62 | CindyTracker (iOS rewrite) |  |
| P19 | `StravaActivityText.kt` | 95 | CindyCore |  |
| P19 | `StravaApi.kt` | 181 | CindyCore |  |
| P19 | `StravaAuth.kt` | 237 | CindyCore |  |
| P19 | `StravaComposer.kt` | 41 | CindyCore |  |
| P19 | `StravaConfig.kt` | 63 | CindyCore |  |
| P19 | `StravaHeartRate.kt` | 28 | CindyCore |  |
| P19 | `StravaHttp.kt` | 173 | CindyCore (`URLSession` behind a transport protocol) |  |
| P19 | `StravaPayload.kt` | 167 | CindyCore |  |
| P19 | `StravaSets.kt` | 67 | CindyCore |  |
| P19 | `StravaTokens.kt` | 170 | CindyCore (logic) + Keychain store in CindyTracker |  |
| P19 | `StravaUploads.kt` | 154 | CindyCore (state machine) + CindyTracker (scheduling) |  |
| P20 | `StravaAuthActivity.kt` | 119 | CindyTracker (iOS rewrite) |  |
| P20 | `StravaConsent.kt` | 100 | CindyTracker (iOS rewrite) |  |
| P20 | `StravaUploadWorker.kt` | 178 | CindyTracker (iOS rewrite) |  |

## Appendix B · Every Kotlin test file, and the phase that ports it

Pure tests are ported one for one. Screen tests become screen-model tests in CindyCore and UI tests,
as their phase describes. `ScreenSmokeTest` covers every screen, so its tests are split across the
phases that build them.

| Phase | Kotlin test | Tests | Kind |
|---|---|---|---|
| P2 | `AssistedPullupTest` | 16 | pure |
| P2 | `BarGateTest` | 12 | pure |
| P2 | `BarGuideTest` | 6 | pure |
| P2 | `CameraStabilityTest` | 7 | pure |
| P2 | `EngineParityTraceTest` | 1 | pure |
| P2 | `HeelsFlatSquatTest` | 18 | pure |
| P2 | `KneePushupTest` | 3 | pure |
| P2 | `LimitedExtensionPullupTest` | 4 | pure |
| P2 | `PosePredictionTest` | 14 | pure |
| P2 | `PullupOcclusionTest` | 12 | pure |
| P2 | `RepCounterMarginsTest` | 4 | pure |
| P2 | `RepCounterTest` | 7 | pure |
| P2 | `SetupTest` | 7 | pure |
| P2 | `SkippedRepsTest` | 11 | pure |
| P2 | `SmartSquatTest` | 21 | pure |
| P2 | `StartPositionTest` | 12 | pure |
| P2 | `TrackingHealthTest` | 15 | pure |
| P2 | `VariationsTest` | 15 | pure |
| P2 | `WorkoutEngineTest` | 28 | pure |
| P3 | `ComparisonsTest` | 14 | pure |
| P3 | `LevelsTest` | 7 | pure |
| P3 | `RecordStoreTest` | 2 | screen (Robolectric) |
| P3 | `RecordsTest` | 32 | pure |
| P3 | `RepLogTest` | 9 | pure |
| P3 | `RepTimesStoreTest` | 3 | screen (Robolectric) |
| P3 | `RepTimesTest` | 10 | pure |
| P3 | `RoundSplitsTest` | 36 | pure |
| P3 | `SessionStatsTest` | 18 | pure |
| P3 | `SplitBookTest` | 8 | pure |
| P4 | `CoachClockTest` | 14 | pure |
| P4 | `CoachTest` | 12 | pure |
| P4 | `PhrasebookDeTest` | 6 | pure |
| P4 | `PhrasebookEnTest` | 18 | pure |
| P4 | `PhrasebookEsTest` | 6 | pure |
| P4 | `PhrasebookFrTest` | 6 | pure |
| P4 | `PhrasebookItTest` | 6 | pure |
| P4 | `PhrasebookNlTest` | 6 | pure |
| P4 | `PhrasebookPlTest` | 8 | pure |
| P4 | `PhrasebookPtTest` | 7 | pure |
| P4 | `PhrasebookRoTest` | 8 | pure |
| P4 | `PhrasebookRuTest` | 8 | pure |
| P4 | `PhrasebookTrTest` | 7 | pure |
| P4 | `PhrasebooksTest` | 12 | pure |
| P4 | `PluralsTest` | 6 | pure |
| P4 | `RecordedHudTest` | 13 | pure |
| P4 | `VoiceChoiceTest` | 23 | pure |
| P4 | `VoiceDirectorTest` | 33 | pure |
| P4 | `VoiceHintsTest` | 7 | pure |
| P4 | `VoiceLanguageTextTest` | 16 | pure |
| P4 | `VoicePacksTest` | 9 | pure |
| P5 | `FrameHandoffTest` | 7 | pure |
| P5 | `LatencyTest` | 9 | pure |
| P5 | `OverlayTransformTest` | 21 | pure |
| P5 | `UprightTransformTest` | 6 | pure |
| P5 | `YuvCropTest` | 11 | not ported |
| P6 | `CountdownTest` | 3 | screen (Robolectric) |
| P6, P11–P14 | `ScreenSmokeTest` | 63 | screen (Robolectric) |
| P8 | `AvatarTest` | 37 | pure |
| P8 | `BadgesTest` | 75 | pure |
| P8 | `CalendarGridTest` | 5 | pure |
| P8 | `CheerTest` | 22 | pure |
| P8 | `EquivalentsTest` | 19 | pure |
| P8 | `LiftedTest` | 17 | pure |
| P8 | `OnboardingTest` | 7 | pure |
| P8 | `PeaksTest` | 22 | pure |
| P8 | `ProgressTest` | 29 | pure |
| P8 | `ReminderTest` | 22 | pure |
| P8 | `SpotlightMathTest` | 8 | pure |
| P8 | `StatTilesTest` | 11 | pure |
| P8 | `StreakTest` | 26 | pure |
| P9 | `CaloriesHeartRateTest` | 9 | pure |
| P9 | `CaloriesTest` | 9 | pure |
| P9 | `CaloriesTimelineTest` | 9 | pure |
| P9 | `HeartRateMeasurementTest` | 7 | pure |
| P9 | `HeartRateRecorderTest` | 10 | pure |
| P9 | `HeartRateStatsTest` | 22 | pure |
| P9 | `HeartRateStoreTest` | 3 | screen (Robolectric) |
| P9 | `HeartRateTracesTest` | 5 | pure |
| P9 | `SessionTimelineCaloriesTest` | 15 | pure |
| P9 | `SessionTimelineTest` | 37 | pure |
| P10 | `AndroidTtsEngineTest` | 13 | screen (Robolectric) |
| P10 | `LanguageGroupTest` | 23 | screen (Robolectric) |
| P10 | `SpeakerTest` | 22 | screen (Robolectric) |
| P11 | `RoundSplitsViewTest` | 10 | screen (Robolectric) |
| P11 | `RoundTrackViewTest` | 7 | screen (Robolectric) |
| P11 | `SessionTimelineViewTest` | 13 | screen (Robolectric) |
| P11 | `ZoneBarViewTest` | 9 | screen (Robolectric) |
| P12 | `CalendarViewTest` | 4 | screen (Robolectric) |
| P12 | `ProgressChartViewTest` | 4 | screen (Robolectric) |
| P13 | `AccountScreenTest` | 34 | screen (Robolectric) |
| P13 | `HeelsFlatScreensTest` | 11 | screen (Robolectric) |
| P13 | `ProfileHeartRateTest` | 8 | screen (Robolectric) |
| P13 | `ProfileVoiceLanguageTest` | 5 | screen (Robolectric) |
| P14 | `HelpScreenTest` | 10 | screen (Robolectric) |
| P14 | `HudTourTest` | 17 | screen (Robolectric) |
| P14 | `LicencesTest` | 3 | screen (Robolectric) |
| P14 | `TutorialScreenTest` | 29 | screen (Robolectric) |
| P15 | `BleHeartRateSourceTest` | 1 | pure |
| P15 | `HeartRateAdvertTest` | 9 | pure |
| P15 | `HeartRatePermissionSheetTest` | 3 | screen (Robolectric) |
| P15 | `HeartRatePermissionsTest` | 2 | pure |
| P18 | `ReminderDeliveryTest` | 10 | screen (Robolectric) |
| P19 | `StravaActivityTextTest` | 23 | pure |
| P19 | `StravaApiTest` | 25 | pure |
| P19 | `StravaAuthTest` | 23 | pure |
| P19 | `StravaHeartRateTest` | 6 | pure |
| P19 | `StravaHttpTest` | 16 | pure |
| P19 | `StravaPayloadTest` | 15 | pure |
| P19 | `StravaSetsTest` | 10 | pure |
| P19 | `StravaUploadsTest` | 7 | pure |
| P20 | `StravaConsentTest` | 7 | screen (Robolectric) |
| P20 | `StravaScreenTest` | 18 | screen (Robolectric) |
| P20 | `StravaSessionTest` | 6 | screen (Robolectric) |
| P20 | `StravaUploadWorkerTest` | 18 | screen (Robolectric) |
| P21 | `PlayListingTest` | 11 | pure |
| P21 | `PlayPolicyTest` | 5 | screen (Robolectric) |

## Appendix C · Pull request body

The house template, from #59 to #65. Leave out a section only when it has nothing to say.

```markdown
## What changes

One paragraph: what the athlete or the developer can now do that they could not, and which phase
this is ("P2 of the iOS plan"). Then a bullet per change, each saying what and why.

## Tested

- `swift test` on Linux, counted from the output: **N tests, 0 failures**. `main` has M; the
  new ones are …
- Parity: **1,639 of 1,639 frames**.
- | Kotlin test | Kotlin | Swift |  — one row per ported file.
- **Mutation check:** what was broken, what failed, restored.
- CI: `core` and `app` green on <sha>.

## Verified by hand

What was read and compared, line by line, and what was checked against the Kotlin.

## iOS deviations

Each place iOS cannot do what Android does, what it does instead, and where the app says so.

## Needs you

Decisions, accounts, devices. Numbered if more than one.

## Not in this PR

What a reader might expect here and which phase has it.

## Still owed

What only a real iPhone can show, as steps the owner can follow.
```
