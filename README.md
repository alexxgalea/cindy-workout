# Cindy Tracker

An app that counts a **Cindy** workout from the phone camera. Android is the working build; an
iOS port lives in [ios/](ios/), where the counting logic is ported and tested but the app layer
around it has never been compiled — see [ios/README.md](ios/README.md).

> AMRAP 20 minutes — 5 pull-ups, 10 push-ups, 15 air squats.

Everything runs on-device: no cloud inference, and the camera stream never leaves the phone.
The only network use is opt-in: Menu → Strava connects your own Strava account, and from then on
each finished workout — score, sets and times, plus heart rate and its calorie estimate when a
watch recorded one — uploads there on its own. Nothing is sent before you connect, and no video
or pose data is ever sent.

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

### Heels-flat squats

A squat with the heels flat on the floor stops higher than one up on the toes: the heels hold the
knees back, so the hips stop higher and the knee closes less. Both are correct squats and both
count. Seen from a phone on the floor a good heels-flat squat closes the knee 35 to 40 degrees
where the air squat asks for about 58, so none of it counted, and after a few deep squats even a
phone at chest height refused the shallower ones that followed.

**Heels flat** is a squat choice, under Menu → Movements. It is counted with two changes to the
[RepCounter](app/src/main/java/com/cindy/tracker/RepCounter.kt): a floor of 35 degrees of travel per
rep (`HEELS_FLAT_MIN_TRAVEL`), and a bottom zone of 60% of the learned travel instead of 30%, so a
session that mixes both styles counts every rep. The floor is what still refuses quarter squats and
partials. Measured through the real engine, the shallowest squat that still counts:

| Standing reads | Air squat | Heels flat |
|---|---|---|
| 175° (phone at chest height) | 115° | 135° |
| 165° | 105° | 125° |
| 155° | 90° | 115° |
| 145° (phone on the floor) | 80° | 105° |

A session with it is filed as *Adaptive Cindy · heels-flat squats* and ranked against your other
heels-flat sessions, like any other choice of movement.

**Spot heels-flat squats** is an experiment, and it is off by default. Switched on in the same
sheet, an air-squat session runs a heels-flat counter beside the air-squat one, on the same
samples, and when it has accepted three reps in a block of squats that the air-squat counter
refused, in a row or not, the session switches. Adaptive Cindy is activated, and the voice says
so: "Adaptive Cindy activated for heels-flat squats". The three reps are credited, and the
heels-flat counter counts every squat from then on, deep ones too. The session is filed as
heels-flat squats, and the results screen says why and offers to make Heels flat the choice for
every workout. It stays off until real sessions have shown it was the right call.

The two counters' bookings are matched by ascent rather than by time, which credited a rep twice
whenever they booked one a moment apart. A tapped `+1` drops what is pending, and the credit never
passes the target of the squats, so nothing is counted twice.

What it cannot do, stated plainly:

- A knee angle cannot tell a heels-flat squat from a half squat of the same travel, so both count
  as heels-flat squats. That is the permissive choice. Anything under 35 degrees of travel, which
  is a quarter squat, never counts.
- 35 is the one number to retune on a phone. At 33 a good squat from the floor counts at 110
  degrees, and so does a quarter squat from chest height.
- A tired athlete looks the same. Squats that stop short of full depth but still travel 35 degrees
  or more are heels-flat squats as far as the counter can tell, so with Spot heels-flat squats on,
  three of them after a set of deep ones switch the session to Adaptive Cindy, and it is filed
  that way. That is the permissive choice, and the reason the setting is off by default: it is
  what real sessions have to show is right.
- A `+1` tapped before the switch clears what was pending, which can leave the reps before it
  uncredited. It can never credit one twice. Pausing and resuming does not clear it.

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

### First launch

A new install is shown around before the camera opens: five pages, then the camera's permission
prompt, then a tour of the controls on the camera screen. Each happens once.

1. **Cindy, counted for you.** What the workout is, and what the phone does.
2. **Your Cindy, your movements.** Other movements count, and which ones: band-assisted pull-ups,
   push-ups from the knees and heels-flat, on-toes or box squats are counted, and movements the
   camera cannot follow, such as inverted rows, are tapped in with `+1`. It explains the setting
   that spots heels-flat squats and has a button into the movement sheet. An athlete who cannot
   do the strict movements yet is the one most likely to decide that the app counts nothing for
   them, so this page comes before anything else about how it works.
