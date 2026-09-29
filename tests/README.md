# Video regression fixtures

This directory holds the inputs and reports for Cindy's offline, real-video regression job.
The job runs on an Android emulator or device because it calls the production `PoseDetector`
(including its MoveNet asset, bitmap preprocessing and ROI tracker) and feeds those keypoints to
the production `WorkoutEngine`.

## Fixture policy

- Keep only short, consented, non-sensitive clips in `fixtures/local/`.
- Keep InfiniteRep and RepCount downloads/extractions out of git. The directories are ignored;
the small scenario JSON files remain versioned and describe what a provisioned CI worker should
run.
- Add a local fixture whenever a production counting bug is fixed. Its scenario should name the
bug and include `regression` in `tags`.

## Layout

```text
tests/
├── fixtures/
│   ├── infiniterep/{pushups,squats}/
│   ├── repcount/{pullups,squats}/
│   └── local/{pullups,pushups,squats}/
├── scenarios/{infiniterep,repcount,local_regressions}.json
├── golden/pose_keypoints/
└── reports/
```

## Build catalogues from downloaded datasets

Place datasets in any local directory, then generate labels whose video paths point to the
fixture tree:

```sh
python3 tools/video_regression/build_scenarios.py infiniterep \
  --dataset /path/to/InfiniteRep \
  --fixture-root tests/fixtures/infiniterep \
  --output tests/scenarios/infiniterep.json

python3 tools/video_regression/build_scenarios.py repcount \
  --dataset /path/to/RepCount \
  --fixture-root tests/fixtures/repcount \
  --output tests/scenarios/repcount.json
```

The InfiniteRep importer pairs `{video_number}.mp4` with `{video_number}.json`, floors the last
valid per-frame `rep_count`, and preserves camera/FOV/occlusion conditions as tags. The RepCount
importer accepts action periods and cycle locations for `pulling-up` and `squatting`; inspect its
warnings before committing a generated catalogue.

## Run the video job

Connect an API-28+ emulator/device, provision the untracked files described by the catalogues,
then run:

```sh
./gradlew videoRegressionTest -PcindyVideoRegression=true
```

If the flag, scenarios, or any declared fixture is absent, the test is marked **skipped** with a
reason. That is intentional: a green result never means that unavailable proprietary fixtures
were tested.

Reports are emitted on the test device at:

```text
/sdcard/Android/data/com.cindy.tracker/files/video-regression/reports/
```

Pull them into the ignored `tests/reports/` directory with:

```sh
adb pull /sdcard/Android/data/com.cindy.tracker/files/video-regression/reports/. tests/reports/
```

To capture inferred pose goldens, append `-PcindyVideoGolden=true`, then pull
`.../video-regression/goldens/` into `tests/golden/pose_keypoints/`. The runner always performs
fresh inference; an existing golden is compared afterwards, so a pose/model drift is distinct
from a counter-logic regression.

## Scenario schema

Each catalogue is an object containing `scenarios`. A scenario has the required fields below;
`expectedRepEventsMs`, `eventToleranceMs`, and `model` are optional.

```json
{
  "id": "pullup_not_on_bar_never_counts",
  "video": "tests/fixtures/local/pullups/not_on_bar.mp4",
  "exercise": "pullup",
  "expectedReps": 0,
  "expectedSetup": "valid",
  "expectedCountingState": "idle",
  "bar": {
    "mode": "manual",
    "yNormalized": 0.22,
    "xMinNormalized": 0.15,
    "xMaxNormalized": 0.85
  },
  "tags": ["regression", "false-positive", "bar-gating"]
}
```

`expectedSetup` accepts `valid` (framed and moving), `ready`, `framing`/`invalid`, or
`poor`/`paused`. The runner checks setup with a dedicated engine and scores the full labelled
clip with a second fixed-exercise engine, so setup calibration reps do not silently subtract from
dataset annotations.

---

# Desktop harness (Python)

