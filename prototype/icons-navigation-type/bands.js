/* MOCK for #140: draws the camera screen's band variants from bands-geometry.js: the ticket's three, the owner's rejected
   fourth (No bands without \u2212/+), the owner's hybrid of 2026-11-07 (Thin bands' top over today's bottom, bands-hybrid.js),
   and Two distances of 2026-11-12 (the hybrid's bands with the bottom band redrawn for the distance the athlete is at, bands-two.js).
   No bands and its six polish designs were rejected on 2026-11-07 and are kept under the view "Rejected".
   What goes where is read from prototype/hud-bands (HudVariants.kt, activity_main.xml, MainActivity.kt renderControls()).
   Not the app, not the in-app prototype. Phosphor icons, Inter, the app's tokens, the real camera capture. No blur. */
(() => {
  "use strict";
  const B = window.BANDS, D = window.ICON_DATA.sets.phosphor;
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => [...r.querySelectorAll(s)];
  const { W, H, LH } = B;

  const VARIANTS = [
    ["two", "Two distances", "The hybrid's bands, with the bottom band drawn for where the athlete is: a scoreboard at the bar (running), the controls forward at the phone (idle, setup, paused, finished)."],
    ["hybrid", "Thin top, today's bottom", "The owner's hybrid: Thin bands' one-row top with the camera switch, the coaching line as a pop-up on the picture, and today's bottom band exactly as it is."],
    ["thin", "Thin bands", "One top row with the clock and the icons; the coaching line is a pill on the picture; one row for the count, one for the actions."],
    ["none", "No bands", "Rejected by the owner on 2026-11-07, with all six of its polish designs. The picture fills the screen. Clock, icons, count and actions float on glass; drawn corners mark the real zone."],
    ["today", "Today's bands", "The baseline: two translucent bands, the coaching line inside the top one, round and count in the bottom one."],
    ["nopm", "No bands, no \u2212/+", "Rejected by the owner on 2026-11-07: \u2212 and + stay. Kept for the record: No bands with the two buttons gone and the round and count redrawn as type on one glass plate (readout A or B)."],
  ];
  const REJECTED = new Set(["none", "nopm"]);             // the owner turned these down; kept on the page, out of the default views
  const HY = window.HYBRID, TW = window.TWO;
  const MAIN = VARIANTS.filter(([v]) => !REJECTED.has(v));
  const STATES = [["idle", "Idle"], ["setup", "Setup"], ["running", "Running"], ["paused", "Paused"], ["finished", "Finished"]];

  // Copy and values as the prototype branch's MainActivity sets them in each state (example numbers where the app has live ones).
  const S = {
    idle:     { clock: "20:00", status: "Tap to set up", dot: "none", ex: "PULL-UPS", round: 1, reps: "0", tgt: "/5", prog: 0, shutter: "play" },
    setup:    { clock: "20:00", status: "Get in frame", dot: "none", ex: "SET UP", round: 1, reps: "—", tgt: "", prog: 0, shutter: "play" },
    running:  { clock: "17:42", status: "Counting…", dot: "ok", ex: "PULL-UPS", round: 2, reps: "3", tgt: "/5", prog: 60, shutter: "pause" },
    paused:   { clock: "17:42", status: "Paused", dot: "none", ex: "PULL-UPS", round: 2, reps: "3", tgt: "/5", prog: 60, shutter: "play" },
    finished: { clock: "00:00", status: "3 + 4 · 94 reps", dot: "none", ex: "PULL-UPS", round: 4, reps: "4", tgt: "/5", prog: 80, shutter: "again", repsAlert: true },
  };
  // CameraControls.of(state) as on the branch, with the camera switch as MainActivity.prototypeSwitchEnabled() has it.
  const CTRL = (st) => {
    const live = st === "running" || st === "paused";
    return {
      sw: st === "idle" || st === "paused" ? 1 : 0.3,        // enabled idle and paused; dimmed in setup, running, finished
      end: live,                                              // END holds the left slot while a workout is live; empty otherwise
      shutter: st === "setup" ? 0.3 : 1,
      edit: st === "running" ? 1 : 0.3,                       // -, + act only while the clock runs
      skip: st === "setup" || live ? 1 : 0.3,                 // a movement to leave in setup and in a live workout
    };
  };

  const AGAIN = { vb: "0 0 256 256", body: '<path d="M224,128a96,96,0,0,1-94.71,96H128A95.38,95.38,0,0,1,62.1,197.8a8,8,0,0,1,11-11.63A80,80,0,1,0,71.43,71.39a3.07,3.07,0,0,1-.26.25L44.59,96H72a8,8,0,0,1,0,16H24a8,8,0,0,1-8-8V56a8,8,0,0,1,16,0V85.8L60.25,60A96,96,0,0,1,224,128Z"/>' };
  const ico = (key, size) => {
    const d = key === "again" ? AGAIN : D[key];
    return `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="${d.vb}" fill="currentColor" aria-hidden="true">${d.body}</svg>`;
  };

  // Placeholder person: a hang from the bar, framed inside today's zone. Drawn, not captured.
  const PERSON = `
    <svg class="person" viewBox="0 0 360 780" width="360" height="780" aria-hidden="true">
      <line x1="40" y1="192" x2="320" y2="192" stroke="rgba(235,235,245,.38)" stroke-width="5" stroke-linecap="round"/>
      <g fill="rgba(235,235,245,.20)" stroke="rgba(235,235,245,.42)" stroke-width="1.2" stroke-linejoin="round">
        <circle cx="180" cy="236" r="19"/>
        <path d="M150 192 L160 192 L166 262 Q180 252 194 262 L200 192 L210 192 L206 268 Q206 284 200 300 L198 372 L206 520 L186 522 L180 408 L174 522 L154 520 L162 372 L160 300 Q154 284 154 268 Z"/>
      </g>
    </svg>
    <div class="ph-label">PLACEHOLDER silhouette, not the camera. The real capture's lens was covered.</div>`;

  const pos = (x, y, w, h, extra = "") => `left:${x}px;top:${y}px;width:${w}px;height:${h}px;${extra}`;
  const f1 = (n) => Math.round(n * 100) / 100;

  // The layers every variant shares above the bottom controls: picture, person, zone corners, frame, bands, top row, coaching line.
  // The polish designs (bands-polish.js) draw these through base("none", ...) so they are identical in every design.
  function base(variant, s, c, o) {
    const g = B.geom(variant);
    const glass = variant === "none" || variant === "nopm", compact = g.thinTop;
    let h = "";
    // picture: full screen in every variant (PreviewView and OverlayView are match_parent, so the analysis frame is the same)
    h += `<div class="bz-pic"></div>${o.lift ? '<div class="bz-lift"></div>' : ""}`;
    if (o.person) h += PERSON;
    if (glass) h += zoneCorners();
    if (o.frame) h += frameOutline();

    // ---- bands (backgrounds) ----
    if (!glass) {
      h += `<div class="bz-band top" style="${pos(0, 0, W, g.topH)}"></div>`;
      h += `<div class="bz-band bot" style="${pos(0, g.y0, W, g.bottomH)}"></div>`;
    }
    // ---- top row ----
    const rowMid = g.rowTop + g.rowH / 2;
    const clockPx = compact ? 28 : 30;
    if (glass) {
      h += `<div class="bz-pillglass" style="${pos(20, g.rowTop, 0, g.rowH, "width:auto;padding:0 16px;")}"><span class="t-metric-m tnum" style="font-size:${clockPx}px">${s.clock}</span></div>`;
    } else {
      h += `<div class="bz-clock t-metric-m tnum" style="left:20px;top:${f1(rowMid - 24)}px;height:48px;line-height:48px;font-size:${clockPx}px">${s.clock}</div>`;
    }
    const icon = (x, key, size, tint, dim, id, label) =>
      `<div class="hit bz-icon ${glass ? "glassbtn" : ""} ${id}" style="${pos(x, g.iconTop, 44, 40, `color:${tint};opacity:${dim};`)}" title="${label}">${ico(key, size)}</div>`;
    h += icon(g.switchX, "flip", 18, "var(--label)", c.sw, "sw", "Switch camera: enabled in idle and paused, dimmed in setup, running and finished");
    h += icon(g.recX, "rec", 18, "var(--label-secondary)", 1, "rec", "REC");
    h += icon(g.menuX, "menu", 18, "var(--label-secondary)", 1, "menu", "MENU");
    if (o.mark) h += `<div class="bz-mark" style="${pos(g.switchX - 3, g.iconTop - 3, 50, 46)}"><i>camera switch</i></div>`;

    // ---- coaching line ----
    // the dot as MainActivity.statusDot() paints it: state_ok, state_alert, or label_tertiary for neutral
    const dotCol = s.dot === "ok" ? "var(--ok)" : s.dot === "alert" ? "var(--alert)" : "var(--label-tertiary)";
    const dot = `<span class="bz-dot" style="background:${dotCol}"></span>`;
    const line = `<span class="t-headline bz-line" style="font-size:14px">${s.status}</span>`;
    if (!compact) {
      h += `<div class="bz-status" style="${pos(0, g.statusTop, W, g.statusH)}">${dot}${line}</div>`;
    } else {
      // Thin bands and No bands: 8 dp under the top band. The hybrid: where the chosen pop-up option puts it.
      const hy = variant === "hybrid", popup = o.popup || HY.PICK;
      const y = hy ? HY.pillY(g, popup) : g.pillTop;
      const toast = hy && popup === "toast" && !s.stays;
      if (!o.nopill) h += `<div class="bz-statuswrap" style="top:${f1(y)}px"><div class="bz-pill${toast ? " toast" : ""}" data-pill style="height:${f1(g.pillH)}px">${dot}${line}</div></div>`;
    }
    return h;
  }

  /** The coaching line shown in a state: the one picked on the page for the current state, the first otherwise. */
  function lineOf(state) {
    const L = HY.LINES[state], i = state === st.state && st.view !== "grid" ? Math.min(st.line || 0, L.length - 1) : 0;
    return L[i];
  }

  // ---- Two distances (bands-two.js): what the scoreboard counts, and the phone drawn in a state ----
  // The set the page shows while running or paused. "Figures" resets it; "Bank a rep" and auto-play move it on.
  const simFor = (fig) => (fig === "2" ? { mv: 2, round: 12, count: 12 } : { mv: 0, round: 2, count: 3 });
  let sim = null;

  /** What the Two distances readout shows in a state: the app's values where the hybrid has them, the set otherwise. */
  function twoModel(state, o) {
    const L = lineOf(state), mv = TW.MOVES[sim.mv];
    const m = { shutter: S[state].shutter };
    if (state === "idle") return Object.assign(m, { count: 0, target: TW.MOVES[0].n, name: TW.MOVES[0].name, round: 1, receded: true });
    if (state === "setup") return Object.assign(m, L.fig ? { count: L.fig.reps, target: 2 } : { count: "\u2014", target: null, receded: true }, { name: "Setup check", round: null });
    if (state === "finished") return Object.assign(m, o.fig === "2" ? { count: 12, target: 15, name: "Squats", round: 12 } : { count: 4, target: 5, name: "Pull-ups", round: 4 }, { alert: true });
    Object.assign(m, { count: sim.count, target: mv.n, name: mv.name, round: sim.round });
    if (state === "running" && o.still === "pulse" && sim.count > 0) Object.assign(m, { prev: sim.count - 1, still: "pulse" });
    if (state === "running" && o.still === "takeover") {
      const nx = TW.MOVES[(sim.mv + 1) % 3];
      Object.assign(m, { count: 0, target: nx.n, name: nx.name, round: sim.round + (sim.mv === 2 ? 1 : 0), taking: nx });
    }
    return m;
  }

  function renderTwo(state, o) {
    const g = B.geom("two"), c = CTRL(state), L = lineOf(state);
    // The top band, the picture and the pop-up are the hybrid's, pop-up A. In idle the one line is under the shutter.
    const s = Object.assign({}, S[state], { status: L.text, dot: L.dot, stays: true });
    return base("two", s, c, Object.assign({}, o, { popup: HY.PICK, nopill: state === "idle" })) + TW.bottom(g, state, twoModel(state, o), c, ico, o);
  }

  function render(variant, state, o) {
    if (variant === "two") return renderTwo(state, o);
    const g = B.geom(variant), c = CTRL(state), L = lineOf(state);
    const s = Object.assign({}, S[state], { status: L.text, dot: L.dot, stays: HY.stays(state, L) }, L.fig || {}, o.figs || {});
    const glass = variant === "none" || variant === "nopm", compact = g.thinBottom;
    let h = base(variant, s, c, o);

    // ---- bottom: progress edge ----
    h += `<div class="bz-track" style="${pos(0, g.y0, W, 3)}"><i style="width:${s.prog}%"></i></div>`;

    const repsCol = s.repsAlert ? "var(--alert)" : "var(--label)";
    const eb = (t, col) => `<span class="t-eyebrow" style="color:${col || "var(--label-tertiary)"}">${t}</span>`;
    const circ = (x, y, size, key, glyph, dim, tint) =>
      `<div class="hit bz-circ" style="${pos(x, y, size, size, `opacity:${dim};color:${tint || "var(--label)"}`)}">${ico(key, glyph)}</div>`;

    if (!compact) {
      // round on the left, movement on the right
      h += `<div class="bz-eyebrow" style="${pos(20, g.eyebrowTop, W - 40, g.eyebrowH)}">${eb("Round")}<span class="t-eyebrow tnum" style="color:var(--label-secondary);margin-left:6px;flex:1">${s.round}</span>${eb(s.ex, "var(--label-secondary)")}</div>`;
      const cy = g.countTop + (g.countH - 52) / 2;
      h += circ(20, cy, 52, "minus", 22, c.edit);
      h += circ(W - 20 - 52, cy, 52, "plus", 22, c.edit);
      // Today's readout: reps 56 sp, target 30 sp. The hybrid's optional toggle sets the target at the count's 56 sp, one weight,
      // stepping down in colour only (the slash tertiary, the target secondary), the rule the owner set for the polish round.
      const same = variant === "hybrid" && o.equal;
      const tgt = !s.tgt ? "" : same
        ? `<span class="t-metric-xl" data-eqfig style="font-size:56px;color:var(--label-tertiary)">/</span><span class="t-metric-xl" data-eqfig style="font-size:56px;color:var(--label-secondary)">${s.tgt.slice(1)}</span>`
        : `<span class="tgt" style="font-size:30px">${s.tgt}</span>`;
      h += `<div class="bz-count${same ? " same" : ""}" data-count style="${pos(72, g.countTop, W - 144, g.countH)}"><span class="t-metric-xl" data-eqfig style="font-size:56px;color:${repsCol}">${s.reps}</span>${tgt}</div>`;
    } else if (variant === "nopm") {
      h += readout(g, s, repsCol, o.readout);
    } else {
      const bx = g.boxX, by = g.boxTop, bw = g.boxW, bh = g.boxH;
      h += `<div class="bz-box ${glass ? "pillglass" : ""}" style="${pos(bx, by, bw, bh)}">`;
      // left: round line over movement line
      const padV = glass ? 4 : 0;
      h += `<div class="bz-stack" style="left:${g.boxPad[0]}px;top:${f1((bh - g.stackH) / 2)}px;height:${f1(g.stackH)}px">` +
        `<div class="ln">${eb("Round")}<span class="t-eyebrow tnum" style="color:var(--label-secondary);margin-left:5px">${s.round}</span></div>` +
        `<div class="ln" style="margin-top:2px">${eb(s.ex, "var(--label-secondary)")}</div></div>`;
      // right: - number +, one cluster (undo 48, number with 6 dp either side, add 48)
      h += `<div class="bz-cluster" style="right:${g.boxPad[1]}px;top:${padV}px;height:${f1(g.K)}px">` +
        `<div class="hit bz-circ" style="position:relative;width:48px;height:48px;opacity:${c.edit}">${ico("minus", 18)}</div>` +
        `<div class="bz-reps"><span class="t-metric-xl" style="font-size:44px;color:${repsCol}">${s.reps}</span><span class="tgt" style="font-size:24px">${s.tgt}</span></div>` +
        `<div class="hit bz-circ" style="position:relative;width:48px;height:48px;opacity:${c.edit}">${ico("plus", 18)}</div></div>`;
      h += `</div>`;
    }

    // ---- action row ----
    const ay = g.actionTop, ah = g.actionH;
    if (c.end) h += circ(g.edX, ay + (ah - g.side) / 2, g.side, "stop", compact ? 18 : 22, 1, "var(--alert)");
    const sh = g.shutter, shGlyph = compact ? 18 : 30;       // padding 19dp in both: the glyph shrinks with the 56dp shutter
    h += `<div class="hit bz-shutter" style="${pos((W - sh) / 2, ay + (ah - sh) / 2, sh, sh, `opacity:${c.shutter}`)}">${ico(s.shutter, shGlyph)}</div>`;
    h += circ(W - 20 - g.side, ay + (ah - g.side) / 2, g.side, "skip", compact ? 20 : 24, c.skip);
    return h;
  }

  // ---- the fourth variant's readout: one glass plate, type carries the hierarchy, tabular figures throughout ----
  const sentence = (t) => t.charAt(0) + t.slice(1).toLowerCase();                  // "PULL-UPS" -> "Pull-ups", "SET UP" -> "Set up"
  const target = (s) => (s.tgt ? parseInt(s.tgt.slice(1), 10) : 2);                // setup counts the two calibration reps
  const repsDone = (s) => (s.reps === "\u2014" ? 0 : parseInt(s.reps, 10));

  // The set as n segments, done of them filled: the target is the number of segments, so it needs no number.
  function ring(n, done, col, size, stroke) {
    const c = size / 2, r = c - stroke / 2, gapDeg = n <= 6 ? 12 : n <= 10 ? 9 : 7, seg = 360 / n - gapDeg;
    const pt = (deg) => { const a = (deg - 90) * Math.PI / 180; return [c + r * Math.cos(a), c + r * Math.sin(a)]; };
    let d = "";
    for (let i = 0; i < n; i++) {
      const a0 = i * 360 / n + gapDeg / 2, a1 = a0 + seg, [x0, y0] = pt(a0), [x1, y1] = pt(a1);
      d += `<path d="M${f1(x0)} ${f1(y0)}A${r} ${r} 0 0 1 ${f1(x1)} ${f1(y1)}" stroke="${i < done ? col : "var(--label-quaternary)"}"/>`;
    }
    return `<svg width="${size}" height="${size}" viewBox="0 0 ${size} ${size}" fill="none" stroke-width="${stroke}" aria-hidden="true">${d}</svg>`;
  }

  function readout(g, s, repsCol, which) {
    const plate = pos(g.boxX, g.boxTop, g.boxW, g.boxH);
    if (which === "B") {
      const n = target(s), done = Math.min(repsDone(s), n);
      return `<div class="bz-box pillglass rd rd-b" style="${plate}">` +
        `<span class="rd-b-ex">${sentence(s.ex)}</span>` +
        `<div class="rd-b-ring">${ring(n, done, repsCol, 68, 6)}<span class="t-metric-xl rd-b-n" style="font-size:${String(s.reps).length > 1 ? 30 : 38}px;color:${s.reps === "\u2014" ? "var(--label-tertiary)" : repsCol}">${s.reps}</span></div>` +
        `<div class="rd-b-rd"><span class="t-eyebrow">Round</span><span class="t-metric-m tnum" style="color:var(--label-secondary)">${s.round}</span></div></div>`;
    }
    return `<div class="bz-box pillglass rd rd-a" style="${plate}">` +
      `<div class="rd-a-n"><span class="t-metric-xl" style="font-size:64px;color:${s.reps === "\u2014" ? "var(--label-tertiary)" : repsCol}">${s.reps}</span><span class="tgt" style="font-size:28px">${s.tgt}</span></div>` +
      `<div class="rd-a-w"><span class="rd-a-ex">${sentence(s.ex)}</span><span class="rd-a-rd tnum">Round ${s.round}</span></div></div>`;
  }

  // The real zone as today's bands leave it, drawn as ZoneCornersView does: 12 dp inset, 30 dp arms, 3 dp strokes, white at 84%.
  function zoneCorners() {
    const z = B.ZONE, i = 12, a = 30, l = i, r = W - i, t = z.top + i, b = z.bottom - i;
    const d = `M${l} ${t + a}V${t}H${l + a} M${r - a} ${t}H${r}V${t + a} M${l} ${b - a}V${b}H${l + a} M${r - a} ${b}H${r}V${b - a}`;
    return `<svg class="corners" viewBox="0 0 ${W} ${H}" width="${W}" height="${H}" aria-hidden="true"><path d="${d}" fill="none" stroke="rgba(255,255,255,.84)" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/></svg>`;
  }

  // The analysis frame, 480 x 640 mapped FILL_CENTER: one rectangle, the same in every variant. Mock-only outline.
  function frameOutline() {
    const f = B.FRAME;
    return `<svg class="frame" viewBox="0 0 ${W} ${H}" width="${W}" height="${H}" aria-hidden="true">
      <rect x="${f.x}" y="${f.y}" width="${f.w}" height="${f.h}" fill="none" stroke="#ff9f0a" stroke-width="2" stroke-dasharray="7 5"/>
      <rect x="1" y="1" width="${W - 2}" height="${H - 2}" fill="none" stroke="#ff9f0a" stroke-width="2" stroke-dasharray="7 5"/>
    </svg>`;
  }

  // ------------------------------------------------------------------ page
  const st = { view: "hybrid", arr: TW.PICK, fig: "1", still: "", auto: false, rm: false, rej: "polish", state: "running", variant: "hybrid", readout: "A", digits: "1", pzsize: "fit", popup: HY.PICK, line: 0, equal: false, hold: false, foot: true, frame: true, person: true, lift: true, mark: true, targets: false };
  try { Object.assign(st, JSON.parse(decodeURIComponent(location.hash.slice(1)) || "{}")); } catch (e) { /* ignore */ }
  // links made before No bands was rejected: its views now live under "Rejected"
  if (st.view === "polish" || st.view === "cmp") { st.rej = st.view === "polish" ? "polish" : "nopm"; st.view = "rejected"; }
  sim = simFor(st.fig);
  const persist = () => { try { history.replaceState(null, "", "#" + encodeURIComponent(JSON.stringify(st))); } catch (e) { /* file:// */ } };

  const phone = (variant, state, scale, label, readout) => {
    const inner = `<div class="phone type-inter ${st.targets ? "show-targets" : ""} ${st.hold ? "hold" : ""}" style="zoom:${scale}">${render(variant, state, Object.assign({}, st, { readout: readout || st.readout }))}</div>`;
    return `<div class="shell" style="width:${f1(W * scale)}px;height:${f1(H * scale)}px" role="img" aria-label="${label}">${inner}</div>`;
  };
  const pct = (n) => n.toFixed(1) + " %";
  const shareOf = (v) => B.shares().find((s) => s.variant === v);

  function pane(v, state, scale, readout) {
    const [, name, what] = VARIANTS.find((x) => x[0] === v);
    const ro = v === "nopm" ? (readout || st.readout) : null;
    const sh = shareOf(v);
    const num = v === "none" || v === "nopm"
      ? `opaque chrome <b>0 %</b> · controls footprint <b>${pct(sh.footprint)}</b>`
      : v === "hybrid" || v === "thin" || v === "two"
        ? `chrome <b>${pct(sh.opaque)}</b> · with the pop-up ${pct(sh.withPill)} · picture ${pct(sh.picture)}`
        : `chrome <b>${pct(sh.opaque)}</b> · picture ${pct(sh.picture)}`;
    const rej = REJECTED.has(v) ? ' <span class="badge rejected">rejected</span>' : "";
    return `<div class="pane${REJECTED.has(v) ? " rejected" : ""}"><p class="cap"><b>${name}${ro ? ", readout " + ro : ""}</b> <span class="badge mock">mock</span>${rej}</p>${phone(v, state, scale, name + ", " + state + (ro ? ", readout " + ro : ""), ro)}<p class="note">${what}</p><p class="note num">${num}</p></div>`;
  }

  function renderStage() {
    const stage = $("#stage");
    $$("[data-view]").forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.view === st.view)));
    $$("[data-state]").forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.state === st.state)));
    $$("[data-variant]").forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.variant === st.variant)));
    $$("[data-readout]").forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.readout === st.readout)));
    $$("[data-rej]").forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.rej === st.rej)));
    $$("[data-popup]").forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.popup === st.popup)));
    const polishOn = st.view === "rejected" && st.rej === "polish";
    const hyOn = st.view === "hybrid" || (st.view === "big" && st.variant === "hybrid");
    $("#grp-rej").hidden = st.view !== "rejected";
    $$(".hy-only").forEach((el) => { el.hidden = !hyOn; });
    $("#seg-line").innerHTML = HY.LINES[st.state].map((L, i) => `<button data-line="${i}" aria-pressed="${String(i === Math.min(st.line, HY.LINES[st.state].length - 1))}" title="${L.src.replace(/"/g, "&quot;")}">${L.text}</button>`).join("");
    $("#grp-line").hidden = st.view === "grid" || polishOn;
    $("#grp-readout").hidden = !(st.view === "big" && st.variant === "nopm");
    $("#grp-variant").hidden = st.view !== "big";
    $$("[data-digits]").forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.digits === st.digits)));
    $$("[data-pzsize]").forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.pzsize === st.pzsize)));
    $("#grp-state").hidden = st.view === "grid";
    $$(".pz-only").forEach((el) => { el.hidden = !polishOn; });
    if (st.view === "hybrid") {
      stage.className = "stage hy";
      stage.innerHTML = hybridStage();
      measureHybrid();
    } else if (polishOn) {
      stage.className = "stage polish";
      stage.innerHTML = rejectedBanner() + polishStage();
      measurePolish();
    } else if (st.view === "rejected") {
      stage.className = "stage rejwrap";
      stage.innerHTML = rejectedBanner() + `<div class="stage">${pane("none", st.state, 1) + pane("nopm", st.state, 1, "A") + pane("nopm", st.state, 1, "B")}</div>`;
    } else if (st.view === "side") {
      stage.className = "stage";
      stage.innerHTML = MAIN.map(([v]) => pane(v, st.state, 1)).join("");
    } else if (st.view === "big") {
      const sc = Math.max(0.9, Math.min(1.7, (innerHeight - 210) / H));
      stage.className = "stage big";
      stage.innerHTML = pane(st.variant, st.state, sc) + `<div class="bigside">${st.variant === "hybrid" ? popupCards() : ""}${sharesTable()}${statesNote()}</div>`;
      if (st.variant === "hybrid") measureHybrid();
    } else {
      stage.className = "stage grid";
      const sc = 0.62;
      stage.innerHTML = `<div class="gridwrap"><div class="gh"></div>${STATES.map(([k, n]) => `<div class="gh">${n}</div>`).join("")}` +
        MAIN.map(([v, name]) => `<div class="gh row">${name}</div>` + STATES.map(([k]) => `<div>${phone(v, k, sc, name + ", " + k)}</div>`).join("")).join("") + `</div>`;
    }
    persist();
  }

  // ------------------------------------------------------------------ Thin top, today's bottom (bands-hybrid.js)
  const STATE_NAME = Object.fromEntries(STATES);
  const dp1 = (n) => f1(n).toFixed(1).replace(/\.0$/, "");

  function rejectedBanner() {
    return `<div class="rejbanner"><b>Rejected on 2026-11-07.</b> No bands, all six of its polish designs, and No bands without \u2212/+ (\u2212 and + stay). Kept here for the record, out of the default views. The page now opens on <b>Thin top, today's bottom</b>.</div>`;
  }

  /** Where each pop-up option lands, against the bands, the real zone and the placeholder athlete. In dp. */
  function popupGeometry(id) {
    const g = B.geom("hybrid"), Z = B.ZONE, A = HY.ATHLETE;
    const y0 = HY.pillY(g, id), y1 = y0 + g.pillH;
    const zone = Math.max(0, Math.min(y1, Z.bottom) - Math.max(y0, Z.top));
    const toZone = zone > 0 ? 0 : y0 >= Z.bottom ? y0 - Z.bottom : Z.top - y1;
    const body = Math.max(0, Math.min(y1, A.bottom) - Math.max(y0, A.top));
    const bar = A.barY >= y0 && A.barY <= y1;
    return { y0, y1, zone, toZone, body, bar, inBand: y0 < g.topH - 0.5 || y1 > g.y0 + 0.5 };
  }

  function popupCards() {
    const L = lineOf(st.state), keep = HY.stays(st.state, L);
    const cards = HY.POPUPS.map((p) => {
      const q = popupGeometry(p.id);
      const where = q.zone > 0
        ? `<span class="bad">${dp1(q.zone)} dp inside the real zone</span>${q.body > 0 ? `, over the athlete's lowest ${dp1(q.body)} dp (the feet)` : ""}`
        : `<span class="good">${dp1(q.toZone)} dp clear of the real zone</span>, ${dp1(HY.ATHLETE.barY - q.y1)} dp above the bar`;
      const now = p.id === "toast" ? (keep ? "This line stays: it asks for something, or names a state." : `This line fades: it is a running line with a ${L.dot === "ok" ? "green" : "grey"} dot.`) : "";
      return `<button class="hy-card" data-popup="${p.id}" aria-pressed="${String(st.popup === p.id)}"><span class="hy-name"><b>${p.name}</b>${p.id === HY.PICK ? '<span class="badge pick">pick</span>' : ""}</span>` +
        `<span>${p.where}</span><span>${p.life}${now ? " " + now : ""}</span>` +
        `<span class="num">y ${dp1(q.y0)} to ${dp1(q.y1)} dp · ${where}</span></button>`;
    }).join("");
    return `<div class="hy-cards"><p class="hy-cap">The coaching pop-up: three options (click one)</p>${cards}<p class="hy-why">${pickWhy()}</p></div>`;
  }

  function pickWhy() {
    const a = popupGeometry("top"), b = popupGeometry("bottom"), g = B.geom("hybrid");
    return `<b>Pick: A, the pill at the top.</b> It sits at y ${dp1(a.y0)} to ${dp1(a.y1)} dp, inside the ${dp1(B.ZONE.top)} dp that today's top band already covers, ` +
      `${dp1(a.toZone)} dp clear of the real zone and ${dp1(HY.ATHLETE.barY - a.y1)} dp above the bar, so the picture the athlete frames themselves in loses nothing to it. ` +
      `It is where Thin bands puts it, so the hybrid's top is Thin bands' top as built. ` +
      `B lands ${dp1(b.zone)} dp inside the real zone's lower edge, over the feet and, for push-ups and squats, the floor the counter reads. ` +
      `C clears only the strip above the zone, and only while counting, where the dot (would this rep count) is the line's main job; a hint read once and gone is easy to miss mid-rep from 2 m.`;
  }

  function hybridNumbers() {
    const rows = ["today", "hybrid", "thin"].map((v) => {
      const sh = shareOf(v), nm = VARIANTS.find((x) => x[0] === v)[1];
      const pill = v === "today" ? "in the band" : pct(sh.withPill);
      return `<tr${v === "hybrid" ? ' class="hy-me"' : ""}><th>${nm}</th><td class="num">${dp1(sh.topDp)} dp · ${sh.topPx.toFixed(0)} px</td><td class="num">${dp1(sh.bottomDp)} dp · ${sh.bottomPx.toFixed(0)} px</td>` +
        `<td class="num"><b>${pct(sh.opaque)}</b></td><td class="num">${pill}</td><td class="num" data-hyarea="${v}">${v === "today" ? "n/a" : "…"}</td><td class="num">${pct(sh.picture)}</td></tr>`;
    }).join("");
    const hy = shareOf("hybrid"), td = shareOf("today");
    return `<table class="tbl"><caption>Chrome share, 1080 x 2340</caption><thead><tr><th></th><th>top band</th><th>bottom band</th><th>chrome (bands)</th><th>+ pop-up, height</th><th>pop-up, area</th><th>picture</th></tr></thead><tbody>${rows}</tbody></table>` +
      `<p class="pz-note">The hybrid's bands take <b>${pct(hy.opaque)}</b>: the thin top ${dp1(hy.topDp)} dp plus today's bottom ${dp1(hy.bottomDp)} dp, against today's ${pct(td.opaque)}. ` +
      `Counted as a band, the way the branch's HUDMEASURE log counts it (the pill's ${dp1(hy.g.pillH)} dp and its 8 dp margin added to the height), the share with the pop-up is <b>${pct(hy.withPill)}</b>. ` +
      `The pill is not a band, though: it is one line wide, so its area is the fairer number, measured here per line from the rendered pill. With option C the share falls back to ${pct(hy.opaque)} whenever a running line has faded.</p>`;
  }

  function linesTable() {
    const rows = STATES.map(([k, n]) => HY.LINES[k].map((L, i) =>
      `<tr${k === st.state && i === Math.min(st.line, HY.LINES[k].length - 1) ? ' class="hy-me"' : ""}><th>${i === 0 ? n : ""}</th><td><span class="bz-dot inl" style="background:${L.dot === "ok" ? "var(--ok)" : L.dot === "alert" ? "var(--alert)" : "var(--label-tertiary)"}"></span>${L.text}</td>` +
      `<td>${HY.stays(k, L) ? "stays" : "fades after " + HY.TOAST.holdMs / 1000 + " s"}</td><td data-fitline="${k}:${i}">…</td><td class="src">${L.src}</td></tr>`).join("")).join("");
    return `<table class="tbl"><caption>The coaching lines the pop-up carries, from prototype/hud-bands</caption><thead><tr><th></th><th>line</th><th>under C</th><th>one line?</th><th>where the app sets it</th></tr></thead><tbody>${rows}</tbody></table>` +
      `<p class="pz-note">The app sets the line in one line (<code>maxLines="1"</code>, no ellipsis), so a line wider than its pill is cut at the edge. The mock cuts it the same way and the "one line?" column measures it, in the pill and in today's band.</p>`;
  }

  function hybridStage() {
    const gap = 28, cw = document.documentElement.clientWidth;
    const sc = Math.max(0.5, Math.min(1, (cw - 32 - 2 * gap) / 3 / W));
    const big = Math.max(0.9, Math.min(1.35, (innerHeight - 150) / H));
    const L = lineOf(st.state);
    return `<div class="hy-intro"><b>Thin top, today's bottom.</b> The owner's hybrid of 2026-11-07. The top band is Thin bands' one row: the clock, then the camera switch, REC and MENU. ` +
      `The coaching line leaves the band and becomes a pop-up on the picture. The bottom band is today's, exactly. The analysis frame is the same rectangle in all three phones.</div>` +
      `<h3 class="hy-h">${STATE_NAME[st.state]} · \u201c${L.text}\u201d · pop-up ${HY.POPUPS.find((p) => p.id === st.popup).name.slice(0, 2)} ${st.equal ? "· count and target at one size" : ""}</h3>` +
      `<div class="hy-row" style="gap:${gap}px">${pane("today", st.state, sc)}${pane("hybrid", st.state, sc)}${pane("thin", st.state, sc)}</div>` +
      `<h3 class="hy-h">The hybrid, one big phone</h3>` +
      `<div class="stage big">${pane("hybrid", st.state, big)}<div class="bigside">${popupCards()}${hybridNumbers()}${linesTable()}<p class="pz-check" id="hycheck">Hybrid self-check: running…</p></div></div>`;
  }

  function measureHybrid() {
    const f = document.fonts;
    Promise.all(["800 100px CindyInter", "600 100px CindyInter"].map((x) => f.load(x))).then(() => f.ready).then(hybridCheck, hybridCheck);
  }

  // Render the hybrid off-screen in every state, with every line and every pop-up option, and check what a reviewer would
  // catch: a pill on a band or off the screen, a line cut at the pill's edge, an analysis frame that differs between the
  // three phones, and, with the one-size toggle, figures of unequal size or wider than the space between \u2212 and +.
  function hybridCheck() {
    const box = document.createElement("div");
    box.className = "pz-offscreen";
    const saved = { line: st.line, state: st.state, popup: st.popup, equal: st.equal };
    const jobs = [];
    STATES.forEach(([k]) => HY.LINES[k].forEach((L, i) => {
      HY.POPUPS.forEach((p) => jobs.push({ v: "hybrid", k, i, popup: p.id }));
      jobs.push({ v: "today", k, i, popup: "top" });
    }));
    [["running", { reps: "3", tgt: "/5" }], ["running", { reps: "12", tgt: "/15" }], ["finished", { reps: "12", tgt: "/15" }], ["setup", null]].forEach(([k, figs]) =>
      jobs.push({ v: "hybrid", k, i: k === "setup" ? 2 : 0, popup: "top", equal: true, figs }));
    box.innerHTML = jobs.map((j) => {
      Object.assign(st, { state: j.k, line: j.i, popup: j.popup, equal: !!j.equal });
      const o = Object.assign({}, st, { figs: j.figs || undefined, frame: true });
      return `<div class="shell"><div class="phone type-inter">${render(j.v, j.k, o)}</div></div>`;
    }).join("");
    Object.assign(st, saved);
    document.body.appendChild(box);
    const g = B.geom("hybrid"), problems = [], fit = {}, areas = {}, frames = new Set();
    $$(".shell", box).forEach((shell, n) => {
      const j = jobs[n], ph = $(".phone", shell), pr = ph.getBoundingClientRect();
      const rect = (el) => { const r = el.getBoundingClientRect(); return { x: r.left - pr.left, y: r.top - pr.top, w: r.width, h: r.height }; };
      const L = HY.LINES[j.k][j.i], tag = `${j.v}, ${j.k}, \u201c${L.text}\u201d${j.v === "hybrid" ? ", " + j.popup : ""}`;
      const fr = $("svg.frame", ph); if (fr) frames.add(fr.innerHTML.replace(/\s+/g, " "));
      const ln = $(".bz-line", ph), cut = ln && ln.scrollWidth > ln.clientWidth + 0.5;
      const key = `${j.k}:${j.i}`;
      fit[key] = fit[key] || {};
      if (j.v === "today") fit[key].band = !cut;
      else if (j.popup === "top" && !j.equal) fit[key].pill = !cut;
      if (j.v === "hybrid" && !j.equal) {
        const p = rect($("[data-pill]", ph));
        if (j.popup !== "bottom" && p.y < g.topH - 0.5) problems.push(`${tag}: the pill overlaps the top band`);
        if (p.y + p.h > g.y0 + 0.5) problems.push(`${tag}: the pill overlaps the bottom band`);
        if (p.x < -0.5 || p.x + p.w > W + 0.5) problems.push(`${tag}: the pill leaves the screen`);
        if (j.popup === "top") (areas[j.k + ":" + j.i] = 100 * p.w * p.h / (W * H));
      }
      if (j.equal) {
        const spans = $$("[data-eqfig]", ph), slot = rect($("[data-count]", ph));
        const sizes = new Set(spans.map((sp) => getComputedStyle(sp).fontSize));
        if (sizes.size > 1) problems.push(`${tag}, one size: the count and its target differ (${[...sizes].join(", ")})`);
        const rs = spans.map(rect), x0 = Math.min(...rs.map((r) => r.x)), x1 = Math.max(...rs.map((r) => r.x + r.w));
        const figs = spans.map((sp) => sp.textContent).join("");
        if (x0 < slot.x - 0.5 || x1 > slot.x + slot.w + 0.5) problems.push(`one size, ${figs}: ${(x1 - x0).toFixed(0)} dp of figures in a ${slot.w.toFixed(0)} dp slot`);
        if ($$(".bz-circ", ph).map(rect).some((c) => c.x < x1 - 0.5 && x0 < c.x + c.w - 0.5 && c.y < slot.y + slot.h && slot.y < c.y + c.h)) problems.push(`one size, ${figs}: the figures run under \u2212 or +`);
        fit["eq:" + figs] = (x1 - x0);
      }
    });
    box.remove();
    if (frames.size !== 1) problems.push(`the analysis frame differs between phones (${frames.size} versions)`);
    $$("[data-fitline]").forEach((el) => {
      const r = fit[el.dataset.fitline] || {};
      el.innerHTML = r.pill && r.band ? '<span class="good">fits</span>' : `<span class="bad">cut</span> ${r.pill ? "" : "in the pill"}${!r.pill && !r.band ? " and " : ""}${r.band ? "" : "in today's band"}`;
    });
    const av = Object.values(areas), first = areas["running:0"];
    $$("[data-hyarea]").forEach((el) => { if (el.dataset.hyarea !== "today") el.textContent = `${first.toFixed(1)} % (${Math.min(...av).toFixed(1)} to ${Math.max(...av).toFixed(1)} %)`; });
    const eq = Object.entries(fit).filter(([k]) => k.startsWith("eq:")).map(([k, v]) => `${k.slice(3)} ${v.toFixed(0)} dp`).join(", ");
    const out = $("#hycheck");
    const cuts = Object.entries(fit).filter(([k, r]) => !k.startsWith("eq:") && r.pill === false).map(([k]) => { const [s, i] = k.split(":"); return HY.LINES[s][i].text; });
    if (out) out.textContent = `Hybrid self-check over ${jobs.length} phones (every state, every line, three pop-up options, today's band, and the one-size readout): ` +
      (problems.length ? problems.length + " problems. " + problems.join("; ") : "no problems.") +
      ` The analysis frame is ${frames.size === 1 ? "identical" : "NOT identical"} in all of them. Lines cut at the pill's edge: ${cuts.length ? cuts.join("; ") : "none"}. One-size figures, width (slot ${W - 144} dp): ${eq}.`;
    console.log("hybrid self-check:", problems.length ? problems : "no problems", "cut:", cuts, "pill area %:", areas, "one-size widths:", eq);
  }

  // ------------------------------------------------------------------ Polish No bands (bands-polish.js)
  const P = window.POLISH;
  const TOP = B.geom("none").topH;                       // the top row's footprint, the same in every design
  const pctH = (dp) => (100 * dp / H).toFixed(1) + " %";

  function polishPhone(d, state, digits, scale) {
    const s = P.figures(S, state, digits), c = CTRL(state), b = P.bottom(d.id, s, c, ico);
    let h = base("none", s, c, st) + b.html;
    if (st.foot) h += `<div class="pz-foot" style="${pos(0, 0, W, TOP)}"><b>top ${f1(TOP)} dp</b></div>` +
      `<div class="pz-foot bot" style="${pos(0, b.y0, W, H - b.y0)}"><b>bottom ${f1(H - b.y0)} dp</b></div>`;
    const label = `${d.name}, ${state}, ${digits === 2 ? "two-digit" : "one-digit"} figures`;
    return `<div class="shell" data-design="${d.id}" style="width:${f1(W * scale)}px;height:${f1(H * scale)}px" role="img" aria-label="${label}">` +
      `<div class="phone type-inter ${st.targets ? "show-targets" : ""}" style="zoom:${scale}">${h}</div></div>`;
  }

  function polishStage() {
    const n = P.DESIGNS.length, gap = 20;
    const sc = st.pzsize === "1" ? 1 : Math.max(0.55, Math.min(1, (document.documentElement.clientWidth - 32 - (n - 1) * gap) / n / W));
    const rows = st.digits === "both" ? [1, 2] : [parseInt(st.digits, 10)];
    const noTwo = st.state === "idle" || st.state === "setup";
    const rowHead = (dg) => rows.length < 2 ? "" : `<h3 class="pz-rowh">${dg === 1 ? "One-digit figures: 3/5, round 2" : "Two-digit figures: 12/15, round 12 (finished: round 24)"}${dg === 2 && noTwo ? ". Idle and setup have no two-digit figures; switch to running, paused or finished." : ""}</h3>`;
    const card = (d, i, dg, meta) => {
      const bt = P.bottom(d.id, P.figures(S, st.state, dg), CTRL(st.state), ico);
      return `<div class="pane pz-card rejected" style="width:${f1(W * sc)}px"><p class="cap"><b>${i + 1} · ${d.name}</b> <span class="badge mock">mock</span> <span class="badge rejected">rejected</span></p>` +
        `<p class="pz-opt">${d.optimises}</p>${polishPhone(d, st.state, dg, sc)}` +
        (meta ? `<dl class="pz-meta"><dt>Controls</dt><dd>${d.arrangement}</dd><dt>Readout</dt><dd>${d.readout}</dd>` +
          `<dt>Footprint</dt><dd class="num">height <b>${pctH(TOP + H - bt.y0)}</b> (top ${f1(TOP)} + bottom ${f1(H - bt.y0)} dp) · glass <b data-area="${d.id}">…</b> of the screen</dd>` +
          `<dt>At 2 m</dt><dd class="num" data-legib="${d.id}">…</dd></dl>` : "") + `</div>`;
    };
    return `<div class="pz-intro"><b>Polish No bands (rejected 2026-11-07, all six).</b> Six designs of the bottom controls and the readout, in one state. The top row, the coaching pill, the zone corners and the analysis frame are the same in all six. − and + stay in every design. In every readout the count and its target are one size and one weight; the target steps down in colour only, or (Segments) stops being a number.</div>` +
      rows.map((dg, r) => rowHead(dg) + `<div class="pz-row" style="gap:${gap}px">${P.DESIGNS.map((d, i) => card(d, i, dg, r === rows.length - 1)).join("")}</div>`).join("") +
      `<section class="pz-sum">${polishTable()}<p class="pz-check" id="selfcheck">Layout self-check: running…</p></section>`;
  }

  function polishTable() {
    const rows = P.DESIGNS.map((d, i) => {
      const b = P.bottom(d.id, P.figures(S, "running", 1), CTRL("running"), ico);
      return `<tr><th>${i + 1} · ${d.name}</th><td>${d.arrShort}</td><td>${d.roShort}</td><td class="num">${d.countSp} sp</td>` +
        `<td class="num" data-mm="${d.id}">…</td><td class="num" data-arc="${d.id}">…</td><td class="num">${f1(H - b.y0)} dp</td>` +
        `<td class="num"><b>${pctH(TOP + H - b.y0)}</b></td><td class="num" data-area="${d.id}">…</td><td data-fit="${d.id}">…</td></tr>`;
    });
    const nb = B.geom("none");
    return `<table class="tbl"><caption>The six designs against No bands as it stands</caption><thead><tr><th></th><th>controls</th><th>readout</th><th>count = target</th><th>figure height</th><th>at 2 m</th><th>bottom</th><th>height footprint</th><th>glass area</th><th>self-check, every state, 1 and 2 digits</th></tr></thead><tbody>` +
      `<tr class="ref"><th>No bands today</th><td>Cluster in the plate</td><td>3 at 44 sp, /5 at 24 sp</td><td class="num">44 / 24 sp</td><td class="num" data-mm="nb">…</td><td class="num" data-arc="nb">…</td><td class="num">${f1(nb.bottomH)} dp</td><td class="num">${pctH(nb.topH + nb.bottomH)}</td><td class="num">n/a</td><td>the size mismatch the owner named</td></tr>` +
      rows.join("") + `</tbody></table>` +
      `<p class="pz-note">Figure height is the height of Inter ExtraBold's digits, measured from the bundled font in this page (canvas <code>measureText</code>), at 1 dp = 1/160 in = 0.159 mm, which is the P40's 480 dpi at 3 px per dp. "At 2 m" is the angle that height makes at 2 m, in minutes of arc: 5′ is the 20/20 acuity limit, and this mock asks at least 10′ of the count for a glance mid-workout. Height footprint is the top row plus the bottom controls as a share of the 780 dp height, as the bands table below measures it. Glass area is the union of every glass element's box (clock, icons, coaching pill, plates, buttons, progress edge) as a share of the screen, measured in the running state; boxes, so rounded corners are counted in full.</p>`;
  }

  let digitEm = null;                                    // Inter ExtraBold digit height per em, measured once
  function measurePolish() {
    const run = () => {
      if (digitEm === null) {
        const cx = document.createElement("canvas").getContext("2d");
        cx.font = '800 1000px "CindyInter"';
        digitEm = cx.measureText("0123456789").actualBoundingBoxAscent / 1000;
      }
      const mm = (sp) => sp * digitEm * 25.4 / 160, arc = (sp) => mm(sp) / 2000 * 180 / Math.PI * 60;
      const legib = (sp) => `${mm(sp).toFixed(1)} mm`;
      const arcTxt = (sp) => `${arc(sp).toFixed(1)}′${arc(sp) < 10 ? " (under 10′)" : ""}`;
      $$("[data-mm]").forEach((el) => { const id = el.dataset.mm; el.textContent = legib(id === "nb" ? 44 : P.DESIGNS.find((d) => d.id === id).countSp); });
      $$("[data-arc]").forEach((el) => { const id = el.dataset.arc; el.textContent = arcTxt(id === "nb" ? 44 : P.DESIGNS.find((d) => d.id === id).countSp); });
      $$("[data-legib]").forEach((el) => { const sp = P.DESIGNS.find((d) => d.id === el.dataset.legib).countSp; el.textContent = `count and target ${sp} sp: digits ${legib(sp)} tall, ${arcTxt(sp)} at 2 m`; });
      selfCheck();
    };
    const f = document.fonts;
    Promise.all(["800 100px CindyInter", "700 100px CindyInter", "600 100px CindyInter"].map((x) => f.load(x))).then(() => f.ready).then(run, run);
  }

  // Render every design in every state with both figure sets off-screen, and check what a reviewer would catch:
  // a figure outside its plate or under a button, a control in the real zone, a target under 48 dp, unequal figures.
  function selfCheck() {
    const box = document.createElement("div");
    box.className = "pz-offscreen";
    const saved = st.foot; st.foot = false;
    const jobs = [];
    P.DESIGNS.forEach((d) => STATES.forEach(([k]) => [1, 2].forEach((dg) => jobs.push([d, k, dg]))));
    box.innerHTML = jobs.map(([d, k, dg]) => polishPhone(d, k, dg, 1)).join("");
    st.foot = saved;
    document.body.appendChild(box);
    const zoneBottom = B.ZONE.bottom, problems = {}, areas = {};
    P.DESIGNS.forEach((d) => { problems[d.id] = []; });
    $$(".shell", box).forEach((shell, i) => {
      const [d, k, dg] = jobs[i], ph = $(".phone", shell), pr = ph.getBoundingClientRect(), z = pr.width / W;
      const rect = (el) => { const r = el.getBoundingClientRect(); return { x: (r.left - pr.left) / z, y: (r.top - pr.top) / z, w: r.width / z, h: r.height / z }; };
      const inter = (a, b) => a.x < b.x + b.w - 0.5 && b.x < a.x + a.w - 0.5 && a.y < b.y + b.h - 0.5 && b.y < a.y + a.h - 0.5;
      const inside = (a, b) => a.x >= b.x - 0.5 && a.y >= b.y - 0.5 && a.x + a.w <= b.x + b.w + 0.5 && a.y + a.h <= b.y + b.h + 0.5;
      const tag = `${k}, ${dg} digit${dg > 1 ? "s" : ""}`;
      const hits = $$("[data-hit]", ph).map(rect);
      $$("[data-fig]", ph).forEach((fg) => {
        const spans = $$(".pz-fig", fg);
        if (!spans.length) return;
        const rs = spans.map(rect);
        const u = rs.reduce((a, r) => ({ x: Math.min(a.x, r.x), y: Math.min(a.y, r.y), r: Math.max(a.r, r.x + r.w), b: Math.max(a.b, r.y + r.h) }), { x: 1e9, y: 1e9, r: -1e9, b: -1e9 });
        const ub = { x: u.x, y: u.y, w: u.r - u.x, h: u.b - u.y };
        const pl = fg.closest("[data-plate]");
        if (pl && !inside(ub, rect(pl))) problems[d.id].push(`${tag}: the figures leave their plate`);
        const slot = rect(fg), over = Math.max(slot.x - ub.x, ub.x + ub.w - (slot.x + slot.w));
        if (over > 0.5) problems[d.id].push(`${tag}: the figures (${ub.w.toFixed(0)} dp) overflow their ${slot.w.toFixed(0)} dp slot`);
        if (hits.some((h) => inter(ub, h))) problems[d.id].push(`${tag}: the figures run under a button`);
        const sizes = new Set(spans.map((sp) => getComputedStyle(sp).fontSize));
        if (sizes.size > 1) problems[d.id].push(`${tag}: count and target differ in size (${[...sizes].join(", ")})`);
      });
      $$("[data-plate], [data-hit]", ph).forEach((el) => {
        const r = rect(el);
        if (r.y < 200) return;                           // the top row, shared and unchanged
        if (r.y < zoneBottom) problems[d.id].push(`${tag}: a control starts at y ${r.y.toFixed(0)} dp, inside the real zone`);
        if (el.hasAttribute("data-hit") && (r.w < 47.5 || r.h < 47.5)) problems[d.id].push(`${tag}: a ${r.w.toFixed(0)} x ${r.h.toFixed(0)} dp target`);
        if (r.x < -0.5 || r.x + r.w > W + 0.5 || r.y + r.h > H + 0.5) problems[d.id].push(`${tag}: off the screen`);
      });
      if (k === "running" && dg === 1) {                 // glass area: union of every glass element's box, on a 1 dp grid
        const grid = new Uint8Array(W * H);
        $$(".bz-pillglass, .bz-icon.glassbtn, .bz-pill, .bz-circ, .bz-shutter, .pz-plate, .pz-capsule, .bz-track[data-chrome]", ph).forEach((el) => {
          const r = rect(el), x0 = Math.max(0, Math.floor(r.x)), x1 = Math.min(W, Math.ceil(r.x + r.w)), y0 = Math.max(0, Math.floor(r.y)), y1 = Math.min(H, Math.ceil(r.y + r.h));
          for (let y = y0; y < y1; y++) grid.fill(1, y * W + x0, y * W + x1);
        });
        areas[d.id] = 100 * grid.reduce((a, v) => a + v, 0) / (W * H);
      }
    });
    box.remove();
    $$("[data-area]").forEach((el) => { el.textContent = areas[el.dataset.area].toFixed(1) + " %"; });
    $$("[data-fit]").forEach((el) => { const p = problems[el.dataset.fit]; el.textContent = p.length ? `${p.length} problem${p.length > 1 ? "s" : ""}` : "passes"; el.className = p.length ? "bad" : "good"; });
    const all = Object.entries(problems).flatMap(([id, p]) => [...new Set(p)].map((x) => `${P.DESIGNS.find((d) => d.id === id).name}: ${x}`));
    const out = $("#selfcheck");
    if (out) out.textContent = `Layout self-check over ${jobs.length} phones (6 designs x 5 states x 1 and 2 digits): ` + (all.length ? all.length + " problems. " + all.join("; ") : "no problems.");
    console.log("polish self-check:", all.length ? all : "no problems", "glass area", areas);
  }

  function statesNote() {
    const rows = [
      ["Camera switch (top band)", "enabled", "dimmed", "dimmed", "enabled", "dimmed"],
      ["END (left slot)", "empty", "empty", "shown", "shown", "empty"],
      ["Shutter", "play", "play, dimmed", "pause", "play", "again"],
      ["− and + (gone in the rejected variant)", "dimmed", "dimmed", "enabled", "dimmed", "dimmed"],
      ["SKIP", "dimmed", "enabled", "enabled", "enabled", "dimmed"],
    ];
    return `<table class="tbl"><caption>Controls per state, as the branch has them</caption><thead><tr><th></th>${STATES.map((x) => `<th>${x[1]}</th>`).join("")}</tr></thead><tbody>` +
      rows.map((r) => `<tr><th>${r[0]}</th>${r.slice(1).map((c) => `<td class="${c.startsWith("dimmed") ? "dimmed" : ""}">${c}</td>`).join("")}</tr>`).join("") + `</tbody></table>`;
  }

  function sharesTable() {
    const L = B.shares();
    const m = B.MEASURED;
    const row = (s) => {
      const name = VARIANTS.find((x) => x[0] === s.variant)[1] + (REJECTED.has(s.variant) ? " (rejected)" : "");
      return `<tr><th>${name}</th><td>${s.topPx.toFixed(0)} px</td><td>${s.bottomPx.toFixed(0)} px</td><td><b>${pct(s.opaque)}</b></td><td>${pct(s.footprint)}</td><td>${pct(s.withPill)}</td><td>${pct(s.picture)}</td></tr>`;
    };
    return `<table class="tbl"><caption>Chrome share, 1080 x 2340</caption><thead><tr><th></th><th>above</th><th>below</th><th>chrome (opaque)</th><th>controls footprint</th><th>+ coaching pill</th><th>picture</th></tr></thead><tbody>${L.map(row).join("")}</tbody></table>`;
  }

  function renderNumbers() {
    $("#shares").innerHTML = sharesTable();
    const t = shareOf("today"), thin = shareOf("thin"), none = shareOf("none"), nopm = shareOf("nopm"), hy = shareOf("hybrid");
    const m = B.MEASURED;
    const mp = (m.topPx + m.bottomPx) / (B.H * B.PX) * 100;
    const sp = (m.spec.topPx + m.spec.bottomPx) / (B.H * B.PX) * 100;
    $("#numnote").innerHTML = `
      <p><b>Today's bands:</b> the model gives ${t.topPx.toFixed(0)} px above and ${t.bottomPx.toFixed(0)} px below, ${pct(t.opaque)} of the screen. The 2026-11-06 capture (<code>captures/camera.png</code>) measures ${m.topPx} px above and ${m.bottomPx} px below, ${pct(mp)}. The ticket and spec #139 say ${m.spec.topPx} px above, ${m.spec.bottomPx} px below and 43 %; ${m.spec.topPx} + ${m.spec.bottomPx} is ${m.spec.topPx + m.spec.bottomPx} px, which is ${pct(sp)}, so the spec's own figures do not add up to 43 %. The capture agrees with 426 above and not with 533 below (the progress edge sits at y = 1678 px).</p>
      <p><b>Thin top, today's bottom:</b> ${hy.topPx.toFixed(0)} px above (Thin bands' top) and ${hy.bottomPx.toFixed(0)} px below (today's bottom), <b>${pct(hy.opaque)}</b> of the screen, against today's ${pct(t.opaque)}. The coaching pop-up is not in it: counted as a band, as HUDMEASURE counts it, the share with it is ${pct(hy.withPill)}; in area the pill is a few percent of the screen (measured in the hybrid view).</p>
      <p><b>Thin bands:</b> ${pct(thin.opaque)}, against a target of about 25 %. The overshoot is the count row: the prototype keeps the reps number at 44 sp (autosize 24 to 44), a ${thin.g.K.toFixed(0)} dp line, in a row the 48 dp editors alone would size to 48 dp. The coaching pill (${(thin.g.pillH + 8).toFixed(0)} dp with its margin) sits on the picture and is not in the ${pct(thin.opaque)}; with it the thin layout reaches ${pct(thin.withPill)}.</p>
      <p><b>No bands (rejected 2026-11-07):</b> no band is opaque, so the picture is the whole screen. The controls still occupy ${pct(none.footprint)} of the height (${none.g.topH.toFixed(0)} dp at the top, ${none.g.bottomH.toFixed(0)} dp at the bottom), which is what the prototype's own HUDMEASURE log calls the footprint.</p>
      <p><b>No bands, no \u2212/+ (rejected 2026-11-07, \u2212 and + stay):</b> same top as No bands (${nopm.g.topH.toFixed(0)} dp). The bottom is ${nopm.g.bottomH.toFixed(0)} dp: the readout plate is drawn at ${nopm.g.boxH} dp in both readouts (A: 64 sp reps; B: a 68 dp segmented ring), against ${none.g.boxH.toFixed(0)} dp for No bands' count pill. Controls footprint <b>${pct(nopm.footprint)}</b> (No bands ${pct(none.footprint)}), still 0 % opaque. Removing \u2212 and + takes width, not height, so the footprint does not fall: the reps number grows instead. The plate is sized as a design value with the font's padding off; the other variants are sized with Android's padding on. If the app kept the padding on for a 64 sp ExtraBold line, the footprint would be ${pct(nopm.padded)}.</p>
      <details><summary>How the numbers are made</summary>
        <p>All in dp, 1 dp = 3 px. The model is <code>bands-geometry.js</code>; every constant is a number from <code>activity_main.xml</code> or <code>HudVariants.kt</code> on <code>prototype/hud-bands</code> (e6593b1).</p>
        <p>Text height is Android's, with font padding on: the font's bounding box. Manrope: ExtraBold 1.5445 em, Bold 1.507 em, SemiBold 1.47 em (read from <code>fonts/*.ttf</code>). Inter is drawn on the page because #141 chose it, but its line heights are not used: the app's code still sets Manrope, so the shares are for the code as it stands.</p>
        <p>The cutout inset (${B.INSET} dp) is not in the layout; it is the one derived value: 426 px is 142 dp, and 14 + 48 + 4 + 22 + 11 leaves ${B.INSET} dp. The spec's "173 px above the clock" agrees (14 + ${B.INSET} = 57 dp = 171 px).</p>
        ${["two", "hybrid", "thin", "today", "none", "nopm"].map((v) => { const s = shareOf(v); const nm = VARIANTS.find((x) => x[0] === v)[1];
          return `<p><b>${nm}</b><br>top ${s.g.topParts.map((p) => p[0] + " " + f1(p[1])).join(" + ")} = ${f1(s.g.topH)} dp<br>bottom ${s.g.bottomParts.map((p) => p[0] + " " + f1(p[1])).join(" + ")} = ${f1(s.g.bottomH)} dp</p>`; }).join("")}
      </details>`;
    const out = B.shares().map((s) => `${s.variant}: above ${s.topPx.toFixed(0)} px, below ${s.bottomPx.toFixed(0)} px, opaque ${s.opaque.toFixed(1)} %, footprint ${s.footprint.toFixed(1)} %`);
    console.log("bands mock, chrome share\n" + out.join("\n"));
    $("#frameinfo").textContent = `Analysis frame ${B.FRAME.srcW} x ${B.FRAME.srcH}, mapped FILL_CENTER onto ${B.W} x ${B.H} dp: scale ${B.FRAME.scale.toFixed(4)}, ${B.FRAME.w.toFixed(1)} x ${B.FRAME.h.toFixed(1)} dp, ${B.FRAME.cropX.toFixed(1)} dp cropped off each side. One rectangle, drawn the same in every variant; the second dashed line is its visible edge. The real zone (today's bright middle, drawn as corners in No bands) is y ${B.ZONE.top.toFixed(0)} to ${B.ZONE.bottom.toFixed(1)} dp.`;
  }

  function init() {
    const seg = (id, items, attr) => { $(id).innerHTML = items.map(([k, n]) => `<button ${attr}="${k}" aria-pressed="false">${n}</button>`).join(""); };
    seg("#seg-view", [["hybrid", "Thin top, today's bottom"], ["side", "Side by side"], ["big", "One big phone"], ["grid", "All " + MAIN.length * STATES.length], ["rejected", "Rejected: No bands"]], "data-view");
    seg("#seg-rej", [["polish", "Polish No bands, six designs"], ["nopm", "No bands, and without \u2212/+"]], "data-rej");
    seg("#seg-popup", HY.POPUPS.map((p) => [p.id, p.name]), "data-popup");
    seg("#seg-readout", [["A", "A  count, then the words"], ["B", "B  segmented ring"]], "data-readout");
    seg("#seg-state", STATES, "data-state");
    seg("#seg-digits", [["1", "3/5, round 2"], ["2", "12/15, round 12"], ["both", "Both rows"]], "data-digits");
    seg("#seg-pzsize", [["fit", "Fit the window"], ["1", "Actual (1 dp = 1 px)"]], "data-pzsize");
    seg("#seg-variant", VARIANTS.map(([k, n]) => [k, REJECTED.has(k) ? n + " (rejected)" : n]), "data-variant");
    document.addEventListener("click", (e) => {
      if (e.target.closest("#replay")) { renderStage(); return; }
      const b = e.target.closest("button[data-view],button[data-state],button[data-variant],button[data-readout],button[data-digits],button[data-pzsize],button[data-rej],button[data-popup],button[data-line]");
      if (!b) return;
      if (b.dataset.view) st.view = b.dataset.view;
      if (b.dataset.state && b.dataset.state !== st.state) { st.state = b.dataset.state; st.line = 0; }
      if (b.dataset.rej) st.rej = b.dataset.rej;
      if (b.dataset.popup) st.popup = b.dataset.popup;
      if (b.dataset.line) st.line = parseInt(b.dataset.line, 10);
      if (b.dataset.variant) st.variant = b.dataset.variant;
      if (b.dataset.readout) st.readout = b.dataset.readout;
      if (b.dataset.digits) st.digits = b.dataset.digits;
      if (b.dataset.pzsize) st.pzsize = b.dataset.pzsize;
      renderStage();
    });
    [["equal", "#t-equal"], ["hold", "#t-hold"], ["foot", "#t-foot"], ["frame", "#t-frame"], ["person", "#t-person"], ["lift", "#t-lift"], ["mark", "#t-mark"], ["targets", "#t-targets"]].forEach(([k, id]) => {
      const el = $(id); el.checked = !!st[k];
      el.addEventListener("change", () => { st[k] = el.checked; renderStage(); });
    });
    addEventListener("resize", () => { if (st.view === "big" || st.view === "rejected" || st.view === "hybrid") renderStage(); });
    renderNumbers();
    renderStage();
  }
  init();
})();
