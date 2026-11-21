# Freestyle is counted by recognition, with no setup check

Freestyle is pull-ups, push-ups and squats in any order, so there is no prescribed next movement for a workout engine to count against. On 2026-11-21 the owner decided that in Freestyle recognition banks the reps: the position the athlete is in picks the one counter that runs, a movement is confirmed at its second counted rep and both reps are banked then. There is no setup check: START starts the clock and the bar is learned from a still hang, which is the case recognition's numbers (0 wrong confirmations, 0 idle recognitions on two of the owner's films and one clip) were measured in. A movement outside the three is not refused: a lunge counts as squats and a dip as pull-ups, and the athlete fixes a set's movement on the session page after STOP.

## Considered Options

- Cindy's setup check before Freestyle: rejected, because recognition was measured without it on purpose, and a check made for one fixed first movement does not fit a workout with none.
- A framing-only check (whole body in view): rejected for now; it is the fallback if the device check shows first sets being missed.
- A cheap "not one of the three" guard, such as asymmetric knees for lunges: rejected until the owner's films show a stray movement happening.
- More movements now: rejected; telling apart movements that share a position is the learned-model question that ADR 0002 keeps closed.
- Recognition banking the reps, with no check and no guard: chosen.

## Consequences

- A set recognition never confirms is lost whole: Freestyle has no SKIP and no round to recover it, and − and + stay dimmed until a movement is confirmed. Kipping pull-ups on the clip's angle (#184) must be counted, or declared out of scope, before Freestyle ships.
- The first rep of every set is shown and spoken only at confirmation, as part of a jump to 2; a set of one rep is not counted.
- The Cindy counting trace must stay byte-identical; Freestyle's counting is held to the recognition trace in Kotlin and the Python twin.
- Freestyle is "done" when the harness holds today's recognition thresholds, per-movement totals equal to the labels, set boundaries near the labels, and an owner film in a mixed order from at least two camera placements.
