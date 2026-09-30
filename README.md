# Cindy Tracker

An app that counts a **Cindy** workout from the phone camera. Android is the working build; an
iOS port lives in [ios/](ios/), where the counting logic is ported and tested but the app layer
around it has never been compiled — see [ios/README.md](ios/README.md).

> AMRAP 20 minutes — 5 pull-ups, 10 push-ups, 15 air squats.

Everything runs on-device: no cloud inference, and the camera stream never leaves the phone.
The only network use is opt-in: Menu → Strava connects your own Strava account, so a later
release can upload finished workouts there. Nothing is sent before you connect, and no video or
pose data is ever sent.

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

### The bar gate

Elbow flexion cannot tell a pull-up from someone standing on the floor waving their arms about,
which is how reps got counted with nobody on the bar. `BarZone` fixes that by learning roughly
where the hands sit when they *are* on the bar, from the one posture that reliably marks it: a
straight-armed dead hang.

Nothing is tapped in. The setup reps already have you hanging, and every dead hang during the
workout refines the estimate, so it survives a pause without another calibration step. Tolerances
are multiples of torso length rather than pixels, so stepping toward or away from the camera does
not move the gate — and `recalibrate()` forgets the bar outright, because its position was
recorded in frame pixels and a moved camera makes those meaningless.

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
awkward angles are where the extra accuracy earns its keep, and the crop means it is not being
asked to find a body in a tall frame. Whether that trade is right depends on the phone, so
long-pressing `FLIP` swaps between them at runtime and the debug readout shows the inference
time for each.

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

### Setting up before the clock starts

`START` does not start the clock — it starts a check, because a badly placed phone undercounts
silently for twenty minutes and there is no way to tell from the score that it happened.

1. **Framing.** The joints this movement cannot be judged without have to be in shot. If they
   are not, the app names them: *"Can't see your knees"*.
2. **Calibration.** Two slow reps. The counter runs against them exactly as it will during the
   workout, so the band is seeded from the athlete's own range and rep one is judged against a
   real measurement rather than the fallback floor.
3. **Verdict.** Calibrated, and the workout starts itself. Or, after twenty seconds of movement
   that barely registers, *"Movement barely registers — raise the phone or step back"* — which
   is the failure this app was losing reps to, said out loud instead of hidden in the score.

`SKIP` bypasses the whole thing. While running, the status line turns red whenever the body is
not being tracked, so a stalled counter looks stalled.

Pausing and flipping the camera both trigger a recalibration: the bands describe this athlete as
seen from where the phone was standing, and either action can invalidate that without invalidating
the reps already counted. The status line says `Recalibrating…` until the band is re-learned.

### Interface

Full-screen preview with the skeleton drawn over it, and four numbers: the clock, the round,
the current movement, and reps against the target.

| Control | Action |
|---|---|
| `START` | start / pause / resume; `RESET` once time expires |
| `+1` | book a rep by hand when the angle defeats the detector |
| `+1` (long press) | skip to the next movement |
| `−1` | take back a rep that should not have counted; steps across movement and round boundaries |
| `STOP` | end early and save the score (replaces `FLIP` during a workout) |
| `REC` | film the workout, overlays burned in, to `Movies/Cindy` |
| `FLIP` | switch between the rear and selfie camera |
| `VOICE` | toggle spoken counting |
| `MUSIC` | tap to pick a track (or mute); long press to change it |
| `RECORDS` | open the record board |
| status line (long press) | debug readout: model, inference ms, crop state, signal, learned range, phase |
| `FLIP` (long press) | swap Thunder ↔ Lightning, to compare accuracy against latency on your phone |

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

### Filming

`REC` records the workout with the skeleton, clock, round, movement, rep count and a **CINDY**
watermark burned into the file — not just drawn on screen.

The preview's overlay is a view on top of the screen and never reaches the encoder, so the video
gets its own renderer through CameraX's `OverlayEffect`, which hands back a canvas over the
recorded buffer. The effect targets `VIDEO_CAPTURE` only; pointing it at the preview as well would
draw the skeleton twice on screen.

Everything is drawn in the analysis frame's upright space — the space the keypoints are already
in — and mapped onto the recorded buffer by [OverlayTransform](app/src/main/java/com/cindy/tracker/OverlayTransform.kt).

