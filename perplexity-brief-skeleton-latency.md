# Cindy Workout — the skeleton overlay lags the body: a reasoned diagnosis with no measurements yet

**A request for a second opinion. Written for a reader with no prior context on this project.**

---

## 0. What I want from you, and the one thing I need you not to do

A tester reports that the pose skeleton drawn over the camera preview is **"substantially
delayed, to the point that it is not in real time."** That is the entire report. There is no
number, no recording, and no profile.

I have read the pipeline end to end and I have a ranked theory of where the time goes (§3, §5).
**I have measured none of it.** There is no emulator and no `adb` device on this machine, the app
has no frame-rate counter, and the only timing instrument that exists anywhere in the codebase is
a single `lastInferenceMs` field. Everything in §3 that carries a number is either read off a
file header or is arithmetic on code I have read — never a stopwatch on a phone.

So the thing I need from you is **not** a plan. It is calibration on the numbers, and specifically:

- Where you can cite a benchmark or vendor doc, please do, **with a link I can open**. I have
  previously been handed fabricated citations in this project and I will check them.
- Where you are estimating, say so in the same sentence. An unmarked guess about MoveNet
  inference time on mid-range Android is worse than no answer, because I will build against it.
- If the honest answer to "how fast is this on a phone" is "it varies by 5× across the Android
  fleet and you must measure," **say that** rather than picking a number to be helpful. Telling
  me my §6 question is unanswerable without a device is a useful answer.

One hard-won piece of context so you don't repeat the advice everyone gives: **the bundled models
are uint8-quantized, which I verified by parsing the flatbuffers** (§2.2). The reflex answer to
"TFLite pose is slow" is "add the GPU delegate," and I believe that is wrong for quantized
MoveNet. §6 Q3 asks you to confirm or destroy that belief.

Please do not propose replacing the counting engine. It works, it is heavily tested, and §7 lists
constraints that rule out most large changes.

---

## 1. The app

An Android + iOS workout tracker for **Cindy**, a CrossFit benchmark: as many rounds as possible
in 20 minutes of *5 pull-ups, 10 push-ups, 15 air squats*. A session is typically 15–20 rounds.

- The athlete props the **phone on a box 2–3 m away** and trains alone. No wearable, no second
  person, no server, no account.
- Pose is **MoveNet SinglePose Thunder** on TFLite, on-device, 17 COCO keypoints with confidences.
- A live **skeleton overlay** is drawn over the camera preview so the athlete can see that the app
  can see them. This overlay is the subject of this document. **It is a feedback device, not part
  of scoring** — that distinction turns out to matter a lot (§5.2).
- Counting happens in a separate engine fed the same keypoints.

### 1.1 Three engines in parity — the constraint that shapes everything

The counting logic exists three times: **Kotlin** (Android, production), **Python** (an offline
harness that runs the same rules over decoded video), and **Swift** (iOS). A parity checker diffs
Kotlin against Python frame by frame over ~925 recorded frames and fails on any divergence.

**Anything that changes the numbers the counting engine sees must be portable to all three and
regression-tested in the harness.** Anything that only changes what is *drawn* is free of that
constraint. This cleanly splits the fixes below into "cheap" and "expensive," and it is why I
have ordered them the way I have.

---

## 2. The pipeline, as built

### 2.1 Capture and binding

```
CameraX 1.4.1
├── Preview            → PreviewView  (no ResolutionSelector; default path)
├── ImageAnalysis      → 480×640 target, FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER
│                        STRATEGY_KEEP_ONLY_LATEST
│                        OUTPUT_IMAGE_FORMAT_RGBA_8888
│                        analyzer on a single-thread Executor
└── VideoCapture       → + an OverlayEffect targeting CameraEffect.VIDEO_CAPTURE **only**
```

