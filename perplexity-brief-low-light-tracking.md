# Cindy Workout — low-light tracking degradation: measured findings and open decisions

**A request for a second opinion. Written for a reader with no prior context on this project.**

---

## 0. What I want from you

A tester reported that a workout stopped counting pull-ups partway through, at sunset. An earlier
plan proposed a design for handling this. Before building it, I reproduced the failure
experimentally against real footage with a known-correct score. **The measurements contradict
several parts of that plan, including a part I proposed myself.**

I want your opinion on the eleven questions in §8 — particularly where you think my conclusions
outrun my evidence. Please distinguish clearly between what you can support with sources and what
is your judgement. Where you cite empirical claims (sensor behaviour, torch output, MoveNet
characteristics), please give sources I can check; I have previously been given fabricated
citations in this project and will verify them.

Please do not propose a redesign of the counting pipeline. It works, it is heavily tested, and
§9 lists constraints that rule out most large changes.

---

## 1. The app

An Android + iOS workout tracker for **Cindy**, a CrossFit benchmark workout: as many rounds as
possible in 20 minutes of *5 pull-ups, 10 push-ups, 15 air squats*. A typical session is 15–20
rounds, so 300–600 reps.

- The athlete props the **phone on a box 2–3 m away** and trains alone. There is no wearable,
  no second person holding the camera, no server, and no account.
- Pose comes from **MoveNet SinglePose Thunder** (256×256 input) running on TFLite, on-device.
  17 COCO keypoints, each with a confidence score. Analysis frames are 480×640.
- A keypoint scoring below **0.30** is treated as unseen.
- The detector crops each frame to a **tracked square region of interest** around where the body
  was last seen, and feeds that crop to the model, so the athlete fills the input rather than
  occupying a few dozen pixels of a tall frame.

**Design rule this project has repeatedly enforced:** be permissive, not exclusionary. Several
past bugs were fixed cameras and thresholds locking out legitimate athletes (a foreshortened
full extension reading 145° against a 158° threshold, etc.). Fixed thresholds have been removed
in favour of ranges learned from the athlete's own movement. A change that makes the app refuse
to count something it currently counts needs very strong justification.

### Three engines in parity

The counting logic exists three times — **Kotlin** (Android, production), **Python** (an offline
harness that runs the same rules over decoded video), and **Swift** (iOS). A parity checker diffs
the Kotlin and Python engines frame by frame over ~925 recorded frames and fails on any
divergence. Anything added to the counting rules must be portable to all three and must be
testable in the offline harness. **A signal that cannot be reproduced in the harness cannot be
regression-tested, and this project does not ship counting changes that cannot be
regression-tested.** This constraint does a lot of work in what follows.

---

## 2. How counting works today, in the parts that matter here

Each frame produces one of two outcomes, and the reason is recorded as a short human-readable
string that doubles as the on-screen hint and the spoken coaching line:

**Rejections meaning "I cannot read your joints":**
`Show both hands`, `Step into frame`, `Arms out of frame`, `Tracking…`, `Show your head`

**Rejections meaning "I can see you fine, you are not in position":**
`Hang from the bar`, `Hang vertically from the bar`, `Lower all the way down`,
`Get your head over the bar`, `Get on the floor`, `Stand up to start`

That distinction is not currently used for anything. It becomes the centre of my proposal.

A rep is booked by a counter that measures how far a joint-angle signal climbs off its trough,
against a band **learned from the athlete's own range** rather than a fixed threshold. Pull-ups
additionally require: both wrists visible, wrists above hips, torso vertical, hands inside a
learned bar zone, head crossing the bar line, and a fresh dead hang since the last rep. Brief
unreadable frames mid-rep are absorbed by a dropout tolerance of 8 frames (~⅓ s at 24 fps).

A voice coach speaks a fault after it has stood for 4 s, and repeats every 12 s while nothing
improves.

**Manual counting already exists:** a `+1` / `−1` control on the camera HUD, a `manualReps`
tally kept separately from auto-counted reps, persisted in the session record, and shown on the
results screen as "Added by hand — N of M".

---

## 3. The incident

A tester reported that **around the tenth round, the app would no longer track his sets** of
pull-ups. The workout was outdoors in the evening. The hypothesis is diminishing light at
sunset.

