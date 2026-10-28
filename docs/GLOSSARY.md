# Cindy

A camera-based counter and logbook for the Cindy benchmark: 20 minutes of rounds of 5 pull-ups, 10 push-ups and 15 squats, done in that order. It counts what the athlete does and coaches them while they do it; it is not a referee.

## Language

### Reps

**Banked rep**:
A rep that counts toward the score, whether the camera saw it or the athlete tapped it in.
_Avoid_: valid rep, counted rep, good rep

**Rep quality**:
What the app observed about a banked rep, such as how deep it went or whether it locked out. It never decides whether the rep is banked.
_Avoid_: valid/invalid, form verdict

**No rep**:
A rep refused for falling short of a movement standard. It exists only in Judge mode.
_Avoid_: invalid rep, rejected rep

**Judge mode**:
An opt-in way of doing the workout in which no reps are possible. The default is the coach.
_Avoid_: strict mode, competition mode

**Unbanked attempt**:
A movement that travelled the range of a rep but was stopped by one of the movement's gates, such as a pull-up that ended below the bar. It is recorded with the gate's reason and never counts.
_Avoid_: missed rep, failed rep, no rep

**Refused frame**:
A camera frame the counter did not use, with the reason it was refused (for example "Get on the bar").
_Avoid_: rejected rep

**Set**:
One movement's reps within one round, such as the 10 push-ups of round 3.
_Avoid_: block, bout

**Weak rep**:
A banked rep that fell well short of the session baseline's range, at the bottom or at the lockout. It is marked, never refused.
_Avoid_: bad rep, invalid rep, no rep

**Quality drop**:
One measure of rep quality, such as depth or lockout, falling below the session baseline for two sets in a row. The app reports the drop, not its cause.
_Avoid_: fatigue, degradation, form breakdown

**Observation**:
What the app says about a quality drop: what changed and since which round. It never tells the athlete what to do.
_Avoid_: advice, recommendation, tip, suggestion

**Session baseline**:
How the athlete moved in the first two rounds of today's session, for each movement. Rep quality is described against it ("since the start of the session"), never against a universal standard or past sessions.
_Avoid_: personal baseline, your usual, calibration, norm

### The athlete's setup

**Variation**:
The version of a movement the athlete has chosen to do, such as a knee push-up or a band-assisted pull-up.
_Avoid_: mode, scaling option

**Setup check**:
The short check before the clock starts that learns where the bar is and how far this athlete moves today. What it learns lasts for one session.
_Avoid_: calibration (on its own), onboarding

### The camera screen

**Picture**:
The camera's live image of the athlete on the camera screen.
_Avoid_: preview, feed, camera view

**Skeleton**:
The joints and bones the app draws over the athlete, on the picture and in the film.
_Avoid_: overlay, stick figure, pose

**Skeleton lag**:
The skeleton showing the body where it was a moment ago, so it trails or jumps off the athlete in the picture. It is about the skeleton against the picture, not against the real athlete.
_Avoid_: delay, latency (on their own)

**Picture delay**:
How far the picture runs behind the real athlete. The app may raise it on purpose to remove skeleton lag.
_Avoid_: delay, latency (on their own)

**Film**:
The video of a workout that the athlete chooses to record, with the skeleton and the count burned in.
_Avoid_: recording (on its own), clip

### The app's pages

**Session page**:
The page for one session, shown when a workout ends and when a past session is reopened.
_Avoid_: results, results screen, summary

**Progress**:
The page of every session over time: the trend, the calendar of trained days and the leaderboard.
_Avoid_: records, history (a record is a personal best, not a page)
