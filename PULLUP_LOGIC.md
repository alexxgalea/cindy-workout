# Pull-up counting rules

Pull-ups are the only Cindy movement with gates in front of the counter. Push-ups and squats are
a joint angle fed straight to [`RepCounter`](app/src/main/java/com/cindy/tracker/RepCounter.kt);
a pull-up also has to establish that the athlete is *on a bar*, because elbow flexion alone counts
anyone waving their arms overhead. This file is the spec for those gates.

## A valid rep

All of the following, in order, in
[`WorkoutEngine`](app/src/main/java/com/cindy/tracker/WorkoutEngine.kt):

1. **Both wrists visible** — each at or above `MIN_SCORE` (0.30).
2. **Hands overhead** — the wrist midpoint is above the hip midpoint. Tested against the hips,
   not the shoulders, because the shoulders climb past the hands at the top of a good rep.
3. **Hands on the bar** — both wrists inside the learned `BarZone`, whose tolerances are multiples
   of torso length so stepping toward or away from the camera does not move the gate.
4. **A dead hang since the last count** — arms straight (see below) with the nose at least
   `HEAD_RESET_TORSOS` (0.25) of a torso below the bar line. This sets `pullupDownSeen`.
5. **The head crosses the bar** — `nose.y < bar.lineY`.
6. **`RepCounter` agrees** — the smoothed signal (negated elbow angle) has climbed far enough off
   its trough, and `minRepMs` (400 ms) has passed since the last count.

After a count, `pullupDownSeen` is cleared: the next rep needs its own dead hang.

## Straight arms are relative, not 150 degrees

`DEAD_HANG_DEGREES` is 150, but that number assumes the camera sees the elbow square on. A phone
standing on the floor looks up at the athlete and foreshortens the upper arm, so a genuinely
locked-out hang can project as 140 — and a fixed threshold then refuses to arm a single rep for
an entire workout.

So the threshold is derived from the straightest arms actually seen on this bar, from this camera:

```
deadHang = min(DEAD_HANG_DEGREES, max(DEAD_HANG_FLOOR_DEGREES, extendedElbow - SLACK))
```

with `SLACK` 15 degrees and a floor of 130. The floor matters: without it the derivation eats
itself, because an athlete only ever seen with bent arms teaches a small "extension" that then
drops the threshold far enough for those same bent arms to qualify as a hang. No camera angle
turns a 60-degree elbow into a locked-out one.

This is the same argument that made `RepCounter` learn its band instead of trusting fixed
thresholds, applied to the gate in front of it.

## Occlusion: brief blackouts are ridden out

A pull-up hides its own keypoints exactly where the rep is decided. At the top the head tilts
back and the wrists pass behind it, so the nose or a wrist routinely drops below `MIN_SCORE` for
a few frames right as the chin clears the bar.

The engine used to treat the first unreadable frame as *left the bar* and discard the cycle. On
real footage that cost nine reps in ten: a verified ten-rep set scored 1.

Now an unreadable frame is absorbed:

- **Fewer than `MAX_DROPOUT_FRAMES` (8) consecutively** — the cycle survives, `pullupDownSeen`
  is kept, but nothing is scored on those frames.
- **More than that** — indistinguishable from having dropped off the bar, so the cycle ends and
  a fresh dead hang is required.
- **No cycle in flight** — an unreadable frame resets immediately; there is nothing to protect.

Eight frames is about a third of a second at 24fps. It was chosen by sweeping 0–24 against the
labelled clips: the counts plateau at 8 and no higher value scores another rep, while every extra
frame weakens the "left the bar" test. See `tests/README.md` for how to re-run that sweep.

## Observing versus scoring

`RepCounter.update` takes a `mayCount` flag. Every readable on-bar frame is *observed*, so the
learned band describes the athlete's whole swing; only a frame that clears all the gates above may
*book* a rep.

Withholding the samples instead — the previous approach — starved the counter, leaving it to judge
reps against a band built from a fraction of the movement. That is what made a calibrated setup
report a range of 45 degrees for a movement that actually spans 115.

## The bar can be un-learned

`BarZone` is refined only by dead hangs that already pass its own gate, which stops someone
stepping off the bar from dragging the learned line down to the floor. But that also means a bar
established in the wrong place can never correct itself, and the athlete is locked out for the
rest of the workout. One clip mis-established the bar during a walk-up and then rejected 2377 of
its 2888 frames with "Get on the bar".

So the estimate is abandoned when it is *sustainedly contradicted at a different body scale*:
more than `MAX_BAR_CONTRADICTIONS` (30) consecutive straight-armed hangs refused by a bar whose
establishing torso differs by more than `BAR_SCALE_CHANGE` (1.6x). The scale test is what keeps
this from undoing the off-bar guard — an athlete stepping down and repeating the movement on the
floor keeps the same torso length, so their reps still do not count.

## Hints

Each rejection sets `hint`, which the UI shows and the offline harness records:

| hint | gate |
|---|---|
| `Show both hands` | a wrist below `MIN_SCORE` |
| `Hang from the bar` | wrists not above the hips |
| `Get on the bar` | wrists outside the learned `BarZone` |
| `Arms out of frame` | elbow angle unmeasurable |
| `Show your head` | nose below `MIN_SCORE` |
| `Return to a dead hang` | no `pullupDownSeen` since the last count |
| `Get your head over the bar` | armed, but the nose has not crossed the bar line |
| `Drive up` | all gates open, `RepCounter` not yet satisfied |
| `Tracking…` | the pose detector lost its region of interest |

## Verifying a change

These rules are covered by `PullupOcclusionTest`, `BarGateTest`, `SetupTest` and
`WorkoutEngineTest` on synthetic skeletons, and by the labelled clips in
`tests/scenarios/youtube.json` through the desktop harness. Both matter: the synthetic tests pin
the semantics, the clips say whether they survive contact with MoveNet. See
[tests/README.md](tests/README.md).
