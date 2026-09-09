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
re-establishment — are specified in [PULLUP_LOGIC.md](../PULLUP_LOGIC.md). `MAX_DROPOUT_FRAMES`
was picked by sweeping it against the labelled clips; re-run that sweep after any change to the
gates, since the useful value is the knee of that curve rather than a round number.

One porting note worth keeping in mind: Kotlin holds this state in 32-bit `Float`s, and the
thresholds are exact comparisons (`elbow >= DEAD_HANG_DEGREES`). A 64-bit port diverges on
frames that land exactly on a threshold, so `f32()` rounds at every point the Kotlin stores a
`Float`. That is not pedantry — it was a real, reproducible one-frame divergence before the fix.

## Scoring clips

```sh
# a labelled catalogue
.venv/bin/python tools/video_regression/run_batch.py --scenarios tests/scenarios/youtube.json

# one clip, ad hoc, with every scoring frame printed
.venv/bin/python tools/video_regression/run_batch.py \
    --video tests/fixtures/youtube/pullups/AB5LE7WDvcQ.mp4 --exercise pullup --expect 10 --frames
```

Reports land in the ignored `tests/reports/`.

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
