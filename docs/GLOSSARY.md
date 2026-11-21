# Cindy

A camera-based counter and logbook for the Cindy benchmark: 20 minutes of rounds of 5 pull-ups, 10 push-ups and 15 squats, done in that order. It counts what the athlete does and coaches them while they do it; it is not a referee. Cindy is the first workout in a catalog of them, and the app keeps its name.

## Language

### Workouts

**Workout**:
A named plan the athlete chooses before the clock starts: its movements, its structure (AMRAP, EMOM, For time or Free), its time cap and how it is scored. Cindy is one. Every session is filed under the workout it was, and every session recorded before workouts existed is a Cindy. Records, levels, badges and the leaderboard are kept per workout; streaks and weekly volume count every session.
_Avoid_: mode, program, routine, WOD

**Freestyle**:
The second workout: pull-ups, push-ups and squats in any order and any amount, chosen by the athlete as they go and named by recognition. The clock counts up from START with no cap, and STOP ends it; there is no setup check, no target and no round. It is scored by each movement's reps and the time, and keeps no records, levels or badges. A movement outside the three is not refused: it is counted as whichever of the three shares its position.
_Avoid_: free mode, open workout, à la carte

**Category**:
What a score may be ranked against: the same workout, done with the same variations. A standard Cindy and an Adaptive Cindy are two categories of one workout.
_Avoid_: division, class

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
One movement's reps within one round, such as the 10 push-ups of round 3. In Freestyle, which has no rounds, a set is a run of one movement's reps, ended by a rest or a transition; it is worked out after STOP from when the reps were banked, and the athlete may give a set another movement on the session page, which marks the set "changed by you" and recomputes the totals. A set given the movement of its neighbour stays a separate set, and the gap between them reads as a Rest.
_Avoid_: block, bout

**Rest**:
In Freestyle, a gap long enough to end a set between two sets of the same movement.
_Avoid_: break, pause (a pause is the athlete stopping the clock)

**Transition**:
In Freestyle, the gap between two sets of different movements.
_Avoid_: changeover, switch

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

### Movements and recognition

**Movement**:
One of the things the athlete does reps of: a pull-up, a push-up or a squat, each in the athlete's chosen variation.
_Avoid_: exercise

**Position**:
Where the athlete's body is: on the bar, on the floor, or standing. Each movement starts from one position. Standing means on the feet, with the shins under the knees, so kneeling is on the floor and never standing. A body not seen well enough is in no position, and is doing no movement.
_Avoid_: posture, pose, stance

**Recognition**:
The app working out by itself which movement the athlete is doing. A movement is recognised only once reps have been counted in its position, and the reps that confirmed it are banked. It stays recognised through pauses until a different movement is. Recognition names movements only: transitions and rests are worked out afterwards from when the reps were banked.
_Avoid_: detection, auto-detect, exercise detection

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
The bottom band of the camera screen, drawn to be read from the bar while the clock runs: the figure, the movement and round on one line (in Freestyle the movement and its session total, and the workout's name until a movement is recognised), − and + beside the figure, and the control row. In idle, setup and a pause the athlete is at the phone, not at the bar, and the band is drawn for that distance instead (see Control row); the band is the same height in both. A finished workout sits behind the session page and is drawn as idle.
_Avoid_: rep panel, counter

**Figure**:
The count and its target as one piece of text, "3/5", on the scoreboard: one size and one weight, only the target's colour is quieter. It is 96 sp while the clock runs and 56 sp at the phone. In Freestyle there is no target: the figure is the reps since recognition last confirmed a movement, "7", and the movement's total for the session sits small on the movement's line. A rest inside one movement does not reset it, so one figure may hold what the session page later shows as two sets. Before recognition confirms a new movement the figure stays on the last one, and the new movement's figure arrives already at 2.
_Avoid_: rep count, reps label

**Next set**:
What the scoreboard shows over the figure and its line for about 1.5 s when the movement changes while the clock runs: the set's target over the movement's name in capitals, "10" over "PUSH-UPS", on two rows at 40 sp with no slash, so it cannot be read as a count. After a finished set it waits about 450 ms for the last rep's roll and pulse; after SKIP it comes at once. − and + and the control row stay and answer under it; any rep banked or taken back ends it at once, and so does a pause.
_Avoid_: takeover, banner, interstitial

**Control row**:
END, the shutter and SKIP along the foot of the bottom band. While the clock runs it is quiet: three 48 dp targets with their icons. At the phone it comes forward: a 72 dp shutter in the centre, END and SKIP at 56 dp, and under each enabled control its name (END, RESUME, SKIP) in a row of labels. In Freestyle STOP stands where END is and SKIP's place stays empty, so each control keeps its place. A dimmed control has no name. In idle the one line of text, the idle line, sits under the shutter in place of the names, and leads with the chosen workout's name. The names are labels only; what a screen reader says is still the control's own name.
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
The most recent session by when it was filed, not the best one. The menu's first row shows its date and score (for a Freestyle, which has no score, its total reps and its time) and opens its session page; with no sessions the row is absent.
_Avoid_: latest result, best session

**Progress**:
The page of every session over time. It leads with how the athlete is doing (the streaks and the week), then the chosen workout's trend, bests and leaderboard (its sessions ranked, with the benchmark among them on Cindy's) and the calendar of trained days. Freestyle keeps no records, so with Freestyle chosen the page shows its recent totals per movement in their place.
_Avoid_: records, history (a record is a personal best, not a page)

**Movements**:
The page where the athlete picks a variation for each of pull, push and squat. A tap gives the row its check and is saved at once; there is no SAVE.
_Avoid_: movement picker, Make Cindy yours (the sheet it replaced)

**Workouts page**:
The page that lists the catalog of workouts, each with its format and one line, where the athlete picks the one the next session will be. A tap is saved at once. It opens from the menu's Workout row, whose subtitle names the choice, and by itself at first launch and when an update brings a workout the athlete has not seen, but only once the catalog holds more than one.
_Avoid_: workout picker, library

**Top bar**:
The strip at the top of a navigation page: a Back control at the leading edge and the page's title in the middle. It, and the system back gesture, are how a page is closed.
_Avoid_: header, toolbar, DONE (the pill the top bar replaced)
