# Cindy Tracker

An Android app that counts a **Cindy** workout from the phone camera:

> AMRAP 20 minutes — 5 pull-ups, 10 push-ups, 15 air squats.

Everything runs on-device. No network, no accounts, no cloud inference; the camera stream
never leaves the phone.

## How it works

```
CameraX (RGBA_8888, KEEP_ONLY_LATEST)
  └─ rotate + mirror to display orientation
     └─ MoveNet SinglePose Lightning (int8, TFLite, 192×192)   → 17 COCO keypoints
        └─ WorkoutEngine: per-exercise scalar signal            → RepCounter (Schmitt trigger)
           └─ Cindy progression: 5 → 10 → 15, then round++
```

### Rep detection

Each movement is reduced to one scalar that swings between a low value at the bottom of the
rep and a high value at the top. A [Schmitt trigger](app/src/main/java/com/cindy/tracker/RepCounter.kt)
with two thresholds books a rep only when the signal crosses the whole dead zone, which is what
stops a jittering keypoint from machine-gunning the counter.

| Movement | Signal | Bottom | Top |
|---|---|---|---|
| Pull-up | mean elbow angle, negated | dead hang (`≈ -170`) | chin over bar (`≈ -60`) |
| Push-up | mean elbow angle | chest down (`≈ 85°`) | lockout (`≈ 175°`) |
| Squat | mean knee angle | in the hole (`≈ 80°`) | standing (`≈ 175°`) |

All three are joint angles, which need no normalisation — nothing about the athlete's build or
their distance from the camera can move them.

**Only the current movement is scored.** The three exercises share joints, and evaluating all of
them at once lets a push-up lockout leak into the squat counter. A posture test separates them:
hands above the hips means hanging, which is a pull-up and not a push-up.

### Designing for a phone on the floor

Nobody has a second person holding the camera, so the phone ends up propped on the ground
pointing up. That is the normal case, and it breaks naive approaches in two ways.

**Perspective foreshortening.** A floor-level camera squashes everything above it, so the same
pull-up projects a much smaller swing than it does from chest height. Any threshold in absolute
units is really a threshold on where you left your phone. So the counter learns the range the
athlete actually produces and puts its thresholds at 30% of that observed travel from each end;
the first rep is judged against a `minRange` floor, and after that the band tightens to what has
been demonstrated, so half reps stop counting once full ones have set the standard.

**A body that fills very little of the frame.** MoveNet resizes whatever it is given down to a
small square, so feeding it a tall frame with an athlete in a slice of it spends most of the
pixels on ceiling and floor. `PoseDetector` therefore crops to a square around where the body was
last seen, follows it, and falls back to the whole frame when tracking is lost. The model runs on
a body that fills its input.

The app ships **MoveNet Thunder** (256×256) rather than Lightning for the same reason — the
awkward angles are where the extra accuracy earns its keep. Lightning is still in `assets/`;
switching is the `modelAsset` default in `PoseDetector`.

### Two bugs this replaced

Worth recording, because both undercounted silently rather than failing loudly:

- The pull-up signal used to be shoulder rise divided by **torso length**, which put the hip
  keypoints in the denominator. Hips are the least reliable joints on someone hanging with their
  knees bent behind them, and a hip estimate drifting low inflates the divisor until the signal
  no longer reaches the arming threshold.
- Its posture guard rejected any frame where the shoulders rose **above** the hands — which is
  exactly what happens at the top of a strong pull-up. The better the rep, the more reliably it
  was thrown away.

A third followed from the fix: arming on a fixed low threshold meant a squashed range never armed
at all, so the counter now tracks the lowest value since the last rep instead. It does not matter
that the range was still unknown when the athlete was at the bottom of the movement.

### Interface

Full-screen preview with the skeleton drawn over it, and four numbers: the clock, the round,
the current movement, and reps against the target.

| Control | Action |
|---|---|
| `START` | start / pause / resume; `RESET` once time expires |
| `+1` | book a rep by hand when the angle defeats the detector |
| `+1` (long press) | skip to the next movement |
| `FLIP` | switch between the rear and selfie camera |
| `VOICE` | toggle spoken counting |
| `MUSIC` | tap to pick a track (or mute); long press to change it |
| `RECORDS` | open the record board |
| status line (long press) | debug readout: inference ms, crop state, signal, learned range, phase |

Reps buzz short, finishing a movement buzzes longer, finishing a round buzzes longest.
At `00:00` the app freezes the score as `N rounds + M reps` and logs it.

### Voice

Every rep is called out. Finishing a movement speaks the final count and then the next
movement; finishing a round announces the round number. The clock calls ten minutes, five
minutes, one minute and ten seconds.

Rep numbers are spoken with `QUEUE_FLUSH` so the voice tracks the athlete instead of falling a
queue behind during a fast set — cues that must not be dropped are queued after.

### Music

The app ships no audio. `MUSIC` opens the storage access framework so you pick a track you
already own; it loops for the workout, pauses when you pause, and ducks to 18% whenever the
voice speaks. The chosen track is remembered across launches through a persistable URI
permission, and quietly forgotten if that permission lapses.

### Records

`RECORDS` shows the benchmark to chase and every attempt logged on this phone, best first.
The benchmark is **Tom Holland — 27 rounds** (810 reps), the score that prompted this app.
Beat it and the finish line says so.

Attempts are stored in `SharedPreferences` as one `rounds,reps,timestamp` line each. A zero-rep
attempt — the app left running with nobody in front of it — is not logged.

## Build

Requires JDK 17 and the Android SDK (platform 35, build-tools 35.0.0).

```sh
./gradlew assembleDebug          # → app/build/outputs/apk/debug/app-debug.apk
./gradlew testDebugUnitTest      # rep-counting logic, on the JVM
./gradlew installDebug           # to an attached device
```

`local.properties` must point at your SDK (`sdk.dir=...`); it is deliberately gitignored.

## Tests

32 JVM tests. The rep logic runs against synthetic skeletons
([PoseFixtures](app/src/test/java/com/cindy/tracker/PoseFixtures.kt)) — full rounds, partial
reps that must not count, and cross-talk between movements — and the record board is covered
for ranking, round-tripping and corrupt-data tolerance.

They do **not** cover the camera path, the model, the voice or the music; those need a real
device.

## Camera placement

Prop the phone 2–3 m away and frame your whole body. On the floor pointing up is fine and is
what the counter is tuned for; the only hard requirement is that the working joints stay in
shot — hips, knees and ankles for squats, shoulders, elbows and wrists for the other two.

If counting looks wrong, long-press the status line for the debug readout. `rng` is the travel
the counter has learned; if it stays far below the movement you are actually doing, the joints
it needs are not being seen.

## Model

`assets/` carries MoveNet SinglePose v4, int8 quantised, from
[Kaggle Models](https://www.kaggle.com/models/google/movenet): Thunder 256×256 (6.8 MB, the
default) and Lightning 192×192 (2.9 MB). `PoseDetector` reads the input size and dtype from the
model at runtime, so switching between them — or to a float build — needs no code change.