**There is no recording of that session.** This is user feedback correlated with time of day,
not a diagnosed failure. That is precisely why I ran the experiment below rather than building
against the hypothesis.

---

## 4. The experiment

**Method.** Take a clip whose correct score is known exactly, decode it, apply a light model to
each frame in memory, and run the *production* detector and counting engine over the result.
Nothing is re-encoded, so the only variable is light.

**Clips.**

| clip | content | frames | ground truth | scores today |
|---|---|---|---|---|
| `3aRP4o23HXo` | band-assisted pull-ups, front view, single static shot, 720×1280 | 532 (17.7 s @30fps) | 5 | **5 ✓** |
| `EgIMk-PZwo0` | knee push-ups, three-quarter view, static camera | 1815 (60.6 s) | 12 | **12 ✓** |

**Two light models**, because a phone does not sit still while the sun goes down:

- **`uncompensated`** — `out = frame × gain`. The exposure is already at its limit, so less light
  simply means a darker picture. The late stage of the failure, and also what happens *at any
  time* when auto-exposure meters on a bright background and leaves the subject underexposed.
- **`iso`** — `out = frame × gain × ISO + noise(σ × ISO)`, `ISO = min(1/gain, 12)`, σ = 2 counts.
  What the camera does *first*: raise gain to hold brightness up, amplifying read noise with it.
  The picture stays bright and gets dirty.

**Measured per run:** reps counted, mean frame luma (Rec. 601), mean confidence of the four torso
keypoints, and the share of frames rejected for *unreadable joints* vs *posture*.

---

## 5. Results

### 5.1 Progressive darkening, pull-ups (ground truth 5)

| light | mean luma | unreadable-joint rejections | postural rejections | **reps** |
|---|---|---|---|---|
| full | 116.0 | 10.3% | 53.4% | **5** ✓ |
| 0.11× | 12.3 | 23.5% | 43.6% | **5** ✓ |
| 0.09× | 9.9 | 42.9% | 32.9% | **5** ✓ |
| 0.085× | 9.4 | 49.8% | 28.2% | **3** ✗ |
| 0.08× | 8.8 | 57.9% | 23.9% | **2** ✗ |
| 0.07× | 7.6 | 78.2% | 19.5% | **0** ✗ |

**The app does not stop at a cliff. It bleeds reps: 5, 3, 2, 1, 0** — with no alarm, and nothing
in the saved record to say the score is unreliable. The tester noticed at zero. The data says he
was probably being under-counted for some minutes before that, and that a wrong score was filed
as a real result.

The dominant rejection through the whole collapse is **`Show both hands`**. Wrists held overhead
are small, fast, motion-blurred and often silhouetted against a bright ceiling or sky, so they
are the first keypoints lost.

### 5.2 The same sweep on push-ups (ground truth 12)

| light | mean luma | reps |
|---|---|---|
| full | 77.5 | 12 ✓ |
| 0.10× | 7.5 | 12 ✓ |
| 0.07× | 5.2 | 12 ✓ |
| 0.05× | 3.6 | 11 |
| 0.03× | 2.1 | 1 ✗ |

**Push-ups survive roughly 16× darker than pull-ups.** Push-ups need shoulder–elbow–wrist with
the arms low, large and central in frame; pull-ups need wrists overhead. The tester lost
*pull-ups* specifically, which is exactly what this predicts.

### 5.3 Frame brightness does not separate working from broken

I had proposed measuring scene light from the **mean luma of the analysis frame**, on the
grounds that it is lens-correct, needs no sensor, and is reproducible in the offline harness
(unlike a lux reading). The ISO model killed that idea:

| condition | mean luma | reps |
|---|---|---|
| dark, uncompensated (0.10×) | **11.2** | **5** ✓ |
| ISO-compensated (0.05×) | **69.8** | **0** ✗ |

**Counting perfectly at luma 11; completely dead at luma 70.** Any threshold low enough to avoid
false alarms in the first case can never fire in the second. The distributions overlap by a
factor of six in the wrong direction. My own proposal fails on its own evidence.

### 5.4 The unreadable-rejection rate *does* separate, and it leads the rep loss