**The camera picture is not what lags.** The `OverlayEffect` that burns a HUD into the recording
targets `VIDEO_CAPTURE` exclusively — deliberately, with a comment saying the preview already has
its own overlay view. So `PreviewView` is a direct surface path with a frame or two of latency.
**Only the skeleton trails the body.** I am reasonably confident of this from the binding code,
and it is the first thing I would confirm with a measurement.

Binding is attempted in three descending tiers (overlay effect + recording, plain recording,
counting only), because preview + analysis + recording + effect is more than some cameras will
bind at once.

### 2.2 The models are uint8-quantized — verified, not assumed

Nothing in the repo records the dtype. The project's Python venv has only numpy and
opencv-python-headless, no tflite. So I wrote a ~40-line minimal TFLite flatbuffer parser and read
the tensor tables directly:

| asset | bytes | input tensor | dtype | shape | output |
|---|---|---|---|---|---|
| `movenet_thunder.tflite` | 7,126,768 | `serving_default_input:0` | **UINT8** | `[1,256,256,3]` | FLOAT32 `[1,1,17,3]` |
| `movenet_lightning.tflite` | 2,894,840 | `serving_default_input:0` | **UINT8** | `[1,192,192,3]` | FLOAT32 `[1,1,17,3]` |

333 tensors each. Both are the **int8 quantized** TF Hub variants, not float16. The interpreter is
constructed with nothing but `numThreads = 4` — **no delegate of any kind**, and the only
dependency is `org.tensorflow:tensorflow-lite:2.16.1` (no `-gpu`, no `-gpu-api`, no
`-nnapi`, no Play-services LiteRT).

The detector reads the input square size off the model at load, so Lightning (192) and Thunder
(256) both drop in. A long-press on the flip button swaps between them at runtime; the swap is
applied at the top of the next analysis callback.

### 2.3 What happens per analysed frame

The analysis callback is **strictly serial**: an `AtomicBoolean` guard refuses a new frame while
the previous one is still in flight, and `STRATEGY_KEEP_ONLY_LATEST` drops the rest. So the loop
runs at whatever rate one full pass completes, and the displayed pose's age is the full pass plus
half a frame interval.

One pass, in order:

| # | stage | what it costs, by inspection |
|---|---|---|
| 1 | `ImageProxy.toBitmap()` | allocates a 480×640 ARGB_8888 — **~1.2 MB** |
| 2 | rotate + mirror via `Bitmap.createBitmap(raw, 0, 0, w, h, m, true)` | allocates a **second** full-frame bitmap, **~1.2 MB**. `filter = true` on what is a pure 90° rotation, so it bilinearly resamples for no geometric reason — and softens the very picture the model is about to read |
| 3 | draw the tracked ROI crop into a reused 256² bitmap via `Canvas` + `Matrix` | cheap, reused surface |
| 4 | `square.getPixels()` | **65,536** ints into a reused `IntArray` |
| 5 | `normalisingGain()` | a **full second pass** over all 65,536 pixels |
| 6 | fill the input buffer | **196,608** individual `ByteBuffer.put(byte)` calls, each going through a `Float` conversion even when gain is 1.0 |
| 7 | `interpreter.run()` | the dominant term, and the one I cannot estimate honestly (§6 Q1) |
| 8 | build 17 `Keypoint`s, update the ROI | negligible |
| 9 | `ui.post { … }` | hands the frame to the main thread |

Steps 1 and 2 together churn **~2.4 MB per frame**. At even 10 fps that is ~24 MB/s of bitmap
allocation on the analysis thread, which I would expect to show up as GC pressure on exactly the
thread that must not stall.

### 2.4 The ROI crop, and why step 5 exists

The detector does not feed whole frames to the model. It crops each frame to a **square region of
interest** around where the body was last seen, so the athlete fills the model's input rather than
occupying a few dozen pixels of a tall frame. Margin 1.45× the body box, never below 25% of the
frame, followed at 0.35 per frame to damp jitter, dropped after 5 consecutive poor frames.

