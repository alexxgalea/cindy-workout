/* MOCK for #140: draws the camera screen's band variants (three, plus the owner's fourth: No bands without \u2212/+) from bands-geometry.js.
   What goes where is read from prototype/hud-bands (HudVariants.kt, activity_main.xml, MainActivity.kt renderControls()).
   Not the app, not the in-app prototype. Phosphor icons, Inter, the app's tokens, the real camera capture. No blur. */
(() => {
  "use strict";
  const B = window.BANDS, D = window.ICON_DATA.sets.phosphor;
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => [...r.querySelectorAll(s)];
  const { W, H, LH } = B;

  const VARIANTS = [
    ["thin", "Thin bands", "One top row with the clock and the icons; the coaching line is a pill on the picture; one row for the count, one for the actions."],
    ["none", "No bands", "The picture fills the screen. Clock, icons, count and actions float on glass; drawn corners mark the real zone."],
    ["today", "Today's bands", "The baseline: two translucent bands, the coaching line inside the top one, round and count in the bottom one."],
    ["nopm", "No bands, no \u2212/+", "Rejected by the owner on 2026-11-07: \u2212 and + stay. Kept for the record: No bands with the two buttons gone and the round and count redrawn as type on one glass plate (readout A or B)."],
  ];
  const REJECTED = new Set(["nopm"]);                     // the owner turned it down; kept on the page, out of the default views
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
    const glass = variant === "none" || variant === "nopm", compact = variant !== "today";
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
    const dot = `<span class="bz-dot" style="background:${s.dot === "ok" ? "var(--ok)" : "transparent"}"></span>`;
    if (!compact) {
      h += `<div class="bz-status" style="${pos(0, g.statusTop, W, g.statusH)}">${dot}<span class="t-headline" style="font-size:14px">${s.status}</span></div>`;
    } else {
      h += `<div class="bz-statuswrap" style="top:${f1(g.pillTop)}px"><div class="bz-pill" style="height:${f1(g.pillH)}px">${dot}<span class="t-headline" style="font-size:14px">${s.status}</span></div></div>`;
    }
    return h;
  }

  function render(variant, state, o) {
    const g = B.geom(variant), s = S[state], c = CTRL(state);
    const glass = variant === "none" || variant === "nopm", compact = variant !== "today";
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
      h += `<div class="bz-count" style="${pos(72, g.countTop, W - 144, g.countH)}"><span class="t-metric-xl" style="font-size:56px;color:${repsCol}">${s.reps}</span><span class="tgt" style="font-size:30px">${s.tgt}</span></div>`;
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
  const st = { view: "polish", state: "running", variant: "thin", readout: "A", digits: "1", pzsize: "fit", foot: true, frame: true, person: true, lift: true, mark: true, targets: false };
  try { Object.assign(st, JSON.parse(decodeURIComponent(location.hash.slice(1)) || "{}")); } catch (e) { /* ignore */ }
  const persist = () => { try { history.replaceState(null, "", "#" + encodeURIComponent(JSON.stringify(st))); } catch (e) { /* file:// */ } };

  const phone = (variant, state, scale, label, readout) => {
    const inner = `<div class="phone type-inter ${st.targets ? "show-targets" : ""}" style="zoom:${scale}">${render(variant, state, Object.assign({}, st, { readout: readout || st.readout }))}</div>`;
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
    $("#grp-readout").hidden = !(st.view === "big" && st.variant === "nopm");
    $("#grp-variant").hidden = st.view !== "big";
    $$("[data-digits]").forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.digits === st.digits)));
    $$("[data-pzsize]").forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.pzsize === st.pzsize)));
    $("#grp-state").hidden = st.view === "grid";
    $$(".pz-only").forEach((el) => { el.hidden = st.view !== "polish"; });
    if (st.view === "polish") {
      stage.className = "stage polish";
      stage.innerHTML = polishStage();
      measurePolish();
    } else if (st.view === "side") {
      stage.className = "stage";
      stage.innerHTML = MAIN.map(([v]) => pane(v, st.state, 1)).join("");
    } else if (st.view === "cmp") {
      stage.className = "stage";
      stage.innerHTML = pane("none", st.state, 1) + pane("nopm", st.state, 1, "A") + pane("nopm", st.state, 1, "B");
    } else if (st.view === "big") {
      const sc = Math.max(0.9, Math.min(1.7, (innerHeight - 210) / H));
      stage.className = "stage big";
      stage.innerHTML = pane(st.variant, st.state, sc) + `<div class="bigside">${sharesTable()}${statesNote()}</div>`;
    } else {
      stage.className = "stage grid";
      const sc = 0.62;
      stage.innerHTML = `<div class="gridwrap"><div class="gh"></div>${STATES.map(([k, n]) => `<div class="gh">${n}</div>`).join("")}` +
        MAIN.map(([v, name]) => `<div class="gh row">${name}</div>` + STATES.map(([k]) => `<div>${phone(v, k, sc, name + ", " + k)}</div>`).join("")).join("") + `</div>`;
    }
    persist();
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
      return `<div class="pane pz-card" style="width:${f1(W * sc)}px"><p class="cap"><b>${i + 1} · ${d.name}</b> <span class="badge mock">mock</span></p>` +
        `<p class="pz-opt">${d.optimises}</p>${polishPhone(d, st.state, dg, sc)}` +
        (meta ? `<dl class="pz-meta"><dt>Controls</dt><dd>${d.arrangement}</dd><dt>Readout</dt><dd>${d.readout}</dd>` +
          `<dt>Footprint</dt><dd class="num">height <b>${pctH(TOP + H - bt.y0)}</b> (top ${f1(TOP)} + bottom ${f1(H - bt.y0)} dp) · glass <b data-area="${d.id}">…</b> of the screen</dd>` +
          `<dt>At 2 m</dt><dd class="num" data-legib="${d.id}">…</dd></dl>` : "") + `</div>`;
    };
    return `<div class="pz-intro"><b>Polish No bands.</b> Six designs of the bottom controls and the readout, in one state. The top row, the coaching pill, the zone corners and the analysis frame are the same in all six. − and + stay in every design. In every readout the count and its target are one size and one weight; the target steps down in colour only, or (Segments) stops being a number.</div>` +
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
    const t = shareOf("today"), thin = shareOf("thin"), none = shareOf("none"), nopm = shareOf("nopm");
    const m = B.MEASURED;
    const mp = (m.topPx + m.bottomPx) / (B.H * B.PX) * 100;
    const sp = (m.spec.topPx + m.spec.bottomPx) / (B.H * B.PX) * 100;
    $("#numnote").innerHTML = `
      <p><b>Today's bands:</b> the model gives ${t.topPx.toFixed(0)} px above and ${t.bottomPx.toFixed(0)} px below, ${pct(t.opaque)} of the screen. The 2026-11-06 capture (<code>captures/camera.png</code>) measures ${m.topPx} px above and ${m.bottomPx} px below, ${pct(mp)}. The ticket and spec #139 say ${m.spec.topPx} px above, ${m.spec.bottomPx} px below and 43 %; ${m.spec.topPx} + ${m.spec.bottomPx} is ${m.spec.topPx + m.spec.bottomPx} px, which is ${pct(sp)}, so the spec's own figures do not add up to 43 %. The capture agrees with 426 above and not with 533 below (the progress edge sits at y = 1678 px).</p>
      <p><b>Thin bands:</b> ${pct(thin.opaque)}, against a target of about 25 %. The overshoot is the count row: the prototype keeps the reps number at 44 sp (autosize 24 to 44), a ${thin.g.K.toFixed(0)} dp line, in a row the 48 dp editors alone would size to 48 dp. The coaching pill (${(thin.g.pillH + 8).toFixed(0)} dp with its margin) sits on the picture and is not in the ${pct(thin.opaque)}; with it the thin layout reaches ${pct(thin.withPill)}.</p>
      <p><b>No bands:</b> no band is opaque, so the picture is the whole screen. The controls still occupy ${pct(none.footprint)} of the height (${none.g.topH.toFixed(0)} dp at the top, ${none.g.bottomH.toFixed(0)} dp at the bottom), which is what the prototype's own HUDMEASURE log calls the footprint.</p>
      <p><b>No bands, no \u2212/+ (rejected 2026-11-07, \u2212 and + stay):</b> same top as No bands (${nopm.g.topH.toFixed(0)} dp). The bottom is ${nopm.g.bottomH.toFixed(0)} dp: the readout plate is drawn at ${nopm.g.boxH} dp in both readouts (A: 64 sp reps; B: a 68 dp segmented ring), against ${none.g.boxH.toFixed(0)} dp for No bands' count pill. Controls footprint <b>${pct(nopm.footprint)}</b> (No bands ${pct(none.footprint)}), still 0 % opaque. Removing \u2212 and + takes width, not height, so the footprint does not fall: the reps number grows instead. The plate is sized as a design value with the font's padding off; the other variants are sized with Android's padding on. If the app kept the padding on for a 64 sp ExtraBold line, the footprint would be ${pct(nopm.padded)}.</p>
      <details><summary>How the numbers are made</summary>
        <p>All in dp, 1 dp = 3 px. The model is <code>bands-geometry.js</code>; every constant is a number from <code>activity_main.xml</code> or <code>HudVariants.kt</code> on <code>prototype/hud-bands</code> (e6593b1).</p>
        <p>Text height is Android's, with font padding on: the font's bounding box. Manrope: ExtraBold 1.5445 em, Bold 1.507 em, SemiBold 1.47 em (read from <code>fonts/*.ttf</code>). Inter is drawn on the page because #141 chose it, but its line heights are not used: the app's code still sets Manrope, so the shares are for the code as it stands.</p>
        <p>The cutout inset (${B.INSET} dp) is not in the layout; it is the one derived value: 426 px is 142 dp, and 14 + 48 + 4 + 22 + 11 leaves ${B.INSET} dp. The spec's "173 px above the clock" agrees (14 + ${B.INSET} = 57 dp = 171 px).</p>
        ${["thin", "none", "today", "nopm"].map((v) => { const s = shareOf(v); const nm = VARIANTS.find((x) => x[0] === v)[1];
          return `<p><b>${nm}</b><br>top ${s.g.topParts.map((p) => p[0] + " " + f1(p[1])).join(" + ")} = ${f1(s.g.topH)} dp<br>bottom ${s.g.bottomParts.map((p) => p[0] + " " + f1(p[1])).join(" + ")} = ${f1(s.g.bottomH)} dp</p>`; }).join("")}
      </details>`;
    const out = B.shares().map((s) => `${s.variant}: above ${s.topPx.toFixed(0)} px, below ${s.bottomPx.toFixed(0)} px, opaque ${s.opaque.toFixed(1)} %, footprint ${s.footprint.toFixed(1)} %`);
    console.log("bands mock, chrome share\n" + out.join("\n"));
    $("#frameinfo").textContent = `Analysis frame ${B.FRAME.srcW} x ${B.FRAME.srcH}, mapped FILL_CENTER onto ${B.W} x ${B.H} dp: scale ${B.FRAME.scale.toFixed(4)}, ${B.FRAME.w.toFixed(1)} x ${B.FRAME.h.toFixed(1)} dp, ${B.FRAME.cropX.toFixed(1)} dp cropped off each side. One rectangle, drawn the same in all four variants; the second dashed line is its visible edge. The real zone (today's bright middle, drawn as corners in No bands) is y ${B.ZONE.top.toFixed(0)} to ${B.ZONE.bottom.toFixed(1)} dp.`;
  }

  function init() {
    const seg = (id, items, attr) => { $(id).innerHTML = items.map(([k, n]) => `<button ${attr}="${k}" aria-pressed="false">${n}</button>`).join(""); };
    seg("#seg-view", [["polish", "Polish No bands"], ["side", "Side by side"], ["big", "One big phone"], ["grid", "All 15"], ["cmp", "Rejected: no \u2212/+"]], "data-view");
    seg("#seg-readout", [["A", "A  count, then the words"], ["B", "B  segmented ring"]], "data-readout");
    seg("#seg-state", STATES, "data-state");
    seg("#seg-digits", [["1", "3/5, round 2"], ["2", "12/15, round 12"], ["both", "Both rows"]], "data-digits");
    seg("#seg-pzsize", [["fit", "Fit the window"], ["1", "Actual (1 dp = 1 px)"]], "data-pzsize");
    seg("#seg-variant", VARIANTS.map(([k, n]) => [k, REJECTED.has(k) ? n + " (rejected)" : n]), "data-variant");
    document.addEventListener("click", (e) => {
      const b = e.target.closest("button[data-view],button[data-state],button[data-variant],button[data-readout],button[data-digits],button[data-pzsize]");
      if (!b) return;
      if (b.dataset.view) st.view = b.dataset.view;
      if (b.dataset.state) st.state = b.dataset.state;
      if (b.dataset.variant) st.variant = b.dataset.variant;
      if (b.dataset.readout) st.readout = b.dataset.readout;
      if (b.dataset.digits) st.digits = b.dataset.digits;
      if (b.dataset.pzsize) st.pzsize = b.dataset.pzsize;
      renderStage();
    });
    [["foot", "#t-foot"], ["frame", "#t-frame"], ["person", "#t-person"], ["lift", "#t-lift"], ["mark", "#t-mark"], ["targets", "#t-targets"]].forEach(([k, id]) => {
      const el = $(id); el.checked = !!st[k];
      el.addEventListener("change", () => { st[k] = el.checked; renderStage(); });
    });
    addEventListener("resize", () => { if (st.view === "big" || st.view === "polish") renderStage(); });
    renderNumbers();
    renderStage();
  }
  init();
})();
