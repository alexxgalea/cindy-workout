# Optimisation log

Every performance and accuracy optimisation in this app, in the order it happened,
with the measurement that justified it and the ideas that were rejected.

Scope: this is not a changelog. Features, UI work and ordinary bug fixes are left
out unless they changed what the counter sees or how fast it sees it.

**The throughline:** in all four phases, the intuitive fix was wrong and the
measurement said so. Keeping the rejections here is the point of the document —
they cost more to learn than the fixes did.

| Phase | Date | What moved | From | To |
|---|---|---|---|---|
| 0 · Feeding the model | 2026-09-08 | Input the model actually sees | whole tall frame | tracked square crop |
| 1 · Counting truthfully | 2026-09-08→09 | Verified 10-rep set | scored 1 | scored 9–10 |
| 2 · Seeing in the dark | 2026-09-12 | Usable light range | baseline | ≥ 3.3× darker |
| 3 · Closing the lag | 2026-09-12→14 | Glass-to-skeleton | ~175 ms | **~148 ms** |
| | | Analysis rate | 10.4 fps | **17.3 fps** |

---

## Phase 0 — Feed the model a body, not a ceiling

*`16409b1`, `5085d73` — 2026-09-08*

The athlete props a phone on a box 2–3 m away. MoveNet resizes whatever it is
given down to a small square, so feeding it a tall portrait frame spent most of
the model's input on ceiling and carpet and left the body a few dozen pixels
tall — which is exactly where keypoints get mushy and the rep counter starts
guessing.

**`PoseDetector` now crops each frame to a square around where the body was last
seen**, follows it at a damped rate, and falls back to the whole frame when
tracking is lost. This is the single most consequential decision in the pipeline,
and every later optimisation is shaped by it — the low-light gain measures *the
crop*, and the YUV sampler in Phase 3 only converts the pixels the crop needs.

Two decisions made here that were revisited later and both held:

- **Thunder over Lightning**, deliberately. The awkward angles a floor-level
  phone produces are where the accuracy earns its keep. Re-examined under
  measurement in Phase 3 and kept.
- **A debug readout from day one.** Long-pressing the status line showed
  inference time, crop state, signal, learned range and phase, so a miscount
  could be read off the screen rather than guessed at. Phase 3 is, in a sense,
  just this idea applied to a question nobody had thought to ask.

Also: **the x86 and x86_64 TFLite native libraries were dropped**, about 9 MB of
an APK that only ever gets sideloaded onto an ARM phone.

---

## Phase 1 — Count what actually happened

*`16409b1`, `f9f9447`, `da8f043` — 2026-09-08 → 09-09*

A verified 10-rep pull-up set scored **1**. Raising the phone made it count
better, which is the tell: where the phone sits should not be part of the
measurement.

Six faults, every one of which undercounted *silently*.

**The signal had hips in the denominator.** Pull-up travel was shoulder rise
divided by torso length. Hips are the least reliable joints on someone hanging
with their knees bent behind them, and a hip estimate drifting low inflates the
divisor until the signal never arms. It became **mean elbow angle**: three joints
close together in space, so perspective distorts them nearly equally, and an
angle needs no normalisation at all.

**The posture guard rejected good reps.** It threw away any frame where the
shoulders rose above the hands — which is precisely the top of a strong pull-up.
The better the rep, the more reliably it was discarded.

**Fixed thresholds cannot survive a floor-level camera.** Foreshortening squashes
everything above the lens. The counter now learns the range the athlete actually
produces and sets thresholds at 30% of that observed travel from each end, so
only the *shape* of the oscillation matters.

**A single occluded keypoint destroyed a whole rep.** Nose or wrist confidence
dips exactly as the chin clears the bar, which invalidated the entire cycle.
Now up to 8 consecutive unreadable frames are tolerated — **8 chosen by sweeping
0–24 against labelled clips**, not picked.

**Gated frames were starving the calibration.** Frames that failed the gate were
withheld from the counter entirely, so a calibrated setup reported a 45° range
for a 115° movement. Every readable frame is now observed for calibration; only
a fully gated one can book a rep.

**A bar learned in the wrong place could never correct itself,** because only
hangs that already passed its gate were allowed to refine it. One clip rejected
**2,377 of 2,888 frames** with "Get on the bar". The estimate is now abandoned
after sustained contradiction at a clearly different body scale.

**Result:** four real clips went 1→9, 0→9, 0→10, 0→9, with zero new false
positives on push-up and squat clips scored as pull-ups.

### The infrastructure this forced

Counting bugs were being chased on an emulator, one run at a time. This phase
built the thing that made every later phase cheap:

- **A line-by-line Python port** of `PoseDetector`, `RepCounter`, `BarZone` and
  `WorkoutEngine` that loads the real `.tflite` assets, so a counting bug can be
  reproduced against real video in seconds.
- **A frame-by-frame parity checker** diffing that port against production
  Kotlin, so the two cannot silently drift apart.

Every optimisation since has had to pass it. It currently checks 925 frames.

