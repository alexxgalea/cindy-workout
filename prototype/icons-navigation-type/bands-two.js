/* MOCK for #140: "Two distances", the direction the owner said yes to seeing on 2026-11-12.
   The camera screen is used from two distances. At the phone (idle, setup, paused, finished) the athlete is at arm's
   length and presses buttons. At the bar (running) they are 2 to 3 m away, cannot touch and cannot read small text.
   Each state is drawn for the distance the athlete is at.
   The base is the owner's hybrid: Thin bands' one-row top, the coaching line as pop-up A, and a bottom band of today's
   height, so the picture, the real zone and the analysis frame are the hybrid's. Only the inside of the bottom band is new.
   Its numbers are in bands-geometry.js (TWO). What each control does in each state is CameraControls.of() as bands.js
   CTRL() has it; nothing here changes a rule. Mock-only design values are marked as such. Nothing here is the app. */
(() => {
  "use strict";
  const B = window.BANDS, T = B.TWO, W = B.W;

  // Cindy's round, in order: the sets the scoreboard counts through.
  const MOVES = [{ name: "Pull-ups", n: 5 }, { name: "Push-ups", n: 10 }, { name: "Squats", n: 15 }];

  // The idle line as origin/main has it since #146 (CameraControls.IDLE_LINE). It names the shutter, so in idle this
  // design sets it under the shutter, as the screen's one line of text, and shows no pop-up. (The branch
  // prototype/hud-bands, which the hybrid's lines are read from, still says "Tap to set up".)
  const IDLE_LINE = "Press the shutter to start the setup check";

  // Mock-only design values, in ms. rep: the pace auto-play banks at.
  const TIMING = { roll: 150, pulse: 300, takeover: 1500, takeIn: 150, rep: 800 };

  const ARRS = [
    { id: "A", name: "A. Stepper capsule in the row",
      what: "One row, as asked: END, the − | + capsule, then the shutter and SKIP. The capsule is one shape and the shutter another, 40 dp apart; − is the half next to END, which asks before it ends anything.",
      cost: "Five controls in one row leave no room for the shutter in the centre: pause, START and RESUME sit at x 240 in every state." },
    { id: "B", name: "B. Stepper beside the figure",
      what: "− and + leave the row and stand beside the count they change, + over −, as today's editors flank the count. The row is today's: END, the shutter in the centre, SKIP, in the same three places in all five states.",
      cost: "The figure gives 64 dp of its width to the capsule: 12/15 keeps 16 dp either side, 3/5 sits 24 dp left of centre, and the takeover is set at 48 sp, not 56. The capsule is on the right edge, a reach for a left hand. It is not one row." },
  ];
  const PICK = "B";

  const atBar = (state) => state === "running";

  // The takeover's type size: the largest of 56, 48, 40 sp at which the widest word (PUSH-UPS) fits the zone with 8 dp
  // either side. Widths of Inter ExtraBold caps at -0.02 em, measured in Chrome: PUSH-UPS is 5.138 em.
  const takeSp = (arr) => [56, 48, 40].find((sp) => sp * 5.138 <= T.arr[arr].figW - 16) || 40;

  const pos = (x, y, w, h, extra = "") => `left:${x}px;top:${y}px;width:${w}px;height:${h}px;${extra}`;

  /** The count and its target as one figure: one size, one weight, tabular. Only the colour steps down.
      m.prev, with m.still === "pulse", draws the changed digits half-way through their roll, in the pulse's green. */
  function figure(m) {
    const cnt = String(m.count), prev = m.prev == null ? null : String(m.prev).padStart(cnt.length, " ");
    const col = m.receded ? "var(--label-tertiary)" : m.alert ? "var(--alert)" : "var(--label)";
    const b = (ch) => `<b>${ch === " " ? "&nbsp;" : ch}</b>`;
    // Digits line up from the right, so 9 to 10 rolls a 1 in and 10 to 9 rolls the 0. Going down, the column runs backwards.
    const cells = [...cnt].map((ch, i) => {
      const was = prev ? prev[prev.length - cnt.length + i] : ch;
      return was !== ch
        ? `<span class="td-d roll${m.down ? " down" : ""}${m.still === "pulse" ? " still" : ""}" data-eq><span class="td-col">${m.down ? b(ch) + b(was) : b(was) + b(ch)}</span></span>`
        : `<span class="td-d" data-eq>${ch}</span>`;
    }).join("");
    const tgt = m.target == null ? "" :
      `<span class="td-s" data-eq style="color:var(--label-tertiary)">/</span><span class="td-t" data-eq style="color:${m.receded ? "var(--label-tertiary)" : "var(--label-secondary)"}">${m.target}</span>`;
    return `<span class="td-n${m.still === "pulse" || m.pulse ? " pulse" : ""}${m.still === "pulse" ? " still" : ""}" data-td-n style="color:${col}">${cells}</span>${tgt}`;
  }

  /** The words under the figure, sentence case: the movement and the round. */
  const lineText = (m) => (m.round == null ? m.name : `${m.name} · Round <span class="tnum">${m.round}</span>`);

  /** The next set, as the takeover shows it: the number over the movement, one size. It covers the figure and the line
      under it (the zone and the line's row, 120 dp), and leaves every control where it is. */
  const takeover = (t) => `<span data-take class="tnum">${t.n}</span><span data-take>${t.name.toUpperCase()}</span>`;

  /** Everything inside the bottom band, in dp from the screen's top-left. g: geom("two"). c: bands.js CTRL(state).
      m: { count, target, name, round, alert, receded, prev, still, taking: { n, name } }. o.arr: "A" or "B". */
  function bottom(g, state, m, c, ico, o) {
    const arr = o.arr === "A" ? "A" : "B", a = T.arr[arr], y0 = g.y0, bar = atBar(state);
    const fx = a.figX, fw = a.figW;
    let h = "";
    const prog = m.target ? Math.max(0, Math.min(100, 100 * (parseInt(m.count, 10) || 0) / m.target)) : 0;
    h += `<div class="bz-track" style="${pos(0, y0, W, 3)}"><i data-td-prog style="width:${prog.toFixed(1)}%"></i></div>`;

    // ---- the readout: the figure zone, and the line ----
    const taking = bar && m.taking;
    const fig = `<div class="td-fig" data-td-fig style="font-size:${bar ? T.figSp : T.phoneFigSp}px">${figure(m)}</div>`;
    const take = bar ? `<div class="td-take" data-td-take style="font-size:${takeSp(arr)}px">${taking ? takeover(m.taking) : ""}</div>` : "";
    const line = `<div class="td-line${m.receded ? " receded" : ""}" data-td-line>${lineText(m)}</div>`;
    if (bar) {
      h += `<div class="td-zone far${taking ? " taking still" : ""}" data-td-zone style="${pos(fx, y0 + T.zoneTop, fw, T.zoneH)}">${fig}${take}</div>`;
      h += `<div class="td-linerow${taking ? " taking" : ""}" data-td-linerow style="${pos(fx, y0 + T.lineTop, fw, T.lineH)}">${line}</div>`;
    } else {
      h += `<div class="td-zone near" data-td-zone style="${pos(fx, y0 + T.zoneTop, fw, T.zoneH)}">${fig}${line}</div>`;
    }

    // ---- the controls: a quiet 48 dp row at the bar; forward, larger and named at the phone ----
    const rowTop = y0 + (bar ? T.rowTop : T.phoneRowTop), rowH = bar ? T.rowH : T.phoneRowH, cy = rowTop + rowH / 2;
    const side = bar ? 48 : 56, run = bar ? 48 : 72;
    const circ = (cx, size, key, glyph, dim, tint, id) =>
      `<div class="hit bz-circ" data-hit data-td-ctl="${id}" style="${pos(cx - size / 2, cy - size / 2, size, size, `opacity:${dim};color:${tint};border-radius:50%`)}">${ico(key, glyph)}</div>`;
    const label = (cx, text, w) => `<div class="td-lbl" style="${pos(cx - w / 2, y0 + T.labelTop, w, T.labelH)}">${text}</div>`;
    if (c.end) h += circ(a.endCx, side, "stop", bar ? 18 : 22, 1, "var(--alert)", "end");
    // The shutter. At the bar it is a quiet glass circle like its neighbours; at the phone it is the white disc it is today.
    h += bar
      ? circ(a.runCx, run, m.shutter, 18, c.shutter, "var(--label)", "run")
      : `<div class="hit bz-shutter" data-hit data-td-ctl="run" style="${pos(a.runCx - run / 2, cy - run / 2, run, run, `opacity:${c.shutter}`)}">${ico(m.shutter, 30)}</div>`;
    h += circ(a.skipCx, side, "skip", bar ? 20 : 24, c.skip, "var(--label)", "skip");

    // − and +, one capsule of two 48 dp targets. A: in the row. B: beside the figure, + over −.
    const s = a.stepper, sy = s.vertical ? y0 + T.zoneTop : cy - s.h / 2;
    const half = (key, act) => `<div class="hit td-half" data-hit data-td-act="${act}" data-td-ctl="${act}">${ico(key, 20)}</div>`;
    h += `<div class="td-capsule${s.vertical ? " v" : ""}" data-td-capsule style="${pos(s.x, sy, s.w, s.h, `opacity:${c.edit}`)}">` +
      (s.vertical ? half("plus", "plus") + `<i></i>` + half("minus", "minus") : half("minus", "minus") + `<i></i>` + half("plus", "plus")) + `</div>`;

    // ---- the names, at the phone only: nothing at the bar is small text ----
    if (!bar) {
      if (state === "idle") h += `<div class="td-one" data-td-one style="${pos(16, y0 + T.labelTop, W - 32, T.labelH)}"><span>${IDLE_LINE}</span></div>`;
      else {
        if (c.end) h += label(a.endCx, "END", 72);
        if (c.shutter === 1) h += label(a.runCx, state === "finished" ? "AGAIN" : "RESUME", 96);
        if (c.skip === 1) h += label(a.skipCx, "SKIP", 72);
      }
    }
    return h;
  }

  window.TWO = { MOVES, IDLE_LINE, TIMING, ARRS, PICK, atBar, takeSp, figure, lineText, takeover, bottom };
})();
