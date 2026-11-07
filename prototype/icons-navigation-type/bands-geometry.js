/* MOCK for #140: the camera screen's three band variants, in dp.
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

  const eyebrow = 11 * LH.b;                     // Cindy.Eyebrow, 11sp Bold
  const stat = Math.max(22, 14 * LH.sb);         // status row: minHeight 22dp, 14sp SemiBold

  /** The layout of one variant, in dp, from the camera screen's top-left. */
  function geom(variant) {
    const g = { variant, W, H };
    const compact = variant !== "today";
    // ---- top band -----------------------------------------------------------------
    if (!compact) {
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
    const gap = variant === "none" ? 8 : 0;                // glass() gives each a marginStart of 8
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
    } else {
      const K = Math.max(48, 44 * LH.xb);                  // reps autosize 24..44sp: 44sp ExtraBold sets the height
      const glass = variant === "none";
      const boxH = glass ? K + 8 : K;
      g.K = K; g.boxH = boxH;
      const gapTop = glass ? 6 : 4;
      g.bottomH = 3 + gapTop + boxH + 6 + 56 + 8;
      g.bottomParts = [["progress edge", 3], ["gap", gapTop], [glass ? "count pill (44 sp reps + 4 dp padding)" : "count row (reps 44 sp)", boxH], ["gap", 6], ["action row (shutter 56)", 56], ["padding bottom", 8]];
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
    return ["thin", "none", "today"].map((v) => {
      const g = geom(v);
      const band = v !== "none";
      const pill = g.pillH ? g.pillH + 8 : 0;
      return {
        variant: v, g,
        topDp: g.topH, bottomDp: g.bottomH,
        topPx: g.topH * PX, bottomPx: g.bottomH * PX,
        footprint: pct(g.topH + g.bottomH),
        opaque: band ? pct(g.topH + g.bottomH) : 0,
        withPill: pct(g.topH + g.bottomH + pill),
        picture: band ? 100 - pct(g.topH + g.bottomH) : 100,
      };
    });
  }

  window.BANDS = { W, H, PX, LH, INSET, MEASURED, geom, ZONE, FRAME, shares, eyebrow };
})();