---

## Phase 2 — See the athlete in the dark

*`e3aafb8` — 2026-09-12*

A tester lost pull-up tracking around the tenth round of a Cindy, outdoors at
sunset. No recording existed, so the hypothesis was reproduced by darkening clips
of known score and running the real detector and engine over them.

**The failure was worse than reported.** The app does not stop at a cliff, it
bleeds. The same five pull-ups scored **5, 3, 2, 1, 0** as the light fell, with
nothing on screen or in the record to say the number had stopped being true. A
wrong score was being filed as a real result.

**Pull-ups fail about sixteen times sooner than push-ups,** because wrists held
overhead are the first keypoints lost — which is why the tester lost pull-ups
specifically, and why every later accuracy trade-off in this document is judged
on what it does to wrists.

### The fix

MoveNet does not normalise its own input, so an underexposed frame fails
*representationally* rather than for want of detail — the information is there,
the numbers are just small. Lifting the analysis crop to a normal mean brought
back all five reps at light levels that had scored zero, and extended the usable
range **at least threefold**.

Two details that matter:

- **Clamped**, so it cannot touch a well-exposed frame and cannot regress
  anything that already worked.
- **Measured on the crop, not the frame.** Auto-exposure meters the whole scene,
  so an athlete against a bright window is left dark inside a picture whose
  average looks perfectly healthy. The crop is already centred on the body.

It also fixed a miscount already recorded as a known gap: a rear-view clip that
scored 9 of 10 now scores 10 — which means that clip had been underexposed all
along and nobody had noticed.

### What brightening cannot do

Once the camera has raised its own gain to the limit, the information is gone and
multiplying amplifies noise along with signal. So `TrackingHealthMonitor` watches
the share of recent frames in which every joint the movement scores from was
legible — **against the session's own baseline**, because no absolute threshold
survives contact with real footage: one clip counts perfectly at 89% legible,
another at 31%. It warns while the count is still right and escalates when reps
are actually going missing.

A session the camera could not stand behind now records how long it was blind.
It is still saved, still shown, still feeds the streak — but it cannot set a
record. The error only runs one way, so "at least this much" is honest where
"a new record" is a claim about a precise number.

### Rejected in this phase

| Idea | Why not |
|---|---|
| Ambient light sensor (`TYPE_LIGHT`) | Sits beside the *front* camera; faces away from the scene when the rear lens is used. Many devices lack it, and it cannot appear in the offline harness, so no rule using it could ever be regression-tested. |
| Mean frame brightness | Counting is **perfect at luma 11 and dead at luma 70**. The distributions overlap by a factor of six in the wrong direction. This was our own proposal, killed by our own measurement. |
| Offering the torch | Roughly 20 lux at a metre is two or three at the 2–3 m the placement guide asks for. A placebo with a battery cost. |

---

## Phase 3 — Close the lag

*`dee67ac`, `7c3799d`, `67276c4` — 2026-09-12 → 09-14*

> "The skeleton preview on my phone is substantially delayed. To the point that
> it is not in real time."

That was the entire report. No number, no recording, no profile.

### Building the instrument first

The codebase contained exactly one timing value: milliseconds inside the TFLite
interpreter. Nothing measured end-to-end latency, frame rate, or how long a
finished pose waited for the main thread.

The trap worth knowing about: camera frame timestamps come from one of two
clocks, and the device tells you which through `SENSOR_INFO_TIMESTAMP_SOURCE` —
`CLOCK_MONOTONIC`, which stops while the phone sleeps, or `CLOCK_BOOTTIME`,
which does not. They drift apart by however long the handset has been asleep
since boot. Subtracting across the pair does not give a slightly wrong latency;
it gives a wildly wrong one that still looks plausible. The instrument resolves
the source once per camera bind and prints `age n/a (clock)` rather than a
fiction.

Constraint that shaped it: for most of this work there was no debugging bridge to
the phone. The app arrived as a file over HTTP and the only channel back was what
a person could photograph. Hence a two-line readout on the camera band, in
medians, legible at 14sp.

### What it said

```
age 175ms · cvt 26 · pre 10 · inf 50 · ui 0
thndr · 10.4 in · 10 drawn · 0% coalesced
```

**Half the budget was gone before a single line of our own code ran.**

### What worked

**Rotation folded into the crop matrix.** The frame was being turned upright by
allocating a second full-frame bitmap and bilinearly resampling into it — for a
pure 90° rotation, which needs no resampling at all. The detector already drew
through a transform, so the rotation was composed in front of it: one resample
instead of two, no intermediate bitmap, a marginally *sharper* input. Verified
on device at **0.0 px keypoint difference** against the path it replaced.

**The model's input read straight from the camera's YUV planes.** The pipeline
had been converting all 307,200 pixels of every frame to RGBA in order to use one
256×256 crop — about 8% of them. The sampler now walks the *destination*: for
each of the 65,536 pixels the model wants, work out which camera pixel feeds it
and convert that one. Luma interpolated, chroma point-sampled. The whole-frame
conversion does not get faster; it stops happening. `cvt` went **26 ms → 0**.