The first attempt composed that map out of the sensor-to-buffer matrices of both streams, and put
the entire overlay in the lower-left corner at a fraction of its size: `ImageInfo`'s matrix is a
default method that stays identity unless the analyzer asks for a coordinate system, so the
composition was pushing analysis-sized coordinates through a full sensor-to-buffer scale.

It now needs only what every frame reports about itself — its size, how far it must be turned to
be displayed, and whether it is mirrored — plus the analysis frame's dimensions. The fit is the
same FILL_CENTER the preview uses, so the recording is framed like the screen and nothing is
stretched, and the text goes through the same map so it comes out the right way up.

That calculation is deliberately plain Kotlin rather than `android.graphics.Matrix`, because
framework classes cannot run in JVM unit tests and this is the part that was wrong. It is now
covered by 13 tests asserting the properties that would have caught it: corners land on corners,
the centre on the centre, squares stay square at every rotation, and a mismatched aspect ratio
crops instead of squashing.

Video only, no audio: it keeps the app clear of the microphone permission and stops it recording
its own voice counting back at you.

Preview, analysis, recording and the overlay effect together are more surfaces than some cameras
will bind at once. Rep counting is the point of the app, so binding degrades in order — overlay
first, then recording — rather than failing outright.

### Records, levels and statistics

Every attempt ends on a results screen: score, level, rounds completed, workout time, average and
fastest round, and a bar chart of the round splits.

**Clock time and real time are reported separately.** The workout clock stops when you pause; the
day does not. Round splits are clock time, so a pause cannot inflate the round it happened in, and
the paused total is shown alongside the real elapsed time whenever it is non-zero.

**Progress** is the screen behind the menu row and the results button of the same name. It opens
with one line that is always true and never scolds. Below it, top to bottom:

- **Streaks.** The daily and weekly streak, with a strip of this week showing which days you
  trained.
- **This week against last.** Sessions, reps and time.
- **Chart.** Score, Pace or Volume over 1M, 3M, 1Y or All. Drag to scrub along it, or tap a
  point. A running-best line follows the best so far, and record points are drawn in the
  achievement colour. A score the camera could not fully see is a hollow ring and is never a
  record, because a lower-bound number should not set a bar.
- **Peaks.** The personal-best board.
- **Calendar.** Days in the current streak are tinted; tap a trained day to see its sessions.
- **Leaderboard.** Your attempts ranked against the benchmark, **Tom Holland — 27 rounds**
  (810 reps), the score that prompted this app.

Scores, rounds and paces are only compared between sessions at the same movements; a chip picks
the category. Volume, streaks and weeks count everything, since a session of any kind is still a
session.

The maths lives in [Progress.kt](app/src/main/java/com/cindy/tracker/Progress.kt) and
[Peaks.kt](app/src/main/java/com/cindy/tracker/Peaks.kt), the wording of the opening line and the
celebrations in [Cheer.kt](app/src/main/java/com/cindy/tracker/Cheer.kt), and the chart is drawn
by [ProgressChartView.kt](app/src/main/java/com/cindy/tracker/ProgressChartView.kt).

#### Streaks

A **daily** streak is consecutive local days with a session. It ends today or yesterday, so a day
that has not finished yet does not count as a break. A **weekly** streak is consecutive weeks
with at least one session, where a week starts on the day the locale says, and it ends this week
or last week for the same reason. A lower-bound attempt still counts towards a streak: it was
still a session. Milestones are celebrated on the results screen: 3, 7, 14, 21, 30, 50, 75, 100,
150, 200 and 365 days, and 2, 4, 8, 12, 26 and 52 weeks. The rules are in
[Streak.kt](app/src/main/java/com/cindy/tracker/Streak.kt).

#### Reminders

Off by default. Menu -> Daily reminder sets the time, and `TRY IT` sends one now. There is at most
one a day, and none on a day you have already trained. The text names the streak at stake, or the
best score to chase when there is no streak.

