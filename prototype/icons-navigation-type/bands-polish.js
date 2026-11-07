/* MOCK for #140: design explorations that polish "No bands", the variant the owner preferred on 2026-11-07.
   Only the bottom controls and the readout change between designs. The top row, the coaching pill, the zone corners
   and the analysis frame are drawn by bands.js base("none", ...) and are the same in every design.
   Rules every design keeps: − and + stay; END holds the left slot while a workout is live; 48 dp targets or larger;
   an 8 dp grid; glass with no blur; Phosphor; Inter; tabular figures; nothing inside the real zone (y < 560 dp).
   The readout rule the owner set: the count and its target ("3" and "5") are one size and one weight. They may step
   down in colour, never in size. Mock-only design values; nothing here is read from the app. */
(() => {
  "use strict";
  const W = 360, H = 780;
  const pos = (x, y, w, h, extra = "") => `left:${x}px;top:${y}px;width:${w}px;height:${h}px;${extra}`;
  const DASH = "—";

  // Rows shared by the designs, from the bottom up: 8 dp to the screen's edge, a 56 dp action row, 8 dp to the plate.
  const PAD = 8, ROW = 56, ROW_Y = H - PAD - ROW;   // 716
  const X3 = { end: 20, shutter: (W - 56) / 2, skip: W - 20 - 48 };                        // END, shutter, SKIP
  const X5 = { end: 20, minus: 86, shutter: (W - 56) / 2, plus: 226, skip: W - 20 - 48 };  // 18 dp between each

  const DESIGNS = [
    { id: "fraction", name: "Fraction",
      optimises: "The smallest change from the No bands you chose: same plate, same cluster, the target grown to the count's size.",
      arrangement: "As No bands: one plate, the words at the left and − count + at the right; END, shutter and SKIP below.",
      readout: "“3/5” on one line, count and target both 44 sp ExtraBold. The slash and the target step down in colour, not in size.",
      arrShort: "Cluster in the plate", roShort: "3/5, one line", countSp: 44 },
    { id: "of", name: "Of",
      optimises: "A count that reads as a phrase from across the room, with − and + as far apart as the plate allows.",
      arrangement: "− and + at the two ends of the plate, the readout centred between them; END, shutter and SKIP below.",
      readout: "“3 of 5” at 56 sp, count and target equal. The word “of” is the only small thing on the line, and it is a word, not a number.",
      arrShort: "Editors flank the plate", roShort: "3 of 5", countSp: 56 },
    { id: "pair", name: "Pair",
      optimises: "Editing reads as one control: − and + become one stepper, beside a readout that is all figure.",
      arrangement: "A readout plate at the left and a − | + stepper capsule (two 56 dp halves) at the right; END, shutter and SKIP below.",
      readout: "Count and target as a matched pair at 52 sp, split by a thin rule; the target one colour step down.",
      arrShort: "Plate + stepper capsule", roShort: "3 │ 5, ruled pair", countSp: 52 },
    { id: "segments", name: "Segments",
      optimises: "Progress you can see from farthest away: filled against empty needs no reading. One row holds all five controls.",
      arrangement: "One row: END, −, shutter, +, SKIP, 18 dp apart. Above it a plate with no buttons.",
      readout: "The count alone at 64 sp. The target is the number of segments under it, in groups of five, so there is no second number to size.",
      arrShort: "One row of five", roShort: "3 + segments", countSp: 64 },
    { id: "scoreboard", name: "Scoreboard",
      optimises: "One calm object instead of floating pieces, and the round promoted to a figure you can read at a glance.",
      arrangement: "One glass deck behind the whole bottom: the readout, a progress line, then END, −, shutter, +, SKIP.",
      readout: "“3/5” and the round as equal figures at 52 sp, each under its own eyebrow, split by a rule.",
      arrShort: "One deck, row of five", roShort: "3/5 │ round, equal", countSp: 52 },
    { id: "big", name: "Big type",
      optimises: "Legibility first: the largest count the bottom can hold, for an athlete at the far end of the room.",
      arrangement: "One row of five controls, as Segments; the plate above holds only type.",
      readout: "“3/5” centred at 72 sp, count and target equal; the movement and the round in one eyebrow above.",
      arrShort: "One row of five", roShort: "3/5, 72 sp centred", countSp: 72 },
  ];

  // The figures each state shows. digits 2 swaps in a two-digit set and round where the app can have them.
  function figures(S, state, digits) {
    const s = Object.assign({}, S[state]);
    if (digits === 2) {
      if (state === "running" || state === "paused") Object.assign(s, { ex: "SQUATS", round: 12, reps: "12", tgt: "/15", prog: 80 });
      if (state === "finished") Object.assign(s, { ex: "SQUATS", round: 24, reps: "12", tgt: "/15", prog: 80, status: "23 + 27 · 717 reps" });
    }
    return s;
  }

  // ------------------------------------------------------------------ pieces
  function kit(s, c, ico) {
    const none = s.reps === DASH;
    const T = s.tgt ? s.tgt.slice(1) : "";
    const countCol = none ? "var(--label-tertiary)" : s.repsAlert ? "var(--alert)" : "var(--label)";
    const fig = (t, sp, col, extra = "") => `<span class="pz-fig" style="font-size:${sp}px;color:${col};${extra}">${t}</span>`;
    const circ = (x, y, key, glyph, dim, tint, label, rel) =>
      `<div class="hit bz-circ" data-hit title="${label}" style="${rel ? "position:relative;width:48px;height:48px;flex:none;" : pos(x, y, 48, 48)}opacity:${dim};color:${tint || "var(--label)"}">${ico(key, glyph)}</div>`;
    const k = {
      none, T, countCol, fig,
      mv: s.ex.charAt(0) + s.ex.slice(1).toLowerCase(),        // "PULL-UPS" -> "Pull-ups"
      // count and target at one size and weight; the slash and the target step down in colour only
      frac: (sp) => fig(s.reps, sp, countCol) + (T && !none ? fig("/", sp, "var(--label-tertiary)") + fig(T, sp, "var(--label-secondary)") : ""),
      eyebrow: (center) => `<div class="pz-eb${center ? " c" : ""}"><span style="color:var(--label-secondary)">${s.ex}</span><span> · Round </span><span class="tnum" style="color:var(--label-secondary)">${s.round}</span></div>`,
      shutter: (x, y) => `<div class="hit bz-shutter" data-hit title="Shutter" style="${pos(x, y, 56, 56, `opacity:${c.shutter}`)}">${ico(s.shutter, 18)}</div>`,
      edge: (y) => `<div class="bz-track" data-chrome style="${pos(0, y, W, 3)}"><i style="width:${s.prog}%"></i></div>`,
      end: (x, y) => (c.end ? circ(x, y, "stop", 18, 1, "var(--alert)", "END") : ""),
      minus: (x, y, rel) => circ(x, y, "minus", 18, c.edit, null, "Minus one rep", rel),
      plus: (x, y, rel) => circ(x, y, "plus", 18, c.edit, null, "Plus one rep", rel),
      skip: (x, y) => circ(x, y, "skip", 20, c.skip, null, "SKIP"),
    };
    k.row3 = () => k.end(X3.end, ROW_Y + 4) + k.shutter(X3.shutter, ROW_Y) + k.skip(X3.skip, ROW_Y + 4);
    k.row5 = (y = ROW_Y) => k.end(X5.end, y + 4) + k.minus(X5.minus, y + 4) + k.shutter(X5.shutter, y) + k.plus(X5.plus, y + 4) + k.skip(X5.skip, y + 4);
    return k;
  }

  // n segments, one per rep of the set, in groups of five: 3 dp inside a group, 10 dp between groups.
  function segments(n, done, col, width, height) {
    const gaps = [];
    for (let i = 1; i < n; i++) gaps.push(i % 5 === 0 ? 10 : 3);
    const seg = (width - gaps.reduce((a, b) => a + b, 0)) / n;
    let x = 0, h = "";
    for (let i = 0; i < n; i++) {
      h += `<i style="left:${x.toFixed(2)}px;width:${seg.toFixed(2)}px;background:${i < done ? col : "var(--label-quaternary)"}"></i>`;
      x += seg + (gaps[i] || 0);
    }
    return `<div class="pz-segs" style="width:${width}px;height:${height}px">${h}</div>`;
  }

  const plate = (x, y, w, h, r, inner, cls = "") =>
    `<div class="bz-box pillglass pz-plate ${cls}" data-plate style="${pos(x, y, w, h, `border-radius:${r}px`)}">${inner}</div>`;
  const P = (name, dp) => [name, dp];

  // ------------------------------------------------------------------ the designs' bottoms
  // Each returns its html, y0 (the top of its bottom chrome, in dp) and the parts that add up to H - y0.
  const BOTTOM = {
    // 1. As No bands, with the target at the count's size.
    fraction(s, c, k) {
      const ph = 72, py = ROW_Y - 8 - ph, ey = py - 8 - 3;
      const html = k.edge(ey) + plate(16, py, W - 32, ph, 24,
        `<div class="pz-stack" style="left:16px">` +
          `<div class="pz-eb"><span>Round </span><span class="tnum" style="color:var(--label-secondary)">${s.round}</span></div>` +
          `<div class="pz-eb"><span style="color:var(--label-secondary)">${s.ex}</span></div></div>` +
        `<div class="pz-cluster" style="right:12px;top:12px;height:48px">${k.minus(0, 0, true)}` +
          `<div class="pz-figrow" data-fig style="padding:0 4px">${k.frac(44)}</div>${k.plus(0, 0, true)}</div>`) + k.row3();
      return { html, y0: ey, parts: [P("progress edge", 3), P("gap", 8), P("plate: 48 dp editors + 12 dp above and below", ph), P("gap", 8), P("action row", ROW), P("padding bottom", PAD)] };
    },
    // 2. − and + at the plate's two ends, "3 of 5" centred.
    of(s, c, k) {
      const ph = 96, py = ROW_Y - 8 - ph, ey = py - 8 - 3;
      const of = k.T && !k.none ? `<span class="pz-of">of</span>${k.fig(k.T, 56, "var(--label-secondary)")}` : "";
      const html = k.edge(ey) + plate(16, py, W - 32, ph, 28,
        `<div class="pz-abs" style="${pos(68, 14, W - 32 - 136, 14)}">${k.eyebrow(true)}</div>` +
        `<div class="pz-figrow c" data-fig style="${pos(68, 32, W - 32 - 136, 56)}">${k.fig(s.reps, 56, k.countCol)}${of}</div>`) +
        k.minus(16 + 12, py + 36) + k.plus(W - 16 - 12 - 48, py + 36) + k.row3();
      return { html, y0: ey, parts: [P("progress edge", 3), P("gap", 8), P("plate: 14 + eyebrow 14 + 4 + figures 56 + 8", ph), P("gap", 8), P("action row", ROW), P("padding bottom", PAD)] };
    },
    // 3. A readout plate and a separate − | + stepper capsule.
    pair(s, c, k) {
      const ph = 88, py = ROW_Y - 8 - ph, ey = py - 8 - 3, pw = W - 32 - 8 - 112;
      const pair = k.T && !k.none
        ? `${k.fig(s.reps, 52, k.countCol)}<span class="pz-rule"></span>${k.fig(k.T, 52, "var(--label-secondary)")}`
        : k.fig(s.reps, 52, k.countCol);
      const cy = py + 30 + (52 - 56) / 2;
      const half = (key, label) => `<div class="hit pz-half" data-hit title="${label}" style="opacity:${c.edit}">${key}</div>`;
      const html = k.edge(ey) + plate(16, py, pw, ph, 28,
        `<div class="pz-abs" style="${pos(16, 12, pw - 32, 14)}">${k.eyebrow(false)}</div>` +
        `<div class="pz-figrow" data-fig style="${pos(16, 30, pw - 32, 52)}">${pair}</div>`) +
        `<div class="bz-box pillglass pz-capsule" data-plate style="${pos(16 + pw + 8, cy, 112, 56)}">` +
          half(k.icoMinus, "Minus one rep") + `<span class="pz-capdiv"></span>` + half(k.icoPlus, "Plus one rep") + `</div>` + k.row3();
      return { html, y0: ey, parts: [P("progress edge", 3), P("gap", 8), P("plate: 12 + eyebrow 14 + 4 + figures 52 + 6 (stepper 56 inside it)", ph), P("gap", 8), P("action row", ROW), P("padding bottom", PAD)] };
    },
    // 4. The count alone, the target as segments; one row of five controls.
    segments(s, c, k) {
      const ph = 96, py = ROW_Y - 8 - ph;
      const n = k.T ? parseInt(k.T, 10) : 2, done = k.none ? 0 : Math.min(parseInt(s.reps, 10), n);
      const html = plate(16, py, W - 32, ph, 28,
        `<div class="pz-words" style="${pos(16, 12, 180, 56)}"><span class="pz-mv">${k.mv}</span><span class="pz-rd">Round <span class="tnum">${s.round}</span></span></div>` +
        `<div class="pz-figrow r" data-fig style="${pos(W - 32 - 16 - 120, 12, 120, 56)}">${k.fig(s.reps, 64, k.countCol, "line-height:56px")}</div>` +
        `<div class="pz-abs" style="${pos(16, 80, W - 64, 6)}">${segments(n, done, k.none ? "var(--label)" : k.countCol, W - 64, 6)}</div>`) + k.row5();
      return { html, y0: py, parts: [P("plate: 12 + count 56 + 12 + segments 6 + 10", ph), P("gap", 8), P("row of five", ROW), P("padding bottom", PAD)] };
    },
    // 5. One deck behind everything; the round as an equal figure.
    scoreboard(s, c, k) {
      const dh = 160, dy = H - PAD - dh, rowY = dy + 92;
      const html = `<div class="bz-box pillglass pz-plate pz-deck" data-plate style="${pos(8, dy, W - 16, dh, "border-radius:32px")}">` +
          `<div class="pz-score" style="${pos(20, 12, W - 16 - 40, 68)}">` +
            `<div class="pz-col"><div class="pz-eb"><span style="color:var(--label-secondary)">${s.ex}</span></div><div class="pz-figrow" data-fig>${k.frac(52)}</div></div>` +
            `<span class="pz-rule tall"></span>` +
            `<div class="pz-col r"><div class="pz-eb">Round</div><div class="pz-figrow r" data-fig>${k.fig(String(s.round), 52, "var(--label-secondary)")}</div></div>` +
          `</div>` +
          `<div class="bz-track pz-intrack pz-abs" style="${pos(20, 85, W - 16 - 40, 3)}"><i style="width:${s.prog}%"></i></div>` +
        `</div>` + k.row5(rowY);
      return { html, y0: dy, parts: [P("deck: 12 + readout 68 + 12 (progress line inside) + row of five 56 + 12", dh), P("padding bottom", PAD)] };
    },
    // 6. The biggest one-line count; one row of five controls.
    big(s, c, k) {
      const ph = 104, py = ROW_Y - 8 - ph, ey = py - 8 - 3;
      const html = k.edge(ey) + plate(16, py, W - 32, ph, 28,
        `<div class="pz-abs" style="${pos(16, 12, W - 64, 14)}">${k.eyebrow(true)}</div>` +
        `<div class="pz-figrow c" data-fig style="${pos(16, 32, W - 64, 64)}">${k.frac(72).replace(/font-size:72px;/g, "font-size:72px;line-height:64px;")}</div>`) + k.row5();
      return { html, y0: ey, parts: [P("progress edge", 3), P("gap", 8), P("plate: 12 + eyebrow 14 + 6 + figures 64 + 8", ph), P("gap", 8), P("row of five", ROW), P("padding bottom", PAD)] };
    },
  };

  /** The bottom of one design: its html, the top of its chrome (y0, dp) and the parts that make up its height. */
  function bottom(id, s, c, ico) {
    const k = kit(s, c, ico);
    k.icoMinus = ico("minus", 18); k.icoPlus = ico("plus", 18);
    return BOTTOM[id](s, c, k);
  }

  window.POLISH = { DESIGNS, figures, bottom, segments, W, H };
})();