**The input filled once instead of 196,608 times.** The buffer was written one
channel at a time, each a bounds-checked write into off-heap memory. Now staged
in an array and copied in once. The brightness pass, which had walked all 65,536
pixels a second time to total up what the sampler had just written, now
accumulates as it writes. `pre` went **17 ms → 10 ms**.

### What didn't, and why it's kept here

| Belief | Verdict |
|---|---|
| **Add the GPU delegate** | **Refuted.** Both models are uint8-quantised — established by hand-writing a 40-line TFLite flatbuffer parser, because nothing in the repo recorded the dtype. TFLite's GPU path handles quantised models only through an experimental dequantise route, frequently slower than the int8 CPU path. |
| **4 threads on a 2-big-core chip is wrong** | **Refuted.** A first sweep showed a 14% win from dropping to 3. Running it in *reverse order* dissolved it into noise — a sweep that only counts upwards cannot tell a slow configuration from a warm phone. Settled: 2/3/4 threads → 43/43/44 ms. |
| **The UI queue is growing unbounded** | **Refuted.** A post-per-frame arrangement with no back-pressure is a textbook unbounded queue and a perfect explanation for lag that grows over a session. Measured `ui 0`, `0% coalesced`, every frame, all session. Fixed anyway as insurance; bought nothing. |
| **Predict where the body will be** | **Refuted twice.** The first attempt measured the horizon from when the pose was *published* rather than *captured*, so it corrected the gap between redraws and left the pipeline lag untouched. Fixed, it still lost: at 10 fps the velocity comes from samples 100 ms apart and must reach 175 ms forward on a movement that reverses every 500 ms. Kept behind a toggle, off by default. |
| **XNNPACK isn't on for uint8** | **Refuted.** 39 ms on versus 42 ms off. Already active. Set explicitly now only so a future AAR default cannot silently regress it. |
| **Thunder → Lightning** | **Deferred.** Real (≈44 ms → ≈21 ms) but costs accuracy on wrists held overhead — the keypoints Phase 2 established fail first. A product decision, not an optimisation, and one that needs measuring against labelled clips. |

### The assumption that outlived everything

The ~90 ms between the sensor and our code was assumed to contain the camera
framework's own full-frame colour conversion. It was the largest line in the
budget, and deleting that conversion was expected to dent it.

**It did not move by one millisecond.** The conversion had been running on our
own analysis thread the whole time, showing up in the column right next to it.
The ~90 ms is sensor readout, image signal processing and buffer delivery — a
floor no application-side change can reach, and **63% of what now remains**.

### Where it landed

```
age 148ms · cvt 0 · pre 10 · inf 44 · ui 0
thndr · 17.3 in · 17 drawn · 0% coalesced
```

**~175 ms → ~148 ms, and 10.4 fps → 17.3 fps.** The frame rate is the more
valuable half: the counter now sees the athlete **66% more often**.

Remaining budget: **~94 ms camera floor · ~10 ms preprocessing · ~44 ms model.**
The only lever left is the model.

---

## Method notes

Four phases, and the same three habits did most of the work.

**Build the instrument before the fix.** Phase 3 tested four confident
hypotheses, all defensible from reading the code, and killed three. The
instrument cost less than any one of the fixes would have.

**One run is not a measurement.** A 27 ms saving evaporated on a second run — a
cold-start artifact. A 14% threading win dissolved when the sweep ran in reverse.
A first configuration measured 117 ms against a settled 43 ms *despite* eight
warm-up frames. All three would have shipped as facts. Thermal drift is large and
fast on this handset: the same model measured 13 ms and 21 ms sixty seconds apart
as it warmed.

**Know which numbers you are allowed to state.** A plausible figure from the
wrong clock is worse than a blank. A benchmark that omits one stage will point
confidently the wrong way — the isolated A/B said the YUV path was 7 ms
*slower*, because it never charged the old path for the conversion the new one
eliminates.

And one that is specific to this app: **the errors only ever run one way.**
Degraded tracking produces absence, not invention — in every low-light run the
count only went down, never up. That is what makes "at least this much" an honest
thing for the app to say, and what makes every threshold in it permissive by
default.

---

## Verification standing

- **315 JVM unit tests**, lint clean.
- **`parity_check.py` PASS on 925 frames** — the Kotlin and Python engines agree
  frame by frame.
- **On-device counting verified:** a full round with pull-ups skipped scored
  exactly 25, being 10 push-ups plus 15 squats.
- Benchmarks (`PoseDetectorBenchmark`, `YuvPathBenchmark`) run explicitly on a
  connected device, not in CI, so any claim about this pipeline can be re-checked
  in about a minute.

All Phase 3 figures measured on an Oppo Reno5 5G (Snapdragon 765G, Android 13) at
thermal status 0, using MoveNet SinglePose Thunder int8 via TensorFlow Lite 2.16
and CameraX 1.4.1.
