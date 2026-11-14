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
The joints and bones the app draws over the athlete, on the picture and in the film: a thin cyan line for each bone and a ring at each joint below the face.
_Avoid_: overlay, stick figure, pose

**Drawn bar**:
The pull-up bar as the picture shows it: a tilted line the app finds in the picture while the athlete hangs, then holds until the phone moves. It is only drawn. It is drawn thin, in the skeleton's colour, and nothing is drawn in its place until the app is sure of it. The gate that decides whether a rep counts is separate and never reads it.
_Avoid_: bar line, rail

**Top band**:
The top of the camera screen: the cutout and one 48 dp row holding the clock at the start edge and the camera switch, REC and MENU at the end edge. It is 91 dp on the owner's phone. It holds nothing else; the coaching line is the pill below it.
_Avoid_: header, top bar (that is a page's)

**Coaching pill**:
The one line of coaching on the camera screen, a glass pill on the picture 8 dp under the top band, centred. A line too long for one row wraps. In idle it is there only while it has something to tell the athlete; the idle line is under the shutter.
_Avoid_: status line, status chip

**Scoreboard**:
The bottom band of the camera screen, drawn to be read from the bar while the clock runs: the figure, the movement and round on one line, − and + beside the figure, and the control row. In idle, setup and a pause the athlete is at the phone, not at the bar, and the band is drawn for that distance instead (see Control row); the band is the same height in both. A finished workout sits behind the session page and is drawn as idle.
_Avoid_: rep panel, counter

**Figure**:
The count and its target as one piece of text, "3/5", on the scoreboard: one size and one weight, only the target's colour is quieter. It is 96 sp while the clock runs and 56 sp at the phone.
_Avoid_: rep count, reps label

**Next set**:
What the scoreboard shows over the figure and its line for about 1.5 s when the movement changes while the clock runs: the set's target over the movement's name in capitals, "10" over "PUSH-UPS", on two rows at 48 sp with no slash, so it cannot be read as a count. After a finished set it waits about 450 ms for the last rep's roll and pulse; after SKIP it comes at once. − and + and the control row stay and answer under it; any rep banked or taken back ends it at once, and so does a pause.
_Avoid_: takeover, banner, interstitial

**Control row**:
END, the shutter and SKIP along the foot of the bottom band. While the clock runs it is quiet: three 48 dp targets with their icons. At the phone it comes forward: a 72 dp shutter in the centre, END and SKIP at 56 dp, and under each enabled control its name (END, RESUME, SKIP) in a row of labels. A dimmed control has no name. In idle the one line of text, the idle line, sits under the shutter in place of the names. The names are labels only; what a screen reader says is still the control's own name.
_Avoid_: action row, button bar

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

**Last session**:
The most recent session by when it was filed, not the best one. The menu's first row shows its date and score and opens its session page; with no sessions the row is absent.
_Avoid_: latest result, best session

**Progress**:
The page of every session over time. It leads with how the athlete is doing (the streaks and the week), then the trend, the bests, the leaderboard (the athlete's sessions ranked, with the benchmark among them) and the calendar of trained days.
_Avoid_: records, history (a record is a personal best, not a page)

**Movements**:
The page where the athlete picks a variation for each of pull, push and squat. A tap gives the row its check and is saved at once; there is no SAVE.
_Avoid_: movement picker, Make Cindy yours (the sheet it replaced)

**Top bar**:
The strip at the top of a navigation page: a Back control at the leading edge and the page's title in the middle. It, and the system back gesture, are how a page is closed.
_Avoid_: header, toolbar, DONE (the pill the top bar replaced)
