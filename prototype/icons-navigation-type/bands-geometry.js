/* MOCK for #140: the camera screen's band variants (three from the ticket, the owner's rejected fourth: No bands without - and +,
   the owner's hybrid of 2026-11-07: Thin bands' top over today's bottom, and "Two distances" of 2026-11-12, which
   keeps the hybrid's top and the height of today's bottom and redraws what is inside the bottom band), in dp.
   Every number below is read from prototype/hud-bands (e6593b1): res/layout/activity_main.xml (today's bands),
   HudVariants.kt (tune(), glass(), makeCompact()) and ZoneCornersView.kt. Nothing here is the app.

   Line heights are Android's, not CSS's: with includeFontPadding on (the default) a TextView is as tall as the
   font's bounding box, which for Manrope is yMax + |yMin| of each weight (read from the .ttf files in fonts/):
   ExtraBold 1.2295 + 0.315, Bold 1.202 + 0.305, SemiBold 1.175 + 0.295. With these, today's bottom band comes
   out at 660 px against the 662 px measured on the 2026-11-06 capture, so the model is anchored to the phone. */
(() => {
  "use strict";
  const W = 360, H = 780, PX = 3;               // 1080 x 2340 at 480 dpi: 1 dp = 3 px
  const LH = { xb: 1.5445, b: 1.507, sb: 1.47 };  // line height per em, Manrope ExtraBold / Bold / SemiBold
  const INSET = 43;                              // the cutout, applied as padding-top of the top band (derived, see below)
  const MEASURED = { topPx: 426, bottomPx: 662, spec: { topPx: 426, bottomPx: 533, pct: 43 } };

  const NOPM_PLATE = 80;                         // the fourth variant's readout plate, in dp (see geom())
  const eyebrow = 11 * LH.b;                     // Cindy.Eyebrow, 11sp Bold
  const stat = Math.max(22, 14 * LH.sb);         // status row: minHeight 22dp, 14sp SemiBold

  /** The layout of one variant, in dp, from the camera screen's top-left. */
  function geom(variant) {
    const g = { variant, W, H };
    // The hybrid ("Thin top, today's bottom") takes Thin bands' top and today's bottom, each exactly as the branch sizes it.
    const thinTop = variant !== "today";
    const compact = variant !== "today" && variant !== "hybrid" && variant !== "two";   // the bottom band
    g.thinTop = thinTop; g.thinBottom = compact;
    // ---- top band -----------------------------------------------------------------
    if (!thinTop) {
      g.rowTop = 14 + INSET; g.rowH = 48;                  // paddingTop 14 + cutout; clockRow 48dp
      g.statusTop = g.rowTop + g.rowH + 4; g.statusH = stat;   // marginTop 4, in the band
      g.topH = g.rowTop + g.rowH + 4 + stat + 11;          // + paddingBottom 11
      g.topParts = [["padding top (14 dp) + cutout (" + INSET + " dp)", g.rowTop], ["clock row", 48], ["gap", 4], ["coaching line", stat], ["padding bottom", 11]];
    } else {
      g.rowTop = INSET; g.rowH = 44;                       // setBandBase(top: 0 .. bottom: 4); clockRow 44dp
      g.topH = g.rowTop + g.rowH + 4;
      g.topParts = [["cutout", INSET], ["clock row", 44], ["padding bottom", 4]];
      g.pillTop = g.topH + 8;                              // statusRow as a pill, 8dp under the band
      g.pillH = 14 * LH.sb + 12;                           // 14sp text, 6dp padding either side
    }
    // icons in the clock row: 44 x 40, paddingEnd 12; the camera switch is first of three
    g.icon = { w: 44, h: 40 };
    const glass = variant === "none" || variant === "nopm";
    const gap = glass ? 8 : 0;                             // glass() gives each a marginStart of 8
    g.menuX = W - 12 - 44;
    g.recX = g.menuX - gap - 44;
    g.switchX = g.recX - gap - 44;
    g.iconTop = g.rowTop + (g.rowH - 40) / 2;
    // ---- bottom band --------------------------------------------------------------
    if (!compact) {
      const C = Math.max(52, 56 * LH.xb);                  // count row: reps 56sp ExtraBold taller than the 52dp editors
      g.eyebrowH = eyebrow; g.countH = C;
      g.bottomH = 3 + 14 + eyebrow + 4 + C + 12 + 68 + 16;
      g.bottomParts = [["progress edge", 3], ["gap", 14], ["round / movement line", eyebrow], ["gap", 4], ["count row", C], ["gap", 12], ["action row (shutter 68)", 68], ["padding bottom", 16]];
      g.y0 = H - g.bottomH;
      g.eyebrowTop = g.y0 + 3 + 14;
      g.countTop = g.eyebrowTop + eyebrow + 4;
      g.actionTop = g.countTop + C + 12; g.actionH = 68;
      g.shutter = 68; g.side = 52; g.edit = 52; g.edX = 20;
      if (variant === "two") {
        // Two distances: the band is today's height to the dp, so the picture and the real zone are the hybrid's.
        g.two = TWO;
        g.bottomParts = [["progress edge", 3], ["gap", TWO.zoneGap], ["figure zone (the count and its target at " + TWO.figSp + " sp in a 1 em line)", TWO.zoneH],
          ["movement and round line", TWO.lineH], ["gap", TWO.rowGap], ["control row (48 dp targets)", TWO.rowH],
          ["padding bottom", g.bottomH - TWO.runUsed]];
      }
    } else {
      const K = Math.max(48, 44 * LH.xb);                  // reps autosize 24..44sp: 44sp ExtraBold sets the height
      // No bands, no -/+ (variant "nopm"): nothing but type to hold, so the plate is drawn to its own height: 64 sp reps
      // in readout A, a 68 dp ring in readout B, 80 dp either way. Mock-only design value, not read from the branch.
      const boxH = variant === "nopm" ? NOPM_PLATE : glass ? K + 8 : K;
      g.K = K; g.boxH = boxH;
      const gapTop = glass ? 6 : 4;
      g.bottomH = 3 + gapTop + boxH + 6 + 56 + 8;
      const plateName = variant === "nopm" ? "readout plate (A: 64 sp reps; B: 68 dp ring; no -/+)" : glass ? "count pill (44 sp reps + 4 dp padding)" : "count row (reps 44 sp)";
      g.bottomParts = [["progress edge", 3], ["gap", gapTop], [plateName, boxH], ["gap", 6], ["action row (shutter 56)", 56], ["padding bottom", 8]];
      if (variant === "nopm") {
        // The other variants are sized with Android's font padding on. If the real app kept it on for a 64 sp ExtraBold
        // reps line, the plate would be 64 x 1.5445 + 8 dp and the bottom taller by the difference.
        g.platePadded = 64 * LH.xb + 8;
        g.bottomHPadded = g.bottomH + (g.platePadded - boxH);
      }
      g.y0 = H - g.bottomH;
      g.boxTop = g.y0 + 3 + gapTop;
      g.boxX = glass ? 16 : 0; g.boxW = glass ? W - 32 : W;
      g.boxPad = glass ? [18, 8] : [20, 20];               // left, right
      g.actionTop = g.boxTop + boxH + 6; g.actionH = 56;
      g.shutter = 56; g.side = 48; g.edit = 48; g.edX = 20;
    }
    g.stackH = 2 * eyebrow + 2;                            // compact count row: round line + movement line + 2dp
    // today's zone: where today's bands leave the picture bright (captureToday() of the prototype)
    return g;
  }

  /** Two distances, inside today's bottom band. Mock-only design values on an 8 grid, measured from the band's top edge.
      Running (at the bar): a 96 dp figure zone, one 24 dp line, a 48 dp control row.
      Idle, setup, paused, finished (at the phone): the same 96 dp zone holding a 56 sp figure and its line, then a
      72 dp control row and a 16 dp label row.
      The figure is set in a line 1 em tall (font padding off, fixed height). With Android's font padding on, a 96 sp
      Manrope ExtraBold line is 96 x 1.5445 dp tall: paddedBottom() gives the band that would need. */
  const TWO = (() => {
    const t = { figSp: 96, phoneFigSp: 56, lineSp: 17, zoneGap: 8, zoneH: 96, lineH: 24, rowGap: 16, rowH: 48,
      phoneGap: 8, phoneRowH: 72, labelGap: 4, labelH: 16, minPad: 16 };
    t.zoneTop = 3 + t.zoneGap;                              // under the progress edge
    t.lineTop = t.zoneTop + t.zoneH;
    t.rowTop = t.lineTop + t.lineH + t.rowGap;
    t.runUsed = t.rowTop + t.rowH;                          // what the running layout uses, before the bottom padding
    t.phoneRowTop = t.zoneTop + t.zoneH + t.phoneGap;
    t.labelTop = t.phoneRowTop + t.phoneRowH + t.labelGap;
    t.phoneUsed = t.labelTop + t.labelH;
    // The least each layout needs: its content and a 16 dp bottom padding. A's figure needs only its own 1 em line of
    // the zone if the zone were cut to it; B's zone is the 96 dp of its two stacked 48 dp targets.
    t.needRun = t.runUsed + t.minPad;
    t.needPhone = t.phoneUsed + t.minPad;
    // Android's line with font padding on, Manrope as the code has it: ExtraBold figure, SemiBold line.
    t.paddedFig = t.figSp * LH.xb;
    t.paddedLine = t.lineSp * LH.sb;
    t.paddedRun = 3 + t.zoneGap + t.paddedFig + t.paddedLine + t.rowGap + t.rowH + t.minPad;
    // Control places, x in dp. A: END, the stepper capsule, then the run control and SKIP, the capsule 40 dp from the
    // run control. B: END, the run control in the centre, SKIP; the stepper stands beside the figure, + over \u2212.
    t.arr = {
      A: { endCx: 40, runCx: 240, skipCx: 320, stepper: { x: 80, w: 96, h: 48, vertical: false }, figX: 16, figW: W - 32 },
      B: { endCx: 40, runCx: 180, skipCx: 320, stepper: { x: 296, w: 48, h: 96, vertical: true }, figX: 16, figW: 272 },
    };
    return t;
  })();

  /** The real zone as today's bands leave it. Identical in every variant: it is a fact about the picture. */
  const todayG = geom("today");
  const ZONE = { top: todayG.topH, bottom: H - todayG.bottomH };

  /** The analysis frame: 480 x 640, mapped onto the screen as OverlayView does (FILL_CENTER). Same in every variant. */
  const FRAME = (() => {
    const scale = Math.max(W / 480, H / 640);
    const w = 480 * scale, h = 640 * scale;
    return { srcW: 480, srcH: 640, scale, w, h, x: (W - w) / 2, y: (H - h) / 2, cropX: Math.max(0, (w - W) / 2), cropY: Math.max(0, (h - H) / 2) };
  })();

  /** The chrome share per variant, from geom(). opaque: what the bands cover; footprint: what the controls occupy. */
  function shares() {
    const pct = (dp) => 100 * dp / H;
    return ["two", "hybrid", "thin", "today", "none", "nopm"].map((v) => {
      const g = geom(v);
      const band = v !== "none" && v !== "nopm";
      const pill = g.pillH ? g.pillH + 8 : 0;
      return {
        variant: v, g,
        topDp: g.topH, bottomDp: g.bottomH,
        topPx: g.topH * PX, bottomPx: g.bottomH * PX,
        footprint: pct(g.topH + g.bottomH),
        opaque: band ? pct(g.topH + g.bottomH) : 0,
        withPill: pct(g.topH + g.bottomH + pill),
        picture: band ? 100 - pct(g.topH + g.bottomH) : 100,
        padded: g.bottomHPadded ? pct(g.topH + g.bottomHPadded) : null,
      };
    });
  }

  window.BANDS = { W, H, PX, LH, INSET, MEASURED, geom, ZONE, FRAME, shares, eyebrow, TWO };
})();
