# Prototype for #141: icons, closing a page, type

Throwaway. Lives on `prototype/icons-navigation-type`, out of `main`, never merged. The verdict is the owner's and goes in a comment on #141.

**Open it:** double-click `index.html`, or `open prototype/icons-navigation-type/index.html`. No server, no build, no network.

## What it compares

| Switch | Options |
|---|---|
| Icons | Current (the app's own vector drawables), Lucide (ISC), Phosphor (MIT), Tabler (MIT), each drawn in the current icons' places |
| Closing a page | the full-width DONE pill, or a top bar with the back gesture (drag from the left edge, or Esc) |
| Top bar shape | control: back chevron or close x; title: centred, left, or the large title kept below |
| Type | Manrope or Inter, same sizes and tracking, tabular figures on numerals |
| Sentence under title | as today, or hidden |
| View | one phone, or the four icon sets / the two closings / the two typefaces side by side |

Every combination works on every screen: Camera, Menu, Progress, Session page, You, Movements sheet. "Real capture alongside" puts the adb capture next to the recreation; "Show touch targets" outlines each hit area (today's top-band icons are 44 x 40 dp, under the 48 dp rule). The **Icon inventory** page lists every icon the app uses and every gap.

No SF Symbols, no SF Pro, no blur.

## Bands mock for #140

[`bands.html`](bands.html) is a **mock**: the camera-screen band variants of #140 in the states idle, setup, running, paused and finished. It opens on **Two distances**, the direction the owner said yes to seeing on 2026-11-12, beside the owner's hybrid, **Thin top, today's bottom**. The other views are the hybrid beside Today's bands and Thin bands, side by side, one big phone with a switcher, all 20, and "Rejected: No bands" (No bands, its six polish designs, and No bands without −/+). It stands in for the phone test the owner cannot do now. It is not the ticket's in-app prototype, which is the branch `prototype/hud-bands` on the live camera. Double-click it; no server, no network.

- What goes where is read from `prototype/hud-bands` (`HudVariants.kt`, `activity_main.xml`, `MainActivity.renderControls()`), in dp. `bands-geometry.js` holds every number; the chrome share per variant is computed from it and printed on the page.
- The picture is the real adb capture (`assets/lens-covered-picture.jpg`, cropped from `captures/camera.png`). The lens was covered, so the person is a drawn placeholder, labelled on the page.
- **Two distances** (the default view, `bands-two.js`) draws each state for where the athlete is: at the phone (idle, setup, paused, finished) they press buttons at arm's length; at the bar (running) they are 2 to 3 m away, cannot touch and cannot read small text. No verdict yet.
  - The bands are the hybrid's to the dp: the thin top, the coaching line as pop-up A, and a bottom band of today's 220.1 dp, so the chrome share stays 39.9 % and the picture, the real zone and the analysis frame do not change. Only the inside of the bottom band is new. Its numbers are `TWO` in `bands-geometry.js`.
  - **Running is a scoreboard.** The count and its target are one figure, "3/5", at 96 sp, one size and one weight, tabular, the target stepping down in colour only. Under it one line, "Pull-ups · Round 2". Every control stays, in 48 dp targets with no names.
  - **A banked rep is seen.** The changed digits roll over 150 ms and the count pulses green (#30D158) over 300 ms, then is white again. "Bank a rep" or the phone's own + counts one; − takes one back; "Auto-play" counts through pull-ups 5, push-ups 10, squats 15 and into the next round. With `prefers-reduced-motion`, or the page's "Reduce motion" switch, nothing rolls or slides and only the colour changes.
  - **A movement change takes over the band.** When a set completes, the next set ("10" over "PUSH-UPS", one size) covers the figure and its line for 1.5 s, then the scoreboard is back at 0/10. The controls stay where they are.
  - **At the phone the controls come forward.** The figure drops to 56 sp, the shutter is the 72 dp white disc and END, RESUME, SKIP and AGAIN are 56 to 72 dp and named. In idle the screen's one line of text is the app's idle line, under the shutter, and there is no pop-up. What each control does in each state is `CameraControls.of()` as `CTRL()` in `bands.js` has it; no rule is changed.
  - "− and +" switches two arrangements. **A**, a − | + capsule in the row, 40 dp from the shutter, which then sits right of centre in every state. **B** (the pick), the capsule beside the figure, + over −, with the row left as today's END, shutter, SKIP. The plain row END, −, pause, +, SKIP is not drawn: it leaves 22 dp between + and pause.
  - "Figures" switches 3/5 in round 2 and 12/15 in round 12. "Hold a still" freezes the pulse half-way or the takeover, for a capture.
  - It fits today's height only with the font padding off: the figure is drawn in a line 1 em tall. As a plain Android line with font padding on, in Manrope ExtraBold, the 96 sp figure is 148.3 dp tall and the band would be 264.3 dp. At the phone the names leave 13.1 dp under them, 2.9 dp less than today's bottom padding. The view prints both.
  - The view prints the digit height and the angle it makes at 2 m and 3 m, the edge-to-edge gaps between +, − and their neighbours, and a self-check over 34 phones (anything outside the band, a target under 48 dp, unequal figures, overflow, a frame that differs from the hybrid's).
- **Thin top, today's bottom** (`bands-hybrid.js`) is the hybrid the owner asked for on 2026-11-07, after rejecting No bands: Thin bands applied to the top only.
  - The top band is Thin bands' one row (the cutout, a 44 dp clock row, 4 dp), with the camera switch beside REC and MENU. The coaching line leaves the band and becomes a pop-up on the picture. The bottom band is today's, untouched. The analysis frame is the same rectangle in every phone; a self-check on the page compares it.
  - The view shows Today's bands, the hybrid and Thin bands in one state, then the hybrid as one big phone. "State" and "Coaching line" switch what is shown; the lines are the app's own, from `MainActivity`, `WorkoutEngine` and `TrackingHealth` on `prototype/hud-bands`, and the table on the page names where each is set.
  - "Pop-up" switches three options: **A**, a pill at the top of the picture, in Thin bands' place, which stays (the pick); **B**, a pill 8 dp above the bottom band; **C**, a toast in A's place that fades in over 150 ms, holds 3 s and fades out over 400 ms, except for lines that ask for something (idle, setup, paused, finished, and any red dot), which stay. "Replay the pop-up" shows the toast again and "Hold the toast" stops it for a still.
  - Chrome share: the hybrid's bands take 39.9 % (thin top 91 dp + today's bottom 220.1 dp) against today's 46.4 %. With the pill counted as a band, as the branch's HUDMEASURE log counts it, 45.1 %; in area the pill is 1.1 to 3.8 % of the screen, depending on the line.
  - "Count and target at one size" is off by default. On, it sets the target at the count's 56 sp in today's readout, stepping down in colour only. Off, the bottom is exactly today's.
  - A self-check renders the hybrid in every state with every line and pop-up option and reports a pill on a band, a line cut at the pill's edge, an analysis frame that differs, and one-size figures that are unequal or run under − or +.
- A fourth variant, **No bands, no −/+**, is No bands with the two rep-editing buttons gone and the round and count redrawn on one glass plate, with readout **A** (count, then the words) or **B** (a segmented ring). **The owner rejected it on 2026-11-07: − and + stay.** It is kept for the record under the view "Rejected: No bands", badged as rejected, and is out of "Side by side" and "All 20".
- **Polish No bands** (`bands-polish.js`) answered the owner's earlier question: No bands is the best of the variants, so how can it be better? **The owner rejected No bands and all six designs on 2026-11-07.** They are kept under "Rejected: No bands", badged as rejected, and No bands is out of "Side by side" and "All 20". Six designs, one state at a time (idle, setup, running, paused, finished), each named with one line on what it optimises for. Only the bottom controls and the readout change; the top row, the coaching pill, the zone corners and the analysis frame are the same in all six, and − and + are in every one.
  - The designs: **Fraction** (No bands as it is, target grown to the count's size), **Of** ("3 of 5", − and + at the plate's ends), **Pair** (a ruled pair beside a − | + stepper capsule), **Segments** (the count alone, the target as segments in groups of five, one row of five controls), **Scoreboard** (one glass deck, the round as an equal figure), **Big type** ("3/5" at 72 sp, one row of five controls).
  - The readout rule the owner set: the count and its target are one size and one weight, stepping down in colour only (or, in Segments, the target stops being a number).
  - "Figures" switches between 3/5 in round 2 and 12/15 in round 12 (round 24 when finished), or shows both rows. "Controls footprint" draws each design's top and bottom chrome; the card and the table give the height share and the glass area.
  - "At 2 m" is the height of Inter ExtraBold's digits, measured from the bundled font in the page, as an angle at 2 m; the mock asks at least 10′ of the count.
  - A layout self-check renders all six designs in all five states with both figure sets off-screen and reports any figure outside its plate, under a button or unequal in size, any control in the real zone, and any target under 48 dp. Script errors are printed at the foot of the page.
- None of this changes a ticket's scope or touches app code.
- The analysis frame outline is one rectangle (480 x 640, mapped as `OverlayView` maps it) drawn the same in every variant. In No bands the real zone is marked by drawn corners. The glass has no blur.

## What is real and what is not

- `captures/*.png` are **real adb captures** from the Huawei P40 (1080 x 2340) taken 2026-11-06 for the spec. They show the status bar of that phone.
- The phones in the page are **HTML recreations** traced from those captures, in dp, with the app's tokens. They are labelled as such. They are not the app.
- To replace the captures, run `./capture.sh` with the phone attached. A missing capture shows a "no capture" box; nothing is faked.

## Files

- `icons.js` is generated by `tools/build-icons.mjs` from `icons/` (the SVGs of the chosen glyphs, copied from `lucide-static`, `@phosphor-icons/core` and `@tabler/icons`) and from the app's `ic_*.xml`.
- `bands.html`, `bands.css`, `bands.js`, `bands-geometry.js`, `bands-two.js`, `bands-hybrid.js`, `bands-polish.js`, `assets/` belong to the bands mock above.
- `fonts/` holds the app's Manrope files and Inter (latin, 400-800, from `@fontsource/inter`); both are SIL OFL. `licenses/` holds the licences of the three icon sets and Inter.