3. **Where to stand.** The placement diagram and its three facts, the same ones the sheet before
   the first setup check shows, built in one place so the two cannot disagree.
4. **Before the clock starts.** The setup check, what the status line's dot means, and what `−1`,
   `+1` and `SKIP` are for.
5. **Nothing leaves your phone.** Counting happens on the phone, `REC` films only when tapped, and
   Strava stays off until it is connected.

The pages come first so that Android asks for the camera only after the athlete has been told why.
They can be swiped, stepped through or skipped, and the last button says `LET'S GO`, or `DONE` on a
replay.

Then the tour: the screen is dimmed and each control is lit in turn, `START`, the status line, the
rep count, `SKIP`, `REC`, the menu and `FLIP`, with a card saying what it is for. A tap anywhere
moves on, and back or `SKIP TOUR` ends it. While it is showing it takes every touch, so nothing it
points at can be pressed by accident. It waits for the clock to be idle, so it never appears
mid-workout, and it leaves out any control that is not showing.

**Who sees it.** New installs only. [`Onboarding.shouldShowTutorial`](app/src/main/java/com/cindy/tracker/Onboarding.kt)
wants nothing seen yet, no session on record, the placement guide never dismissed and the camera's
permission not already held. Each of the last three means the app is not new to them. The
permission reaches furthest back, because Android starts every fresh install without it, so an
athlete who updated from an older version, and may never have finished a session, has it already.
They are marked as having seen the pages without being shown them, so clearing their records later
does not make them look new.

**Again.** Help → Take the tour replays the pages and then the tour, over the camera screen. The
placement guide before the first setup check is separate and unchanged: it is the reminder at the
moment of need, with its own "Don't show this again".

The flags are in [FirstRun.kt](app/src/main/java/com/cindy/tracker/FirstRun.kt), the pages in
[TutorialActivity.kt](app/src/main/java/com/cindy/tracker/TutorialActivity.kt), the tour in
[SpotlightView.kt](app/src/main/java/com/cindy/tracker/SpotlightView.kt), what it says about each
control in [HudTour.kt](app/src/main/java/com/cindy/tracker/HudTour.kt), and where its card sits in
[SpotlightMath.kt](app/src/main/java/com/cindy/tracker/SpotlightMath.kt).

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
| `REC` | film the workout, overlays burned in, to `Movies/Cindy`; the voice says when it starts |
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

Recording announces itself: "Recording in 3" as the countdown starts, so an athlete walking to
the bar knows filming is about to begin, "Recording" once it has, and "Recording didn't start" if
it could not. They are queued so they never cut a count off, and stay quiet while TalkBack runs,
since TalkBack already reads the countdown and the toasts.

#### Languages

The voice speaks English, Spanish, French, German, Italian, Portuguese (Brazil), Dutch, Polish,
Romanian, Turkish or Russian. The screens stay in English; only what is said aloud changes.
`MENU → Voice` lists the languages, each with its own name, where it stands on this phone, and a
▶ button to hear a sample. HEAR IT and the volume check speak in the language that is ticked.

The voices belong to the phone's speech engine (Google's, Samsung's…), not to Cindy. The app ships
no audio and asks for no internet permission. Choosing a language that is not on the phone asks
the engine to fetch it, at once and whether or not you then press SAVE, so it can be arriving
while the sheet is open; **Manage voices** opens the engine's own screen for one that will not.
An engine reports no progress, so a download that has not turned up after two minutes says the
engine may be waiting for Wi-Fi, and tapping the row asks again.

- **Workouts only use voices stored on the phone**, so counting works offline and is never held up
  by the network.
- **If the chosen language is not there yet** the workout counts in English, and a toast says so
  as it starts. The words always follow the voice actually in use, never Spanish words in an
  English voice or the reverse. A voice fetched in the meantime is picked up the next time the
  workout starts or the screen comes back.
- **A preview of a language that is not downloaded** goes through the engine's online voice, is
  labelled as an online preview, and plays a fixed sample line. If it cannot reach the network it
  says the preview needs a connection.
- **A language the engine does not speak at all** is dimmed and cannot be chosen.

How the words are made: the coach decides *what* is said and *when*, as a
[VoiceLine](app/src/main/java/com/cindy/tracker/VoiceLine.kt) — a fact, such as "round 3 took 80
seconds" — and never words it. Each language has a `Phrasebook` that does, written as an
exhaustive `when` so that a language missing a line does not compile. English is byte-identical to
what the app said before phrasebooks existed, which a golden test pins down.

