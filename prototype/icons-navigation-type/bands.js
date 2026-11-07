/* MOCK for #140: draws the camera screen's three band variants from bands-geometry.js.
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
  ];
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

  function render(variant, state, o) {
    const g = B.geom(variant), s = S[state], c = CTRL(state);
    const glass = variant === "none", compact = variant !== "today";
    let h = "";
    // picture: full screen in every variant (PreviewView and OverlayView are match_parent, so the analysis frame is the same)
    h += `<div class="bz-pic"></div>${o.lift ? '<div class="bz-lift"></div>' : ""}`;
    if (o.person) h += PERSON;
    if (variant === "none") h += zoneCorners();
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
  const st = { view: "side", state: "idle", variant: "thin", frame: true, person: true, lift: true, mark: true, targets: false };
  try { Object.assign(st, JSON.parse(decodeURIComponent(location.hash.slice(1)) || "{}")); } catch (e) { /* ignore */ }
  const persist = () => { try { history.replaceState(null, "", "#" + encodeURIComponent(JSON.stringify(st))); } catch (e) { /* file:// */ } };

  const phone = (variant, state, scale, label) => {
    const inner = `<div class="phone type-inter ${st.targets ? "show-targets" : ""}" style="zoom:${scale}">${render(variant, state, st)}</div>`;
    return `<div class="shell" style="width:${f1(W * scale)}px;height:${f1(H * scale)}px" role="img" aria-label="${label}">${inner}</div>`;
  };
  const pct = (n) => n.toFixed(1) + " %";
  const shareOf = (v) => B.shares().find((s) => s.variant === v);

  function pane(v, state, scale) {
    const [, name, what] = VARIANTS.find((x) => x[0] === v);
    const sh = shareOf(v);
    const num = v === "none"
      ? `opaque chrome <b>0 %</b> · controls footprint <b>${pct(sh.footprint)}</b>`
      : `chrome <b>${pct(sh.opaque)}</b> · picture ${pct(sh.picture)}`;
    return `<div class="pane"><p class="cap"><b>${name}</b> <span class="badge mock">mock</span></p>${phone(v, state, scale, name + ", " + state)}<p class="note">${what}</p><p class="note num">${num}</p></div>`;
  }

  function renderStage() {
    const stage = $("#stage");
    $$("[data-view]").forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.view === st.view)));
    $$("[data-state]").forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.state === st.state)));
    $$("[data-variant]").forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.variant === st.variant)));
    $("#grp-variant").hidden = st.view !== "big";
    $("#grp-state").hidden = st.view === "grid";
    if (st.view === "side") {
      stage.className = "stage";
      stage.innerHTML = VARIANTS.map(([v]) => pane(v, st.state, 1)).join("");
    } else if (st.view === "big") {
      const sc = Math.max(0.9, Math.min(1.7, (innerHeight - 210) / H));
      stage.className = "stage big";
      stage.innerHTML = pane(st.variant, st.state, sc) + `<div class="bigside">${sharesTable()}${statesNote()}</div>`;
    } else {
      stage.className = "stage grid";
      const sc = 0.62;
      stage.innerHTML = `<div class="gridwrap"><div class="gh"></div>${STATES.map(([k, n]) => `<div class="gh">${n}</div>`).join("")}` +
        VARIANTS.map(([v, name]) => `<div class="gh row">${name}</div>` + STATES.map(([k]) => `<div>${phone(v, k, sc, name + ", " + k)}</div>`).join("")).join("") + `</div>`;
    }
    persist();
  }

  function statesNote() {
    const rows = [
      ["Camera switch (top band)", "enabled", "dimmed", "dimmed", "enabled", "dimmed"],
      ["END (left slot)", "empty", "empty", "shown", "shown", "empty"],
      ["Shutter", "play", "play, dimmed", "pause", "play", "again"],
      ["− and +", "dimmed", "dimmed", "enabled", "dimmed", "dimmed"],
      ["SKIP", "dimmed", "enabled", "enabled", "enabled", "dimmed"],
    ];
    return `<table class="tbl"><caption>Controls per state, as the branch has them</caption><thead><tr><th></th>${STATES.map((x) => `<th>${x[1]}</th>`).join("")}</tr></thead><tbody>` +
      rows.map((r) => `<tr><th>${r[0]}</th>${r.slice(1).map((c) => `<td class="${c.startsWith("dimmed") ? "dimmed" : ""}">${c}</td>`).join("")}</tr>`).join("") + `</tbody></table>`;
  }

  function sharesTable() {
    const L = B.shares();
    const m = B.MEASURED;
    const row = (s) => {
      const name = VARIANTS.find((x) => x[0] === s.variant)[1];
      return `<tr><th>${name}</th><td>${s.topPx.toFixed(0)} px</td><td>${s.bottomPx.toFixed(0)} px</td><td><b>${pct(s.opaque)}</b></td><td>${pct(s.footprint)}</td><td>${pct(s.withPill)}</td><td>${pct(s.picture)}</td></tr>`;
    };
    return `<table class="tbl"><caption>Chrome share, 1080 x 2340</caption><thead><tr><th></th><th>above</th><th>below</th><th>chrome (opaque)</th><th>controls footprint</th><th>+ coaching pill</th><th>picture</th></tr></thead><tbody>${L.map(row).join("")}</tbody></table>`;
  }

  function renderNumbers() {
    $("#shares").innerHTML = sharesTable();
    const t = shareOf("today"), thin = shareOf("thin"), none = shareOf("none");
    const m = B.MEASURED;
    const mp = (m.topPx + m.bottomPx) / (B.H * B.PX) * 100;
    const sp = (m.spec.topPx + m.spec.bottomPx) / (B.H * B.PX) * 100;
    $("#numnote").innerHTML = `
      <p><b>Today's bands:</b> the model gives ${t.topPx.toFixed(0)} px above and ${t.bottomPx.toFixed(0)} px below, ${pct(t.opaque)} of the screen. The 2026-11-06 capture (<code>captures/camera.png</code>) measures ${m.topPx} px above and ${m.bottomPx} px below, ${pct(mp)}. The ticket and spec #139 say ${m.spec.topPx} px above, ${m.spec.bottomPx} px below and 43 %; ${m.spec.topPx} + ${m.spec.bottomPx} is ${m.spec.topPx + m.spec.bottomPx} px, which is ${pct(sp)}, so the spec's own figures do not add up to 43 %. The capture agrees with 426 above and not with 533 below (the progress edge sits at y = 1678 px).</p>
      <p><b>Thin bands:</b> ${pct(thin.opaque)}, against a target of about 25 %. The overshoot is the count row: the prototype keeps the reps number at 44 sp (autosize 24 to 44), a ${thin.g.K.toFixed(0)} dp line, in a row the 48 dp editors alone would size to 48 dp. The coaching pill (${(thin.g.pillH + 8).toFixed(0)} dp with its margin) sits on the picture and is not in the ${pct(thin.opaque)}; with it the thin layout reaches ${pct(thin.withPill)}.</p>
      <p><b>No bands:</b> no band is opaque, so the picture is the whole screen. The controls still occupy ${pct(none.footprint)} of the height (${none.g.topH.toFixed(0)} dp at the top, ${none.g.bottomH.toFixed(0)} dp at the bottom), which is what the prototype's own HUDMEASURE log calls the footprint.</p>
      <details><summary>How the numbers are made</summary>
        <p>All in dp, 1 dp = 3 px. The model is <code>bands-geometry.js</code>; every constant is a number from <code>activity_main.xml</code> or <code>HudVariants.kt</code> on <code>prototype/hud-bands</code> (e6593b1).</p>
        <p>Text height is Android's, with font padding on: the font's bounding box. Manrope: ExtraBold 1.5445 em, Bold 1.507 em, SemiBold 1.47 em (read from <code>fonts/*.ttf</code>). Inter is drawn on the page because #141 chose it, but its line heights are not used: the app's code still sets Manrope, so the shares are for the code as it stands.</p>
        <p>The cutout inset (${B.INSET} dp) is not in the layout; it is the one derived value: 426 px is 142 dp, and 14 + 48 + 4 + 22 + 11 leaves ${B.INSET} dp. The spec's "173 px above the clock" agrees (14 + ${B.INSET} = 57 dp = 171 px).</p>
        ${["thin", "none", "today"].map((v) => { const s = shareOf(v); const nm = VARIANTS.find((x) => x[0] === v)[1];
          return `<p><b>${nm}</b><br>top ${s.g.topParts.map((p) => p[0] + " " + f1(p[1])).join(" + ")} = ${f1(s.g.topH)} dp<br>bottom ${s.g.bottomParts.map((p) => p[0] + " " + f1(p[1])).join(" + ")} = ${f1(s.g.bottomH)} dp</p>`; }).join("")}
      </details>`;
    const out = B.shares().map((s) => `${s.variant}: above ${s.topPx.toFixed(0)} px, below ${s.bottomPx.toFixed(0)} px, opaque ${s.opaque.toFixed(1)} %, footprint ${s.footprint.toFixed(1)} %`);
    console.log("bands mock, chrome share\n" + out.join("\n"));
    $("#frameinfo").textContent = `Analysis frame ${B.FRAME.srcW} x ${B.FRAME.srcH}, mapped FILL_CENTER onto ${B.W} x ${B.H} dp: scale ${B.FRAME.scale.toFixed(4)}, ${B.FRAME.w.toFixed(1)} x ${B.FRAME.h.toFixed(1)} dp, ${B.FRAME.cropX.toFixed(1)} dp cropped off each side. One rectangle, drawn the same in all three variants; the second dashed line is its visible edge. The real zone (today's bright middle, drawn as corners in No bands) is y ${B.ZONE.top.toFixed(0)} to ${B.ZONE.bottom.toFixed(1)} dp.`;
  }

  function init() {
    const seg = (id, items, attr) => { $(id).innerHTML = items.map(([k, n]) => `<button ${attr}="${k}" aria-pressed="false">${n}</button>`).join(""); };
    seg("#seg-view", [["side", "Side by side"], ["big", "One big phone"], ["grid", "All 15"]], "data-view");
    seg("#seg-state", STATES, "data-state");
    seg("#seg-variant", VARIANTS.map(([k, n]) => [k, n]), "data-variant");
    document.addEventListener("click", (e) => {
      const b = e.target.closest("button[data-view],button[data-state],button[data-variant]");
      if (!b) return;
      if (b.dataset.view) st.view = b.dataset.view;
      if (b.dataset.state) st.state = b.dataset.state;
      if (b.dataset.variant) st.variant = b.dataset.variant;
      renderStage();
    });
    [["frame", "#t-frame"], ["person", "#t-person"], ["lift", "#t-lift"], ["mark", "#t-mark"], ["targets", "#t-targets"]].forEach(([k, id]) => {
      const el = $(id); el.checked = !!st[k];
      el.addEventListener("change", () => { st[k] = el.checked; renderStage(); });
    });
    addEventListener("resize", () => { if (st.view === "big") renderStage(); });
    renderNumbers();
    renderStage();
  }
  init();
})();
