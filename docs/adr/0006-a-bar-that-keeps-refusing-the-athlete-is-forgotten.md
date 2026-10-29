# A bar that keeps refusing the athlete is forgotten

On 2026-10-29 four of six sessions in a day's tests stayed at 0 of 2 in the setup check while the athlete pulled up, and said "Get on the bar" until they gave up or skipped it. Each had learned its bar from a hang whose wrists were 3 to 6 px apart, so the zone was a sliver and a normal grip fell outside it. Nothing healed it: the bar is refined only by grips it already accepts, and the one recovery needed the athlete to change size in the frame. The owner decided that the engine learns the first hang with at least a quarter torso either side of the hands, and forgets a bar that has refused half of the last four seconds, to learn it again from the next hang. This reverses the rule that a bar is never re-taught by movement at the same scale, which five tests held.

## Considered Options

- Keep "never re-taught" and only widen the first grip: rejected, because it repaired one of the four sessions; in two the bar had been learned at the frame's left edge, where the athlete was not.
- Refuse to learn a bar from wrists less than a tenth of a torso apart and wait for a real grip: it repaired all four and touched no existing rule, and the owner declined it for the fuller recovery below. A hang with the hands together would never teach a bar.
- Forget only a bar learned from a narrow grip: rejected, because the synthetic poses the engine tests use all have narrow grips, so it did not keep the old rule for them either.
- Widen the first grip and forget any bar that has refused for four seconds: chosen.

## Consequences

- Someone who steps off the bar and keeps repeating the movement for more than four seconds teaches the engine a new bar and scores on the floor. Before, only a change of body scale could do that.
- `BarGateTest` and `PullupOcclusionTest`, and their Swift twins, run two seconds off the bar where they ran four to ten repetitions, and a new case in each says what a longer run does.
- The numbers (a quarter torso, four seconds, half of the frames) are starting values from six sessions in one gym with one athlete. `StuckCalibrationTest` replays five of those setups, and the Swift engine is held to the Kotlin engine's own moment of READY on each.
- The change is in `BarZone` and `BarRefusalWatch`, in Kotlin, the Python port and CindyCore, and has to stay in step in all three. Turning the watch off restores the old rule.