Across both light models, the share of frames rejected for unreadable joints rises monotonically
and crosses roughly **45–50% exactly where reps begin to disappear** — while sitting at 10–23%
in healthy conditions, and reaching 23% and 43% *while the count is still perfect*. That gap is
the warning window.

Critically, the **postural** rejection rate moves the *opposite* way (53% → 19%), because frames
that would have been refused for posture are now refused earlier for unreadability. An
undifferentiated "rejection rate" would run ~64% healthy to ~98% dead and separate far more
weakly. The split is what makes the signal work — and it also means **normal rest and transitions
between movements do not trip it**, because those produce postural rejections.

### 5.5 The biggest finding: two distinct regimes, one of which is free to fix

MoveNet does not normalise input brightness. So I tested whether its failure under darkening is
*informational* (the detail is genuinely gone) or merely *representational* (the pixel values are
small). I applied software gain to the analysis frame before inference — adaptive, lifting the
frame's mean luma to a target of 110, clamped to ≤16× and never below 1×.

**Underexposed regime — fully recovered:**

| light | reps before | reps after | unreadable before → after |
|---|---|---|---|
| full (regression check) | 5 ✓ | **5 ✓** | 10.3% → 10.3% |
| 0.09× | 5 | **5** | 42.9% → 10.5% |
| 0.07× | **0** ✗ | **5 ✓** | 78.2% → 12.8% |
| 0.05× | **0** ✗ | **5 ✓** | — → 13.0% |
| 0.03× | **0** ✗ | **5 ✓** | — → 12.0% |

Counting is restored at every light level that previously failed, the usable range extends **at
least 3.3×** further into the dark (0.10× → 0.03×), and **full light is completely unaffected**
because the adaptive gain clamps to 1×.

**Noise-limited regime — no help at all:**

| light (ISO model) | luma before → after | reps before | reps after |
|---|---|---|---|
| 0.08× | 111 → 111 | 5 ✓ | 5 ✓ |
| 0.05× | 69.8 → 109.3 | **0** ✗ | **0** ✗ |
| 0.03× | 42.6 → 108.5 | **0** ✗ | **0** ✗ |

Brightening a noisy frame amplifies the noise with the signal. At 0.03× it is marginally *worse*
(94% → 100% unreadable).

**So there are two failure modes that look identical to the user and need opposite responses:**

1. **Underexposed** — the camera has not compensated, or has metered on a bright background and
   left the subject dark. Costs nothing to fix in software, and the ROI crop is already centred
   on the athlete, so normalising *within the crop* is immune to background metering.
2. **Noise-limited** — the camera has already raised gain to its limit. The information is gone.
   Only real light or manual counting helps.

### 5.6 No phantom reps, ever

Across every run at every light level, the count only ever went **down**: 5,5,5,3,2,1,0 and
12,11,12,12,11,1. Degraded pose never produced a rep that did not happen. The existing gates
already refuse unreadable frames, so darkness produces *absence*, not *error*.

---

## 6. What the earlier plan proposed, and where the data now contradicts it

The prior plan (discussed with you in an earlier chat) proposed: a `TrackingHealth` state machine
gating rep booking; an `AmbientLightMonitor` reading `Sensor.TYPE_LIGHT` with lux thresholds and
hysteresis; a torch offer; a gyro camera-move guard; a manual mode; and a persisted
`TrackingEvent` list on the session record.