The Android job above is the highest-fidelity check, but it needs an emulator or device, which
makes the edit/run loop too slow to actually debug counting with. `tools/video_regression/`
holds a Python twin of the same pipeline that scores a clip in about a second per 350 frames, so
a counting bug can be reproduced, instrumented and iterated on directly.

```text
tools/video_regression/
├── cindy_sim/
│   ├── keypoints.py        # Keypoint + COCO-17 indices
│   ├── pose_detector.py    # MoveNet + ROI tracking, from PoseDetector.kt
│   ├── rep_counter.py      # from RepCounter.kt
│   ├── bar_zone.py         # from BarZone.kt
│   ├── workout_engine.py   # from WorkoutEngine.kt
│   └── pose_fixtures.py    # from the JVM test PoseFixtures.kt
├── build_scenarios.py      # dataset importers (InfiniteRep / RepCount)
├── parity_check.py         # proves the port still matches the Kotlin
├── run_batch.py            # scores scenarios, same schema as the Android job
├── fetch_youtube.py        # re-provisions the third-party clip fixtures
└── contact_sheet.py        # timestamped tiles, for counting reps by eye
```

It reads the real `.tflite` assets out of `app/src/main/assets`, so the network is byte-identical
to the phone's.

## Setup

```sh
python3.12 -m venv .venv
.venv/bin/pip install ai-edge-litert numpy opencv-python-headless yt-dlp
brew install ffmpeg      # contact sheets and yt-dlp muxing only
```

## Keeping the port honest

Two implementations of the same rules drift, and a harness that has quietly stopped agreeing
with the phone is worse than no harness — it gives confident, wrong verdicts. So the port is not
trusted on inspection; it is diffed against the production Kotlin frame by frame.

`EngineParityTraceTest` (a JVM unit test) replays `tests/parity/plan.csv` through the real
`WorkoutEngine` and writes every frame's decision to `tests/parity/trace_jvm.csv`.
`parity_check.py` replays the same plan through the port and compares all 18 columns — event,
count, phase, signal, learned range, hint and every diagnostic flag — so a divergence is
localised to one frame rather than to "the totals disagree".

```sh
./gradlew testDebugUnitTest --tests 'com.cindy.tracker.EngineParityTraceTest'
.venv/bin/python tools/video_regression/parity_check.py
```

Run this after touching either implementation. It currently passes on all 372 frames.

The pull-up gates themselves — occlusion tolerance, the derived dead-hang angle and bar
re-establishment — are covered by the Kotlin unit tests and the parity trace above. `MAX_DROPOUT_FRAMES`
was picked by sweeping it against the labelled clips; re-run that sweep after any change to the
gates, since the useful value is the knee of that curve rather than a round number.

One porting note worth keeping in mind: Kotlin holds this state in 32-bit `Float`s, and the
thresholds are exact comparisons (`elbow >= DEAD_HANG_DEGREES`). A 64-bit port diverges on
frames that land exactly on a threshold, so `f32()` rounds at every point the Kotlin stores a
`Float`. That is not pedantry — it was a real, reproducible one-frame divergence before the fix.

**A known discrepancy, left alone on purpose.** The harness reads the detector's tracking flag
one frame earlier than the app does. `run_batch.py`'s `infer_video` captures
`detector.tracking` *before* calling `detector.detect()` for that frame, so the flag it hands the
engine describes the *previous* frame's crop state; `MainActivity.analyse` calls `det.detect(...)`
first and only reads `det.tracking` afterwards, in the same call that feeds the engine, so it
always describes the *current* frame. The two therefore disagree for exactly one frame around
every crop-tracking transition. This is not fixed here, because doing so would shift every
existing baseline by up to a frame's worth of tracking state on the clips that exercise it, and
nothing currently depends on the flag meaning anything more than "was a crop being followed" —
only pull-up counting reads it at all today, gated by `MAX_DROPOUT_FRAMES`, which absorbs a
one-frame flicker regardless of which side of the transition it lands on. A rewrite that reads the
flag consistently everywhere is a bigger, separate change.