- Plurals follow each language's own CLDR rule: Polish, Romanian and Russian have few/many forms,
  French and Portuguese count 0 as singular, Turkish keeps the noun singular after a number.
- One — and two, for feminine nouns in Portuguese, Polish, Romanian and Russian — is written as a
  word, so an engine cannot read it with the wrong gender.
- Outside English no digit is placed before a full stop, which engines read as an ordinal ("12."
  becomes "twelfth").
- The engine's position hints ("Get on the bar") stay English inside `WorkoutEngine`, because the
  Python parity trace compares their text. They are translated where they are spoken, through the
  [VoiceHints](app/src/main/java/com/cindy/tracker/VoiceHints.kt) catalogue, and a test reads the
  engine's source and fails on any hint the catalogue does not know.

**The translations have not been read by native speakers.** Each language is one file
([PhrasebookEs.kt](app/src/main/java/com/cindy/tracker/PhrasebookEs.kt) and so on) with its
conventions noted at the top, ready for someone to check. Adding a language is a phrasebook, an
entry in [VoicePacks](app/src/main/java/com/cindy/tracker/VoicePacks.kt) and that language's test.

### Music

The app ships no audio. `MUSIC` opens the storage access framework so you pick a track you
already own; it loops for the workout, pauses when you pause, and ducks to 18% whenever the
voice speaks. The chosen track is remembered across launches through a persistable URI
permission, and quietly forgotten if that permission lapses.

### Heart rate

Menu -> Heart rate pairs a watch or chest strap that broadcasts the standard Bluetooth LE Heart
Rate profile (service `0x180D`), the same one nearly every chest strap speaks and Garmin watches
from about 2019 on can turn on under Wrist Heart Rate -> Broadcast Heart Rate. Apple Watch and
most Wear OS watches do not broadcast it without a third-party app. Pairing is a scan, once, from
the menu; the watch then reconnects on its own whenever the camera screen is open, and a dropped
connection is retried with backoff rather than left for the athlete to notice and refix.