The alarm uses `AlarmManager.setWindow` with a fifteen-minute window rather than an exact alarm.
Exact alarms need a permission that Android 14 denies by default, and an inexact alarm armed a day
ahead can drift by hours, which makes a "daily" reminder useless. A reminder delivered more than
two hours late is dropped, and one never posts during a live workout. The alarm is re-armed on
every fire, on boot, on app update, on a clock or time-zone change, and whenever the app is
opened. Android 13+ asks for notification permission when the reminder is switched on; if it is
denied the row says "Blocked". Nothing leaves the phone. See
[Reminder.kt](app/src/main/java/com/cindy/tracker/Reminder.kt) and
[ReminderScheduler.kt](app/src/main/java/com/cindy/tracker/ReminderScheduler.kt).

#### Set times

The workout clock also times each set. Pauses are excluded and getting into position is
included, as they are for round splits. The results screen shows where a round's time went, per movement. Peaks
include the fastest 5 pull-ups, 10 push-ups and 15 squats, taken only from sets where the camera
saw every rep and the set reached its target.

Levels are ranked by rounds, since in a fixed 20-minute AMRAP that is the same measurement as
average round time:

| Level | Rounds |
|---|---|
| First Steps | 0 |
| Novice | 5 |
| **Intermediate** | **10** — a complete Cindy |
| Advanced | 16 |
| Elite | 21 |
| Legend | 27 — level with the benchmark |

The ladder is provisional and lives in one table in [Levels.kt](app/src/main/java/com/cindy/tracker/Levels.kt),
so retuning it is a matter of editing numbers.

Attempts persist in `SharedPreferences`, one line each, versioned so older records keep loading.
The current format (v7) also records each set's time; v1-v6 lines still load, without sets. A
zero-rep attempt — the app left running with nobody in front of it — is not logged.

### Strava

Menu → Strava connects a Strava account, opening Strava's own consent page (in the Strava app
when it is installed, otherwise your browser). It asks for `read`, so the app can greet you by
name, and `activity:write`, the one permission an upload would need. Nothing reaches Strava
before you connect.

**This build only connects and disconnects — uploads arrive in the next release.** DISCONNECT
clears the tokens from the phone immediately, and also asks Strava to revoke them on its side;
that part is best-effort, so it still clears locally even if you are offline. If Strava still
lists Cindy Tracker at [strava.com/settings/apps](https://strava.com/settings/apps) afterwards,
remove it there too. The tokens live in their own preferences file, which is excluded from
Android's own backup and device-transfer — they do not travel to a new phone the way your
records do.

Building this yourself needs a Strava API application — create one at
[strava.com/settings/api](https://www.strava.com/settings/api), with its "Authorization
Callback Domain" set to `localhost` — and its client ID and secret in a gitignored
`strava.properties` at the repo root, next to `keystore.properties`:

```
clientId=...
clientSecret=...
```

Without that file — true for CI and a fresh clone — the feature quietly turns itself off rather
than failing the build: `BuildConfig` bakes in empty strings, and the menu row reads "Not
available in this build".

## Build

Requires JDK 17 and the Android SDK (platform 35, build-tools 35.0.0).

```sh
./gradlew assembleDebug          # → app/build/outputs/apk/debug/app-debug.apk
./gradlew testDebugUnitTest      # rep-counting logic, on the JVM
./gradlew installDebug           # to an attached device
```

`local.properties` must point at your SDK (`sdk.dir=...`); it is deliberately gitignored.

## Tests

The JVM suite covers the logic below. **JDK 17 is required** for Android Gradle test runs. The rep logic runs against synthetic skeletons
([PoseFixtures](app/src/test/java/com/cindy/tracker/PoseFixtures.kt)) — full rounds, partial
reps that must not count, and cross-talk between movements — and the record board is covered
for ranking, round-tripping and corrupt-data tolerance.

Real-video regression is a separate, opt-in Android instrumentation job. It decodes every native
video frame, runs the production MoveNet preprocessing/model and production counter, then emits
JSON/CSV evidence for every rejection and counted rep. Fixture data is deliberately not bundled
with the app or repository; see [tests/README.md](tests/README.md) for provisioning datasets,
scenario labels, golden keypoints, and the `videoRegressionTest` command. A missing fixture is
reported as an explicit skipped test, never as a video-test pass.

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