## Scoring clips

```sh
# a labelled catalogue
.venv/bin/python tools/video_regression/run_batch.py --scenarios tests/scenarios/youtube.json

# one clip, ad hoc, with every scoring frame printed
.venv/bin/python tools/video_regression/run_batch.py \
    --video tests/fixtures/youtube/pullups/AB5LE7WDvcQ.mp4 --exercise pullup --expect 10 --frames
```

Reports land in the ignored `tests/reports/`.

## Diagnosing a miss

A count mismatch says a rep is missing, not which gate refused it. `diagnose_pullups.py` answers
the second question:

```sh
.venv/bin/python tools/video_regression/diagnose_pullups.py --clip AB5LE7WDvcQ
.venv/bin/python tools/video_regression/diagnose_pullups.py --all
```

It finds the repetitions the athlete visibly performed using a deliberately dumb oracle —
hysteresis on the raw bilateral elbow angle, with no bar, head or dead-hang gate involved, so it
cannot inherit the failure it is measuring — matches them against the reps the engine booked, and
names the first gate that stood in the way of each unmatched one:

```text
=== AB5LE7WDvcQ ===
  expected 10  actual 9  error -1
  oracle saw 10 visual reps, 9 matched a booking
  MISSED @4462ms  DEAD_HANG_NARROWLY_MISSED  — peak elbow 149.0 vs threshold 150.0 (short by 1.0)
```

Per clip it writes `<id>.events.jsonl` (one row per frame), `<id>.summary.json` (counts, gate
histogram, classified misses) and `<id>.timeline.csv` (plot-ready) into the ignored
`reports/diagnostics/`.

**Diagnose before tuning.** A single clip's miss is a data point, not a defect. Only generalise a
fix when the same classification reproduces across at least two clips or a synthetic semantic
test — otherwise the likely outcome is trading an under-count for a false positive, which is the
worse failure.

## Evaluation policy

`run_batch.py` reports metrics grouped by category, because averaging valid clips together with
deliberately-invalid ones produces a flattering number that means nothing:

- **clean-valid** — ordinary footage; the target is an exact count.
- **difficult-but-valid** — tagged `occlusion`, `camera-cut` or `known-gap`; judged on error size.
- **must-not-count** — `expectedReps: 0`; the only acceptable false-positive count is zero.

A scenario may carry `countTolerance`. That is an evaluation policy for footage explicitly
annotated as visually ambiguous — never permission to hide a regression. `expectedReps` stays at
ground truth and the signed error is printed whether or not the scenario passes, so a clip that
counts 9 against a truth of 10 still reports `-1`.

## Labelling new clips

Expected rep counts must come from somewhere other than the pipeline under test, or the suite
merely asserts that today's bugs are still present. `contact_sheet.py` renders timestamped tiles
so a clip can be counted by eye:

```sh
.venv/bin/python tools/video_regression/contact_sheet.py clip.mp4 --fps 4 --grid 8x6
```

`tests/fixtures/youtube/sources.json` records, per clip, how its label was established and how
much it is trusted. Clips whose count is not yet verified stay `status: "candidate"` and assert
nothing.

## Cindy mode

A scenario with `"exercise": "cindy"` (or `--exercise cindy` ad hoc) scores the real progression
instead of one fixed movement: no exercise is pinned, setup runs until it reports READY, and only
then does the clip get scored frame by frame through the whole pull-up → push-up → squat → …
cycle — the same order the app itself uses: `on_setup_frame` every frame while in setup,
`finish_setup()` the moment it reports READY, and `on_frame` for every frame after that, never
both for the same frame. This is the only path that crosses a movement transition, which matters
for anything that has to survive one.