A Garmin paired to the same phone through Garmin Connect needs two allowances a chest strap does
not. It already holds a connection to the phone, and a device in that state may not advertise to
it at all, so the scan also lists every device already connected over Bluetooth LE, marked
"Connected to this phone". And Android keeps the service list it read from a bonded watch across
connections: read while broadcast was off, it says the watch has no heart rate. When a connection
finds no Heart Rate service, the source drops that cached list once and looks again. The scan
itself is unfiltered and matches the full advertisement in software (the Heart Rate service, or
Garmin's manufacturer ID), since some phones' hardware filters miss a service UUID that is only in
the scan response.

Where there is a heart rate, calories come from the Keytel et al. (2005) heart-rate equation
instead of the MET model above — fitted separately for women and men from measured energy
expenditure, so it follows the effort actually made rather than a table's idea of it. Below the
equation's fitted range it undershoots badly, so it is floored at 1 MET rather than trusted past
where it was validated. Any minute the watch did not cover — no watch paired, a connection gap, a
reading outside a plausible range — falls back to the MET model for exactly that stretch, and the
results screen says which parts came from which.

The formula needs a birth year and a sex beyond body weight, asked for separately in the same
sheet: a birth year rather than an age, because an age goes stale the moment it is typed, and a
third sex option that averages the other two rather than assuming one for someone who has not
said. Both are asked only here, not beside body weight, because the MET model has no use for them
and a setting nobody reads should not be asked for on that account alone.

Bluetooth needs a runtime permission either way; which one depends on the phone. Android 12 and
newer ask for Bluetooth's own scan and connect permissions. Android 11 and older instead ask for
location, because that is the permission the platform ties a Bluetooth scan to on those versions
— Cindy never reads it, and the menu explains as much when it asks. Those older versions also tie
a scan to system Location being switched on at all; if it is off, the menu says so rather than
leaving a scan that silently finds nothing unexplained.

Nothing about it leaves the phone.

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

Any session can be reopened on the page it ended on: tap a leaderboard row, a day's session in
the calendar sheet, or **OPEN** on a selected point of the chart. Reopened, it shows a single
DONE and no streak (that describes today, not the day being looked at), and a **COMPARED WITH**
card stands in for the usual against-your-best row: your best or last session at the same
movements, whichever is chosen, and only ever an earlier one — a session cannot honestly be
measured against something that had not happened yet. Tapping the card opens that one too.

Scores, rounds and paces are only compared between sessions at the same movements; a chip picks
the category. Volume, streaks and weeks count everything, since a session of any kind is still a
session.

The maths lives in [Progress.kt](app/src/main/java/com/cindy/tracker/Progress.kt) and
[Peaks.kt](app/src/main/java/com/cindy/tracker/Peaks.kt), the wording of the opening line and the
celebrations in [Cheer.kt](app/src/main/java/com/cindy/tracker/Cheer.kt), and the chart is drawn
by [ProgressChartView.kt](app/src/main/java/com/cindy/tracker/ProgressChartView.kt).

#### Rounds, reps and time

Under the score, the results screen says the session three ways. Six tiles read ROUNDS, REPS and
TIME, then AVG ROUND, FASTEST and SLOWEST, each with a line saying what it is made of: the reps
tile carries the pace in reps a minute, the rounds tile the reps into the round the clock ended
on. A tile with nothing to say is a dash, never a zero.

Below them is a pill for every round, ten to a row. Each pill is split into pull-ups, push-ups
and squats in the 5:10:15 proportion of the scheme and filled by how much of each was done, in the
same three brightnesses as the Help page, so a round with the pull-ups skipped is hollow at the
front instead of looking whole. A round is not worth thirty by definition: skipping a set still
moves the cycle on, so the pills and the tiles say what was banked. Tap a pill, or drag along
them, for "Round 8 · 12 of 30 · 5 pull-ups, 7 push-ups"; a finished round says what it cost
instead, and any reps tapped in are named as tapped. Under the pills, one card per movement gives
its reps, its time, its average finished set and its share of the set time, in the session's own
words ("knee push-ups", not "push-ups").

All of it is read off the sets the record banked, through the same check the Strava upload uses,
so a record that does not add up shows no pills rather than a guess. A session from before sets
were timed keeps its tiles and hides the rest. A session the camera lost you in says "at least"
on the reps tile and its pace, as the score line does. The reading is in
[SessionStats.kt](app/src/main/java/com/cindy/tracker/SessionStats.kt) and the pills are drawn by
[RoundTrackView.kt](app/src/main/java/com/cindy/tracker/RoundTrackView.kt). What is left of the
old session block — pause time, reps added by hand, the calorie estimate and Strava — now sits
at the bottom of the page as **Details**.

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

### You, and your badges

**There is no account.** Nothing is signed in to and nothing is sent anywhere. The card at the top
of the menu (your name, or "You") opens a screen of your own: a name, a photo, and the badges your
sessions have earned.

- **Name.** Kept with the other settings and tidied on the way in: trimmed, one space between
  words, at most 30 characters. The menu and the leaderboard use it, and until there is one the
  app says "You". It is not part of anything sent to Strava. Saving the field empty takes it back.
- **Photo.** Picked with the system photo picker, which needs no permission. The app keeps a copy
  rather than a pointer into the gallery, so deleting the original does not lose it: turned
  upright from its EXIF orientation, cut to its centred square and reduced to 320 px, as
  `avatar.jpg` in the app's own files, which is tens of kilobytes. With no photo the circle shows
  your initials, and with no name a neutral figure. It is monochrome on purpose, because the
  palette keeps colour for what you earned.
- **Backup.** The name and the photo ride the same Android backup as the records and the other
  settings, to your own Google Drive and onto a new phone, because the backup rules already carry
  the app's preferences and files. The app itself uploads neither.
- **Clearing records** removes the records, and so the badges, and leaves the name and photo.

**Badges** are worked out from the recorded sessions each time they are asked for, and nothing is
stored for them. They cannot disagree with the record board, they come back with the records from
a backup, and they go when the records are cleared. Each is stamped with the session that first
earned it, found by replaying the sessions oldest first, so a later and better session never takes
an earlier one's date.

There are 26, in six families:

| Family | Badges | Earned by |
|---|---|---|
| Sessions | First Cindy; 10, 25, 50, 100 sessions | sessions finished, of any kind |
| Rounds | First round; Novice, Intermediate, Advanced, Elite, Legend; Past Tom Holland | rounds in one standard Cindy. The rungs are read from the level table, and Past Tom Holland is beating the benchmark, more than 810 reps |
| Streaks | 3, 7, 14, 30 days in a row; 4, 12, 26 weeks in a row | a run of local days or of weeks, as under Streaks above |
| Volume | 1,000, 5,000, 10,000 reps | reps across every session |
| Pace | Round under 2 minutes; under 45 seconds | the fastest round of a standard Cindy, the two marks Help quotes |
| Craft | Every rep seen; Made it yours | a full 20-minute session with no rep tapped in; any Adaptive Cindy |

The record board's honesty rules apply. A badge for a **score**, the rounds and the pace, is only
earned by a standard Cindy the camera could stand behind. An adaptive session is a different
prescription rather than a lower score, and a session the camera could not see for half a minute
or more is a lower bound, which never claims a record. A session whose movements this version
cannot read earns none of those, and is not counted as an adaptation either, because what it was
is unknown. **Every rep seen** likewise needs a session recorded by a version that counted reps:
an older record shows no taps and no blind time because they were never written down, not
because there were none. The badges for **showing up**, the sessions, streaks and volume, count every session,
since a session of any kind is still a session.

A locked badge says how far along it is, and a tile opens a sheet with what it asks for and when
it was won. The results screen names up to three badges the session just earned, hardest first,
and counts the rest. The rules are in [Badges.kt](app/src/main/java/com/cindy/tracker/Badges.kt),
the arithmetic behind the name and the photo in
[Avatar.kt](app/src/main/java/com/cindy/tracker/Avatar.kt), the photo's storage in
[AvatarStore.kt](app/src/main/java/com/cindy/tracker/AvatarStore.kt), and the screen is
[AccountActivity.kt](app/src/main/java/com/cindy/tracker/AccountActivity.kt).

### Strava

Menu → Strava connects a Strava account, opening Strava's own consent page (in the Strava app
when it is installed, otherwise your browser). It asks for `read`, so the app can greet you by
name, and `activity:write`, the one permission an upload needs. Nothing reaches Strava before
you connect.

