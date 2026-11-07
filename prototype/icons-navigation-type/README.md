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

[`bands.html`](bands.html) is a **mock**: the camera-screen band variants of #140 (Thin bands, No bands, Today's bands, and the rejected fourth, No bands without −/+) in the states idle, setup, running, paused and finished, side by side, as one big phone with a switcher, or as all 15, plus six designs that polish No bands. It stands in for the phone test the owner cannot do now. It is not the ticket's in-app prototype, which is the branch `prototype/hud-bands` on the live camera. Double-click it; no server, no network.

- What goes where is read from `prototype/hud-bands` (`HudVariants.kt`, `activity_main.xml`, `MainActivity.renderControls()`), in dp. `bands-geometry.js` holds every number; the chrome share per variant is computed from it and printed on the page.
- The picture is the real adb capture (`assets/lens-covered-picture.jpg`, cropped from `captures/camera.png`). The lens was covered, so the person is a drawn placeholder, labelled on the page.
- A fourth variant, **No bands, no −/+**, is No bands with the two rep-editing buttons gone and the round and count redrawn on one glass plate, with readout **A** (count, then the words) or **B** (a segmented ring). **The owner rejected it on 2026-11-07: − and + stay.** It is kept for the record under the view "Rejected: no −/+", badged as rejected, and is out of "Side by side" and "All 15".
- **Polish No bands** (the default view, `bands-polish.js`) answers the owner's next question: No bands is the best of the variants, so how can it be better? Six designs, one state at a time (idle, setup, running, paused, finished), each named with one line on what it optimises for. Only the bottom controls and the readout change; the top row, the coaching pill, the zone corners and the analysis frame are the same in all six, and − and + are in every one.
  - The designs: **Fraction** (No bands as it is, target grown to the count's size), **Of** ("3 of 5", − and + at the plate's ends), **Pair** (a ruled pair beside a − | + stepper capsule), **Segments** (the count alone, the target as segments in groups of five, one row of five controls), **Scoreboard** (one glass deck, the round as an equal figure), **Big type** ("3/5" at 72 sp, one row of five controls).
  - The readout rule the owner set: the count and its target are one size and one weight, stepping down in colour only (or, in Segments, the target stops being a number).
  - "Figures" switches between 3/5 in round 2 and 12/15 in round 12 (round 24 when finished), or shows both rows. "Controls footprint" draws each design's top and bottom chrome; the card and the table give the height share and the glass area.
  - "At 2 m" is the height of Inter ExtraBold's digits, measured from the bundled font in the page, as an angle at 2 m; the mock asks at least 10′ of the count.
  - A layout self-check renders all six designs in all five states with both figure sets off-screen and reports any figure outside its plate, under a button or unequal in size, any control in the real zone, and any target under 48 dp. Script errors are printed at the foot of the page.
- None of this changes a ticket's scope or touches app code.
- The analysis frame outline is one rectangle (480 x 640, mapped as `OverlayView` maps it) drawn the same in every variant. In No bands the real zone is marked by drawn corners, the glass has no blur.

## What is real and what is not

- `captures/*.png` are **real adb captures** from the Huawei P40 (1080 x 2340) taken 2026-11-06 for the spec. They show the status bar of that phone.
- The phones in the page are **HTML recreations** traced from those captures, in dp, with the app's tokens. They are labelled as such. They are not the app.
- To replace the captures, run `./capture.sh` with the phone attached. A missing capture shows a "no capture" box; nothing is faked.

## Files

- `icons.js` is generated by `tools/build-icons.mjs` from `icons/` (the SVGs of the chosen glyphs, copied from `lucide-static`, `@phosphor-icons/core` and `@tabler/icons`) and from the app's `ic_*.xml`.
- `bands.html`, `bands.css`, `bands.js`, `bands-geometry.js`, `bands-polish.js`, `assets/` belong to the bands mock above.
- `fonts/` holds the app's Manrope files and Inter (latin, 400-800, from `@fontsource/inter`); both are SIL OFL. `licenses/` holds the licences of the three icon sets and Inter.