Because setup is not skipped, calibration behaves exactly as it does on the phone: the athlete's
first two pull-ups are consumed to learn the rep-detection band, then zeroed out the moment the
clock starts, so they never count toward the pull-up total. A `cindy` scenario's
`expectedRepsByMovement` (an object such as `{"pullup": 3, "pushup": 5, "squat": 5}`) must
therefore be the *labelled* total for each movement — every rep visible in the clip, calibration
included — and the reported `observed` count for pull-ups will legitimately run two lower than
that label once calibration completes. If setup never reaches READY at all (the learned range
never clears the movement's threshold, or the count never reaches two), no workout frames are
scored, every movement reports zero, and the failure says so explicitly rather than reporting a
misleading exact-zero pass.

Two optional fields reproduce the athlete's own controls, for footage the counter cannot
calibrate or progress on by itself. `"setup": "skip"` is the SKIP button: no calibration, so the
label equals the expected count. `"skipTo": [{"atMs": 25000, "movement": "pushup"}]` is the athlete
tapping skip when the app has not moved on by itself: at that time, if the engine is still on an
earlier movement, it banks what was done and advances. A movement the engine already reached on its
own is left alone. `tests/scenarios/cindy.json` uses both, because production counts only one
of that clip's five pull-ups, too few to calibrate or to finish the movement.

Per-movement results land in each report's `per_movement` object (`expected`/`observed`/
`eventsMs`), alongside the usual single `expectedReps`/`observedReps` totals summed across
movements.

## Real two-person clips

A local catalogue of real footage with a bystander in shot (never committed — real people are not
test fixtures) can be scored the same way the synthetic composites are, via
`tools/video_regression/identity/run_identity.py --catalogue <path to catalogue.json>`. The
catalogue is a JSON object:

```json
{
  "version": 1,
  "clips": [
    {
      "id": "scenario_a_bystander_still",
      "scenario": "a",
      "video": "scenario_a.mp4",
      "groundTruth": "scenario_a.truth.json",
      "repsMs": { "pullup": [1234, 2456], "pushup": [], "squat": [] }
    }
  ]
}
```

`video` and `groundTruth` are resolved relative to the catalogue file itself unless they are
absolute paths. `scenario` is a single letter naming which of the recorded situations the clip
covers (a bystander standing still from before the athlete arrives; a partner near the athlete
during a movement transition; a partner walking behind then in front; a partner training the same
movement out of phase nearby; a partner starting the same movement at an adjacent station at the
same moment; the athlete leaving and returning to frame while the partner stays; the partner
stepping into the athlete's own spot while the athlete is briefly away; and, optionally, a mirror
or screen showing people behind the athlete). `repsMs` gives eye-labelled rep timestamps per
movement, established the same way any other clip's labels are (by eye, from a contact sheet,
never from the counter under test).

`groundTruth` points to a second JSON file with the per-frame athlete position, established from
an independent multi-person pose source and simple tracking, with the athlete's own track picked
by hand and spot-checked:

```json
{
  "frames": [
    { "index": 1, "athleteBox": [30, 40, 130, 480], "occluded": false,
      "torso": [[0,0,0], [0,0,0], [0,0,0], [0,0,0], [0,0,0],
                [62, 120, 0.9], [98, 122, 0.9], [0,0,0], [0,0,0], [0,0,0], [0,0,0],
                [66, 260, 0.9], [94, 262, 0.9], [0,0,0], [0,0,0], [0,0,0], [0,0,0]] }
  ]
}
```

`index` matches the frame indices the harness itself produces when it decodes the same video at
its own analysed rate (every second frame of a 30 fps source, 15 fps). `torso` is a full 17-entry
keypoint list in the same `(x, y, score)` order the pose detector emits, so the identity metrics'
existing torso helper works on it unchanged; entries outside the four shoulder/hip joints may be
left zeroed if only the torso was hand-tracked. `athleteBox` and `occluded` are optional extra
ground truth for frames where the athlete's whole body position or visibility is also worth
recording (a walk-through-style pass, or a departure and return), beyond what the torso alone
says.