`normalisingGain()` (step 5) is **not incidental** — it is a hard-won low-light feature. MoveNet
does not normalise its own input, so an underexposed crop fails for a reason that is
representational rather than informational. Measuring mean luma *inside the crop* and lifting it
toward a target of 110 (clamped to `[1×, 16×]`, so well-exposed footage passes through untouched)
was measured to extend the usable light range at least 3.3× and to fix a real miscount. It is
ported to the Python engine and covered by parity.

**So step 5 cannot simply be deleted to save time, and any change to how it samples must be
mirrored in the Python port or the parity check will drift.** This is the single most important
thing to understand before suggesting I trim the per-pixel work.

### 2.5 What happens on the main thread

Every analysed frame posts a block that does three things: hands the keypoints to `OverlayView`,
runs `apply(snapshot)` (sets a half-dozen text views, a progress bar, a status dot, accessibility
strings, a voice-coaching call and a position-coaching call — **including TTS**), and pushes the
same numbers into the recording overlay. A separate 200 ms ticker runs the workout clock on the
same thread.

**`ui.post` has no coalescing and no back-pressure.** The analysis thread never waits for the main
thread. If the main thread falls behind for any reason, those runnables queue without bound and
the skeleton's lag grows monotonically and never recovers.

### 2.6 What the overlay does with a pose

`OverlayView.setPose()` stores the keypoints and calls `postInvalidateOnAnimation()`. It draws
them at the coordinates they arrived with, recomputing the same FILL_CENTER mapping `PreviewView`
applies so the skeleton lands on the body.

**There is no filtering, no smoothing, no interpolation and no extrapolation anywhere.** The
overlay is a direct, unsmoothed render of the last completed inference, redrawn once per
inference. Whatever the pipeline latency is, the skeleton is exactly that far behind — and at the
pipeline's own frame rate, so if inference is running at 7 fps, the skeleton also *moves* at
7 fps.

---

## 3. My theory, ranked, and my confidence in each part

| # | claim | confidence |
|---|---|---|
| A | The preview is live; only the skeleton trails | **high** — from the effect targeting, unmeasured |
| B | Inference dominates the loop | **medium** — see §6 Q1; I have no number for Thunder int8 on real hardware |
| C | Steps 1–6 add a non-trivial constant on top | **medium-high** — the allocation and loop counts are facts, their cost in ms is not |
| D | Drawing once per inference makes it *look* worse than it measures | **high** — 7 fps motion reads as broken even when the lag is modest |
| E | The unbounded `ui.post` queue could be turning a fixed lag into a growing one | **low-medium, and untested** — but it fits "not in real time" better than a steady 200 ms would |

**I consider D the most under-appreciated item and A+E the two that a single measurement would
settle.** I would rather be told my ranking is wrong than be handed a fix list.

---

## 4. What I have not ruled out

Stated plainly, because these are the holes a second opinion should probe:

- **I have never seen the app run on this tester's phone**, or any phone, in this session. I do
  not know the device, its SoC, its thermal state, or whether recording was active at the time.
- **Recording may have been on.** That binds a `VideoCapture` use case plus an `OverlayEffect`
  surface processor. I have assumed that does not touch preview or analysis latency because the
  effect targets `VIDEO_CAPTURE` only, but I have not verified that binding a third use case
  leaves the analysis frame rate alone.
- **I do not know the actual analysis frame rate.** Nothing measures it. `480×640` is a *target*
  with a closest-higher-then-lower fallback, so the real resolution is device-dependent.
- **Thermal throttling.** A 20-minute session with the screen on, camera open, TTS running and
  possibly recording is a sustained load. Lag that appears partway through a workout is a
  different problem from lag that is there at second one, and the report does not distinguish.
- **`armeabi-v7a` is still in the ABI list.** If any tester is on a 32-bit build the arithmetic
  changes considerably.

---

## 5. What I am considering building, in order

### 5.1 Instrument it first (no behaviour change)

