/* MOCK for #140: the owner's hybrid of 2026-11-07, "Thin top, today's bottom".
   The top is Thin bands' one-row band (cutout + a 44 dp clock row + 4 dp), with the camera switch beside REC and MENU;
   the coaching line leaves the band and becomes a pop-up on the picture. The bottom band is today's, untouched.
   This file holds the coaching lines the pop-up carries, with their source on prototype/hud-bands (e6593b1), and the
   three pop-up options. Mock-only design values are marked as such. Nothing here is the app. */
(() => {
  "use strict";

  // The coaching line, per state, as the branch's MainActivity and engine set it. dot: the status dot's colour
  // (ok = state_ok, alert = state_alert, neutral = label_tertiary). fig: the readout the same code path sets with it.
  const LINES = {
    idle: [
      { text: "Tap to set up", dot: "neutral", src: "MainActivity, idle (the spec rewords it to point at the shutter, a later ticket)" },
    ],
    setup: [
      { text: "Get in frame", dot: "neutral", src: "MainActivity.enterSetup()" },
      { text: "Can't see your ankles", dot: "alert", src: "applySetup(), FRAMING: \"Can't see your \" + the missing joints" },
      { text: "Do 2 slow pull-ups to calibrate", dot: "neutral", src: "applySetup(), MOVING", fig: { reps: "1", tgt: "/2" } },
      { text: "Movement barely registers — raise the phone or step back", dot: "alert", src: "applySetup(), POOR", fig: { reps: "1", tgt: "/2" } },
    ],
    running: [
      { text: "Counting…", dot: "ok", src: "MainActivity.beginWorkout(), then the engine's hint" },
      { text: "Tracking…", dot: "ok", src: "WorkoutEngine hint" },
      { text: "Get your head over the bar", dot: "ok", src: "WorkoutEngine hint, mid-rep" },
      { text: "Hang from the bar", dot: "neutral", src: "WorkoutEngine hint, blocked: after 1.2 s the start-position card replaces the line" },
      { text: "Recalibrating…", dot: "neutral", src: "apply(), not calibrated; and on RESUME" },
      { text: "Phone moved — checking framing", dot: "neutral", src: "MainActivity.onCameraMoved()" },
      { text: "Losing you — more light helps", dot: "neutral", src: "TrackingHealth, WEAK" },
      { text: "Too dark to count — tap +1", dot: "alert", src: "TrackingHealth, LOST with a dark crop" },
      { text: "Can't see you — tap +1", dot: "alert", src: "TrackingHealth, LOST" },
    ],
    paused: [
      { text: "Paused", dot: "neutral", src: "MainActivity.toggleRun(), RUNNING to PAUSED" },
    ],
    finished: [
      { text: "3 + 4 · First Steps", dot: "neutral", src: "Attempt.scoreLabel() · caption (the level's title)" },
    ],
  };

  // The toast's timing. Mock-only design values.
  const TOAST = { inMs: 150, holdMs: 3000, outMs: 400 };

  // A line stays while it names a state the athlete is in or asks for something before counting can go on (idle, setup,
  // paused, finished, and any red dot). Only a running line with a green or grey dot is transient, so only that fades.
  const stays = (state, line) => state !== "running" || line.dot === "alert";

  const POPUPS = [
    { id: "top", name: "A. Pill at the top of the picture",
      where: "Thin bands' own place: centred, 8 dp under the thin top band, 16 dp from either edge. It stays, as today's line does.",
      life: "Stays. Changes in place when the line changes." },
    { id: "bottom", name: "B. Pill above the bottom band",
      where: "Centred, 8 dp above today's bottom band, so the line sits next to the count it explains.",
      life: "Stays. Changes in place when the line changes." },
    { id: "toast", name: "C. Toast at the top that fades",
      where: "Option A's place.",
      life: `Fades in over ${TOAST.inMs} ms, holds ${TOAST.holdMs / 1000} s, fades out over ${TOAST.outMs} ms, and comes back with the next new line. Lines that ask for something (idle, setup, paused, finished, and any red dot) do not fade.` },
  ];
  const PICK = "top";

  /** Where the pop-up's top edge sits, in dp, for a geometry g from bands-geometry.js. */
  const pillY = (g, popup) => (popup === "bottom" ? g.y0 - 8 - g.pillH : g.pillTop);

  // The placeholder athlete in bands.js PERSON, for the clearance numbers: the bar, and the body from the head to the feet.
  const ATHLETE = { barY: 192, top: 217, bottom: 522, x0: 150, x1: 210 };

  window.HYBRID = { LINES, TOAST, POPUPS, PICK, stays, pillY, ATHLETE };
})();