**Once connected, every finished workout uploads on its own** — a Crossfit activity carrying the
score, every movement as a set with the reps actually banked, clock time, paused time and real
time, and calories, estimated from your body weight or, when a watch recorded your heart rate
during the workout, from that heart rate instead — with the heart-rate trace itself uploaded as
a stream on the activity. Automatic upload is a toggle in the Strava sheet, on by default. With
it off, the results screen offers UPLOAD instead; if you finish a workout before connecting, it
offers CONNECT TO UPLOAD, which links the account and then sends that workout. The results
screen shows where an upload has got to — uploading, done (with a link to the activity), failed
with a retry, or asking you to reconnect — and the upload itself carries on in the background:
it survives the app closing, waits for a network connection, and backs off between retries
rather than hammering Strava's API. Workouts are sent as they finish; attempts already on the
record board are not uploaded retroactively.

DISCONNECT clears the tokens from the phone immediately, and also asks Strava to revoke them on
its side; that part is best-effort, so it still clears locally even if you are offline. If Strava
still lists Cindy Tracker at [strava.com/settings/apps](https://strava.com/settings/apps)
afterwards, remove it there too. The tokens, and the record of what has been uploaded, live in
their own preferences file, which is excluded from Android's own backup and device-transfer —
neither travels to a new phone the way your records do.

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

Every badge rule is tested on both sides of its boundary, and so are the honesty rules that keep
a lower-bound, adaptive or unreadable session from earning a score badge. The name, the initials
and the photo's cropping, sampling and orientation are pure and tested the same way.

The first-launch rule is tested on every combination of its inputs. The pages are built and stepped
through on a test device, and the camera-screen tour runs the real step list over the inflated HUD
layout, checking that each hole sits on its control and each card fits on the screen.

The voice is tested up to the speech engine: every line in every language (plural forms at the
awkward numbers, written-out ones and twos, each clock mark), the choice of voice against lists
shaped like Google's, Samsung's, an empty engine's and a network-only one's, the fall-back to
English, and the language list driven on a fake engine.

Real-video regression is a separate, opt-in Android instrumentation job. It decodes every native
video frame, runs the production MoveNet preprocessing/model and production counter, then emits
JSON/CSV evidence for every rejection and counted rep. Fixture data is deliberately not bundled
with the app or repository; see [tests/README.md](tests/README.md) for provisioning datasets,
scenario labels, golden keypoints, and the `videoRegressionTest` command. A missing fixture is
reported as an explicit skipped test, never as a video-test pass.

They do **not** cover the camera path, the model, how the voice sounds, whether a voice download
completes, or the music; those need a real device.

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