The debug readout shows `lastInferenceMs` and nothing else — no end-to-end latency, no frame rate,
no main-thread queue depth. `ImageProxy.imageInfo.timestamp` should give true glass-to-overlay
latency for about ten lines of code. **This is the only item I am sure is worth doing**, because
it discriminates between B, C and E, which want different fixes. §6 Q7 asks about a real trap here.

### 5.2 Make the overlay predict rather than report (display-only, zero counting risk)

Keep the last two poses with their capture timestamps; at draw time, advance each joint by its
velocity × (now − captureTime); redraw every vsync instead of once per inference.

The appeal is that it attacks **perceived** lag directly and it is **outside the parity
constraint entirely** — the counting engine keeps scoring the true, un-extrapolated keypoints, and
the Python and Swift engines never see it. A display-only change in an app where the display is a
feedback device and the engine is the scorer.

The obvious hazard is overshoot at direction changes, and a pull-up has a hard one at the top of
every rep. §6 Q5 is the question I most want answered.

### 5.3 Cut the per-frame fat (touches the counting path)

Fold the rotation and mirror into the detector's existing crop matrix so step 2's whole bitmap
disappears; replace `getPixels` + 196 k `put` calls with a reused `ByteArray` and one bulk put.

This changes the pixels the model sees (if only by removing a spurious bilinear resample), so it
needs the full parity harness re-run and a fixture check. Worth doing only if §5.1 says steps 1–6
are actually material.

### 5.4 Auto-fall-back Thunder → Lightning

The swap already exists behind a long-press. Driving it off a rolling median of inference time
would be straightforward. But it costs accuracy on footage that already loses wrists — measured
low-light work on this project showed **wrists held overhead are the first keypoints to go**, and
pull-ups fail roughly 16× sooner than push-ups because of it. So this is a measured fallback, not
a new default. §6 Q2 asks what the real speed/accuracy trade is.

### 5.5 Explicitly *not* first: the GPU delegate

See §6 Q3. I believe this is the wrong tool for uint8 models and I want to be argued with.

---

## 6. Questions

1. **What inference time should I actually expect for MoveNet SinglePose Thunder int8 (256²) and
   Lightning int8 (192²) under TFLite 2.16 on arm64 Android CPU?** Give a range across tiers —
   flagship, mid-range, and a 5-year-old budget device — and **cite benchmarks rather than
   estimating**. If the honest answer is that the spread is too wide to design against, say so;
   that is a valid and useful answer and it changes my plan.

2. **What is the real Thunder → Lightning trade?** I can find the accuracy delta in TF Hub's model
   cards, but I want the *latency* ratio on CPU, and specifically whether the speedup is closer to
   the pixel ratio (256²/192² ≈ 1.8×) or to the FLOP ratio (which I believe is larger). And: does
   Lightning degrade disproportionately on the case that matters here — **wrists held overhead,
   small, fast and often motion-blurred or silhouetted**?

3. **Is my rejection of the GPU delegate correct?** My reasoning: the TFLite GPU delegate supports
   quantized models only via an experimental dequantize path
   (`setQuantizedModelsAllowed`), it converts to fp16 internally, and on many devices it is
   *slower* than the int8 CPU path — while a proper GPU story would mean shipping the **float16**
   MoveNet builds instead (Thunder fp16 ≈ 12.6 MB — a figure I am quoting from memory and have
   *not* verified, unlike the int8 sizes in §2.2), which is a numerically different model and
   forces a full parity re-run. Is that accurate as of 2026? Under what circumstances would you
   expect GPU to win on a quantized MoveNet anyway?

