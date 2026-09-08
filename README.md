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

| Movement | Signal | Bottom | Counts at |
|---|---|---|---|
| Pull-up | shoulder rise toward the hands, in torso-lengths | dead hang (`< -0.85`) | `> -0.45` (chin over bar) |
| Push-up | mean elbow angle | chest down (`< 100°`) | `> 150°` (lockout) |
| Squat | mean knee angle | in the hole (`< 100°`) | `> 158°` (standing) |

Two details that matter:

- **Signals are normalised by torso length**, so how far you stand from the camera does not
  change the thresholds.
- **Only the current movement is scored.** The three exercises share joints, and evaluating all
  of them at once lets a push-up lockout leak into the squat counter. There are also posture
  guards — hands above the shoulders is a pull-up, not a push-up.

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

Prop the phone 2–3 m away, framing your whole body — the counters need hips, knees and ankles
for squats, and wrists above the head for pull-ups. Landscape framing side-on works best for
push-ups.

## Model

`app/src/main/assets/movenet_lightning.tflite` is MoveNet SinglePose Lightning v4, int8
quantised (2.9 MB), from [Kaggle Models](https://www.kaggle.com/models/google/movenet).
`PoseDetector` reads the input size and dtype from the model at runtime, so dropping in Thunder
(256×256) or a float build needs no code change.