**Where I think it is right:** the tracking-health idea itself (§2 of that plan listed "fraction
of frames with a usable pose" first, which is the signal that actually works); keeping the
workout timer running when tracking fails; never enabling the torch silently; and treating manual
mode as a first-class fallback rather than a failure screen.

**Where the data contradicts it:**

1. **Gating `mayBook` on tracking health protects against a failure that does not occur** (§5.6).
   Meanwhile the damage that *does* occur — a rep the camera never saw — cannot be fixed by any
   gate, because you cannot count what you cannot see. Adding a global veto on top of gates that
   already refuse can only remove reps that currently count, which is the lockout pattern this
   project has repeatedly had to undo.
2. **`Sensor.TYPE_LIGHT` is the wrong instrument.** It sits beside the *front* camera. With the
   phone on a box using the rear lens, it faces away from the scene and reads the wall behind the
   phone. Many devices lack it. And it cannot appear in the offline harness, so a lux-driven rule
   could never be regression-tested (§1).
3. **Frame luma is also the wrong instrument** (§5.3) — my idea, killed by my own measurement.
4. **The plan treats low light as one condition.** It is two, with opposite remedies (§5.5), and
   the plan's headline framing — "detect degraded light, offer torch, fall back to manual" —
   skips the free fix entirely.
5. **The plan frames the failure as tracking *stopping*.** It is tracking *quietly under-counting*
   first. That changes the priority from "fail over gracefully" to "do not silently file a wrong
   score".

---

## 7. What I propose to build

**A. Normalise brightness inside the tracked crop before inference.** Adaptive gain to a target
mean, clamped, never below 1×. Free, no permissions, no battery cost, no effect at full light,
≥3.3× more usable range. Reproducible in all three engines and in the offline harness, so it is
regression-testable.

**B. A rolling unreadable-rejection monitor in the shared engine.** Consumes the rejection
reasons the engine already produces, split unreadable vs postural (§2). Emits a health state.
Ported to Kotlin/Python/Swift with a parity trace.

**C. Honest messaging.** Today a dark stall tells the athlete `Show both hands` and then
`Step into frame` — blaming them for something they cannot fix by moving. Replace with a warning
while the count is still correct, escalating when reps are being lost.

**D. Torch offered only in the noise-limited regime** — where software cannot help — never
silently, and only after sustained degradation. **See question 4: I am not convinced this is
worth building at all.**

**E. Manual failover surfaced at the moment tracking dies.** The mechanism already exists; the
gap is discoverability.

**F. Mark degraded sessions honestly** so a known-unreliable score is not filed as a personal
record without a note.

**G. Gyro camera-move guard.** A bumped phone invalidates the learned bar position, which is
recorded in frame pixels. The engine already has a `recalibrate()` that resets exactly the right
state; nothing currently calls it on movement.

---

## 8. Questions

1. **Is the unreadable-vs-postural rejection rate the right detector**, or is there a better
   cheap on-device signal for "the pose stream has become unreliable"? I considered and did not
   test: temporal keypoint jitter, per-keypoint confidence trend, image sharpness (Laplacian
   variance), and optical-flow residual. Which would you expect to add information over the
   rejection rate, and why?

2. **Capture metadata as the light signal.** `Camera2Interop` / `Camera2CameraInfo` can expose
   `SENSOR_SENSITIVITY` (ISO) and `SENSOR_EXPOSURE_TIME` from the actual imaging lens. That is
   the one light measurement my ISO experiment would *not* have defeated, since it reads the gain
   the camera is applying. `camera-camera2` is already a dependency, so this costs nothing.
   **How reliable and comparable are these values across Android vendors?** Are the ranges
   device-specific enough that only *relative* change within a session is trustworthy? Note it
   cannot be reproduced in the offline harness, so it could only ever be advisory, never a gate.

3. **Absolute vs session-relative thresholds.** My healthy baseline was 10.3% unreadable on one
   clip, but the push-up clip sat near 46% at full light because it contains footage with no
   athlete in it. That argues for detecting a *rise above the session's own established baseline*
   rather than a fixed percentage — which also matches this project's existing idiom of learning
   the athlete's range instead of fixing thresholds. Do you agree, and how would you handle a
   session that is already degraded when it starts?

4. **Does a phone torch actually do anything at 2–3 m?** Inverse-square suggests a typical
   phone LED gives very little illuminance on a subject three metres away, against an ambient
   level that is already failing. **What illuminance should I expect at 2–3 m from a modern phone
   torch, with sources?** If it is negligible, offering it is a placebo that costs battery, heat
   and trust, and I would rather tell the athlete to turn on a room light or move the phone
   closer. I would like this settled with numbers, not intuition.

5. **Wording, given irreducible ambiguity.** The app cannot distinguish "too dark to see you"
   from "you walked out of frame" — both produce the same missing keypoints. What should it say
   that is honest about the uncertainty, actionable, and not alarming mid-workout? Current
   candidate: *"Losing track of you — more light usually helps"*, escalating to *"Not counting
   reliably — add light or tap +1"*.

6. **Should a degraded session be allowed to set a personal record?** The session is real work;
   the *score* may be wrong and is known to be under, never over (§5.6). Options: flag but allow;
   flag and exclude from PRs/benchmarks; or two tiers — allow through the warning band, exclude
   once the monitor crossed into the rep-losing band. There is precedent in the codebase for
   excluding non-comparable sessions from benchmarks.

7. **Is my refusal to gate `mayBook` correct?** I argue the gate protects against a
   non-occurring failure and risks lockout. Is there a low-light regime you would expect to
   produce *phantom* reps that my two clips and two light models did not reach — for example
   keypoints that are confidently wrong rather than merely absent?

8. **Is my simulation trustworthy enough to design against?** It models gain and Gaussian read
   noise. It does **not** model motion blur from longer exposures, ISP temporal denoising (which
   smears moving limbs), rolling shutter, or chroma subsampling artefacts. I suspect all of these
   hit fast-moving wrists *harder* than my simulation does, meaning real-world failure arrives at
   *higher* light levels than my numbers suggest. **How would you model low-light motion blur
   and ISP denoising realistically?** Is there a standard approach for synthesising low-light
   video degradation for vision benchmarks?

9. **Is the brightness normalisation in §5.5 / §7A safe in ways I have not tested?** Specific
   worries: clipping highlights on a backlit athlete and losing the silhouette edge; amplifying
   compression artefacts; interacting badly with the crop-follow logic when the crop moves
   between a bright and dark part of the scene. Would per-crop histogram equalisation or CLAHE be
   meaningfully better than a simple mean-targeting gain, and is that worth the cost on a phone
   at 24 fps?

10. **Is there published characterisation of MoveNet's behaviour in low light or under noise**
    that I should know about — particularly whether wrist and ankle keypoints degrade first, which
    is what I observed? Sources please.

11. **Is there a fundamentally different approach I am not considering?** Constraints in §9.
    I am specifically interested in whether locking or biasing exposure via Camera2 (accepting
    motion blur in exchange for signal) would be better or worse than software normalisation, and
    how that trade lands for a fast movement like a pull-up.

---

## 9. Constraints and non-goals

- **minSdk 26** (Android 8.0). Compile/target SDK 35. Anything requiring API 31+ needs a
  fallback. CameraX 1.4.1, with `camera-camera2` already present.
- **Three engines in parity.** Counting-rule changes must be portable to Kotlin, Python and Swift
  and testable in the offline video harness. Platform-only signals (sensors, capture metadata)
  can be advisory but can never gate counting.
- **No new heavy dependencies.** No runtime blur, no Compose, no Material — the UI is hand-styled
  XML with custom Views, deliberately.
- **On-device only.** No server, no account, no upload. Workout video and pose data are personal
  data and stay on the phone.
- **Permissive, not exclusionary.** A change that stops the app counting something it counts
  today needs strong justification.
- **The workout timer must keep running** when tracking fails. The athlete may well be mid-set.
- **Not in scope:** competition-grade verification or anti-cheat; distinguishing assisted from
  strict movements by force (impossible from one RGB view); anything requiring a second device.
- **iOS is deliberately a generation behind** the Android engine and is not the priority here.

---

## Appendix: reproducing this

The sweep decodes a fixture, applies the light model per frame in memory, and runs the production
`PoseDetector` + `WorkoutEngine` from the Python parity port. Adaptive normalisation lifts each
frame's mean luma to 110, clamped to `[1×, 16×]`.

Caveats on the evidence, stated plainly:

- **Two clips, one per movement.** Neither is outdoor evening footage; both are well-lit clips
  darkened synthetically.
- **Neither clip is a real Cindy session.** The pull-up clip is 17.7 s with 5 reps; the reported
  failure was ~10 rounds into a 20-minute workout, where fatigue also degrades form.
- **The tested failure is synthetic.** No recording of the actual incident exists, so this
  reproduces the *hypothesis* faithfully — it does not prove the tester's failure had this cause.
  The strongest corroboration is that pull-ups fail ~16× sooner than push-ups, and the tester
  lost pull-ups specifically.
- **No motion blur or ISP denoising modelled** (question 8).