4. **What is the state of TFLite CPU acceleration for uint8 in 2026, and am I leaving free speed
   on the table?** Specifically: (a) is XNNPACK's QU8/QS8 path enabled by default in the
   `tensorflow-lite:2.16.1` Android AAR, or does it need `setUseXNNPACK(true)` or a build flag?
   (b) `numThreads = 4` is set blindly — on big.LITTLE, does TFLite pin to big cores, or can 4
   threads land on little cores and lose to 2? (c) NNAPI was deprecated in Android 15 — what
   actually replaces it for a small app: LiteRT via Play services, vendor delegates (Qualcomm QNN,
   MediaTek Neuron), something else? Is migrating off `org.tensorflow:tensorflow-lite` to **LiteRT**
   worth it for a model this size, and what does it cost me at **minSdk 26**?

5. **The predictive overlay (§5.2) — is this standard practice, and what is the right filter?**
   Constant-velocity extrapolation is the naive version. I know the **One Euro filter** is the
   usual recommendation for interactive pose, but One Euro is a *smoother* — it removes jitter at
   the cost of adding lag, which is the opposite of my problem. Questions: is there an established
   predictive variant, or is the standard answer an alpha-beta / constant-velocity Kalman
   predictor? **How do practitioners stop it overshooting at a hard direction reversal** — which
   for a pull-up happens at the top of every single rep, at the exact moment the athlete is looking
   at the screen to see whether the rep counted? Is there prior art in AR/VR late-stage reprojection
   or in game netcode client-side prediction that transfers cleanly to 17 independent 2D keypoints
   with per-keypoint confidence?

6. **Is there a perceptual literature on how much overlay lag is actually tolerable here?** I do
   not need "under 100 ms" folklore. I want to know whether the threshold for *"a skeleton drawn
   on my own moving body looks wrong"* is meaningfully different from the well-studied thresholds
   for touch latency or AR registration, and whether **smoothness (redraw rate) or latency**
   dominates the perception when the two trade off — because §5.2 improves both and §5.3/§5.4
   improve only latency.

7. **A measurement trap I want to avoid: what clock is `ImageProxy.imageInfo.timestamp` actually
   on?** I intend to subtract it from `SystemClock.elapsedRealtimeNanos()` to get glass-to-overlay
   latency. But Camera2's `SENSOR_INFO_TIMESTAMP_SOURCE` can be `UNKNOWN` (monotonic,
   `CLOCK_MONOTONIC`, i.e. **not** counting suspend) or `REALTIME` (`CLOCK_BOOTTIME`), and I
   believe CameraX passes the sensor timestamp through unchanged. On a device reporting `UNKNOWN`,
   subtracting from `elapsedRealtimeNanos` would give a wrong and possibly wildly wrong answer.
   **How do I do this correctly and portably at minSdk 26?** Is there a standard way to detect the
   source and convert, and is there a sanctioned way to measure end-to-end camera latency on
   Android that I should use instead of rolling my own?

8. **Is the serial `AtomicBoolean` + `KEEP_ONLY_LATEST` structure costing me throughput?** It
   guarantees the freshest frame and bounds memory, which I like. But it also means the CPU sits
   idle during every non-inference stage and vice versa. Would a two-stage pipeline — preprocess
   frame *n+1* while the interpreter runs on *n* — be a meaningful win, or does contention on a
   phone's memory bandwidth and the interpreter's own threading eat the gain? Note the TFLite
   `Interpreter` is not thread-safe and would have to stay on one thread.

9. **Is the unbounded `ui.post` queue (§2.5, theory E) a real risk or am I inventing it?** If
   real, what is the idiomatic Android fix — a volatile latest-value field with a single
   coalescing runnable, `Choreographer`-driven pulls, something else? And is doing TTS calls and a
   dozen view mutations on the main thread at analysis rate a plausible way to saturate it, or is
   that far too little work to matter?

10. **Is there a cheaper path from `ImageProxy` to model input than the one in §2.3?** I currently
    request `OUTPUT_IMAGE_FORMAT_RGBA_8888` and let CameraX do the YUV→RGBA conversion, then do a
    full-frame rotate, then a crop-and-scale, then a per-pixel copy into a `ByteBuffer`. Since I
    only ever need **one 256² square crop**, converting the whole frame seems wasteful. Would
    taking `YUV_420_888` and converting only the crop region be faster in practice, or does
    CameraX's RGBA conversion already run somewhere I cannot beat from Java? Is there a sanctioned
    zero-copy or GPU-assisted preprocessing path for TFLite vision on Android that works at
    minSdk 26?

11. **Should I be using MediaPipe Pose Landmarker instead of raw MoveNet on TFLite?** It has a
    LIVE_STREAM mode, GPU delegation, and built-in landmark smoothing — i.e. it solves several of
    my problems as a product rather than as things I hand-roll. Against that: it is a different
    model with different keypoints, it would break three-engine parity, and this project's
    counting rules and learned ranges are tuned against MoveNet's COCO-17 output. **Is the latency
    win large enough to be worth that, or is this a trap?** I am genuinely undecided and would
    rather hear "no, and here is why" than a migration guide.

12. **Is there a fundamentally different framing I am missing?** One I considered and rejected:
    deliberately *delaying the preview* to match the skeleton, so the two are consistent. That
    would require rendering camera frames myself instead of using `PreviewView`, and it makes the
    *picture* late to fix the *overlay* being late, which seems obviously wrong for an app where
    the athlete is using the preview to position themselves. Am I right to reject it? Is there a
    third option — for instance, drawing something that is honest about its own uncertainty rather
    than a crisp skeleton in the wrong place?

---

## 7. Constraints and non-goals

- **minSdk 26** (Android 8.0), compile/target SDK 35, ABIs `arm64-v8a` + `armeabi-v7a`. Anything
  needing API 31+ requires a fallback path.
- **CameraX 1.4.1** with `camera-camera2`, `camera-video`, `camera-effects` already present.
  **TFLite 2.16.1, CPU only, no delegate artifacts in the build.**
- **Three engines in parity** (§1.1). Changes to what the *counting engine* sees must be portable
  to Kotlin, Python and Swift and regression-tested in the offline harness. **Changes to what is
  merely *drawn* are exempt** — this is the main lever I have.
- **The analysis frame must not move.** 480×640 with the current use cases is a settled decision
  from an earlier interface milestone; narrowing the counter's field of view was explicitly
  rejected because the hardest footage already loses wrists.
- **The low-light normalisation in §2.4 must not regress.** It was established experimentally and
  is parity-covered.
- **Permissive, not exclusionary.** This project has repeatedly had to undo thresholds that locked
  out legitimate athletes. A latency fix that costs keypoint accuracy is a real trade, not a free
  win.
- **No new heavy dependencies.** No Compose, no Material, no runtime blur — the UI is hand-styled
  XML with custom Views, deliberately.
- **On-device only.** No server, no account, no upload. Workout video and pose data are personal
  data and stay on the phone.
- **iOS is deliberately a generation behind** the Android engine and is not the priority here.

---

## Appendix: how to read the evidence in this document

| claim type | how it was established | trust it? |
|---|---|---|
| Model dtypes, shapes, sizes (§2.2) | flatbuffer parsed directly from the assets | **yes, verified** |
| Binding structure, effect targets, backpressure (§2.1) | read from source | **yes** |
| Allocation counts, loop iteration counts (§2.3) | arithmetic on source that was read | **yes, as counts** |
| Any of those counts expressed in **milliseconds** | — | **no. Not measured.** |
| Inference time, frame rate, end-to-end latency | — | **no. Nothing measures these.** |
| "The preview is live, only the skeleton lags" (§3 A) | inferred from effect targeting | **plausible, unconfirmed** |
| The tester's actual device, thermal state, and whether recording was on | — | **unknown** (§4) |

The previous brief from this project on low-light tracking carried measurements from a repeatable
offline harness. **This one does not, and nothing here should be cited back to me as though it
did.** Where a question in §6 can only be answered with a device in hand, telling me so is the
answer I want.
