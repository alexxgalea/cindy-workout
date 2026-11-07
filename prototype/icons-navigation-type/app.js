/* Prototype #141: icons, closing a page, type — over the app's real screens.
   The phones are HTML recreations traced from the adb captures (positions in dp, strings as captured);
   the real captures sit beside them. Nothing here is the app, and none of it is meant to be merged. */
(() => {
  "use strict";
  const D = window.ICON_DATA;
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => [...r.querySelectorAll(s)];

  // ------------------------------------------------------------------ state
  const SETS = [["current", "Current"], ["lucide", "Lucide"], ["phosphor", "Phosphor"], ["tabler", "Tabler"]];
  const SCREENS = [["camera", "Camera"], ["menu", "Menu"], ["progress", "Progress"], ["session", "Session page"], ["you", "You"], ["sheet", "Sheet"]];
  const PARENT = { menu: "camera", progress: "menu", you: "menu", sheet: "menu", session: "progress" };
  const CAPTURES = {
    camera: { file: "captures/camera.png", what: "Camera, idle. The picture is dark: the lens was covered." },
    menu: { file: "captures/menu.png", what: "Menu, top of the page." },
    progress: { file: "captures/progress.png", what: "Progress, top of the page." },
    session: { file: "captures/session.png", what: "Session page, top. (Its DISCARD / DONE footer shows only once scrolled; not in this capture.)" },
    you: { file: "captures/you.png", what: "You, top of the page." },
    sheet: { file: "captures/sheet.png", what: "Movements sheet (\"Make Cindy yours\") over the menu." },
  };
  const DEFAULTS = { view: "single", screen: "camera", icons: "current", nav: "done", ctl: "back", ttl: "center", type: "manrope",
    sub: "show", real: "0", targets: "0", tab: "screens" };
  const st = { ...DEFAULTS };
  try { Object.assign(st, JSON.parse(decodeURIComponent(location.hash.slice(1)) || "{}")); } catch (e) { /* ignore a bad hash */ }
  const save = () => { try { history.replaceState(null, "", "#" + encodeURIComponent(JSON.stringify(st))); } catch (e) { /* file:// in some browsers */ } };

  // ------------------------------------------------------------------ icons
  function ico(key, size = 24, set = "current") {
    const d = D.sets[set][key];
    if (!d) return `<span style="width:${size}px;height:${size}px"></span>`;
    const dim = key === "ring_empty" && set !== "current" ? ' style="opacity:.25"' : "";
    const open = `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="${d.vb}"${dim} aria-hidden="true"`;
    if (d.kind === "stroke") {
      return `${open} fill="${d.fillIt ? "currentColor" : "none"}" stroke="currentColor" stroke-width="${d.sw}" stroke-linecap="round" stroke-linejoin="round">${d.body}</svg>`;
    }
    if (d.kind === "fill") return `${open} fill="currentColor">${d.body}</svg>`;
    return `${open}>${d.body}</svg>`;
  }

  // ------------------------------------------------------------------ pieces
  const status = () => `<div class="status"><span>16:30</span><i></i></div>`;

  function chevron(c) { return `<span class="chev">${ico("chevron_right", 22, c.icons)}</span>`; }

  /** Title block and the way the page closes. `p` = {title, sub, body, footer, noTitle, barTitle}. */
  function page(c, p) {
    const top = c.nav === "bar";
    const large = top && c.ttl === "large";
    const showLarge = !top || large;
    const subtitle = p.sub && c.sub === "show" && showLarge;
    let html = status();
    let bodyTop;
    if (top) {
      const glyph = c.ctl === "close" ? ico("close", 24, c.icons) : ico("chevron_left", 26, c.icons);
      const label = c.ctl === "close" ? "Close" : "Back";
      html += `<div class="tbar ${c.ttl}"><button class="hit" data-back aria-label="${label}">${glyph}</button>` +
        (c.ttl === "large" ? "" : `<span class="ttl">${p.barTitle || p.title}</span>`) + `</div>`;
      bodyTop = 84;
    } else bodyTop = 28;
    if (p.title && showLarge) {
      const y = top ? 84 : 62;
      html += `<div class="hdr" style="top:${y}px"><div class="t-title">${p.title}</div>` +
        (subtitle ? `<div class="t-body sub">${p.sub}</div>` : "") + `</div>`;
      bodyTop = y + 46 + (subtitle ? 6 + 22 * (p.subLines || 1) : 0) + 20;
    } else if (!p.title) bodyTop = top ? 96 : 60;
    else bodyTop += 8;
    const done = c.nav === "done";
    const footer = p.footer ? p.footer(c, done) : (done ? `<div class="pillbar"><button class="btn-primary t-button hit" data-back>DONE</button></div>` : "");
    const bottom = footer ? 78 : 16;
    html += `<div class="scroll" style="top:${bodyTop}px;bottom:${bottom}px">${p.body}<div style="height:12px"></div></div>${footer}`;
    return `<div class="page">${html}</div>`;
  }

  // ------------------------------------------------------------------ screens
  const R = {};

  R.camera = (c) => `
    <div class="cam">
      <div class="top"></div><div class="bot"></div><div class="track"></div>
      <div class="clock t-metric-m tnum">20:00</div>
      <button class="rec hit" data-goto="" aria-label="Record" style="color:var(--label)">${ico("rec", 20, c.icons)}</button>
      <button class="menu hit" data-goto="menu" aria-label="Menu">${ico("menu", 22, c.icons)}</button>
      <div class="line">Tap to set up</div>
      <div class="round t-eyebrow">Round <span style="color:#fff;margin-left:8px">1</span></div>
      <div class="mov t-eyebrow">Pull-ups</div>
      <div class="count"><span class="t-metric-xl">0</span><span class="of tnum">/5</span></div>
      <div class="circ off hit" style="left:16px;top:588px">${ico("minus", 24, c.icons)}</div>
      <div class="circ off hit" style="right:16px;top:588px">${ico("plus", 24, c.icons)}</div>
      <div class="circ hit" style="left:16px;top:699px;background:rgba(40,40,44,.92)">${ico("flip", 26, c.icons)}</div>
      <div class="shutter hit">${ico("play", 30, c.icons)}</div>
      <div class="circ off hit" style="right:16px;top:699px">${ico("skip", 24, c.icons)}</div>
    </div>${status()}`;

  const MENU_ROWS = [
    ["Movements", "Cindy", "sheet"], ["Progress", "13 sessions · 2-day streak", "progress"], ["Daily reminder", "Off"],
    ["Body weight", "Not set — calories need it"], ["Heart rate", "fenix 7X · add your age for calories"],
    ["Voice", "On · 100% · English"], ["Music", "No track chosen"], ["Help", "What Cindy is, how it is scored, and where to stand"],
  ];
  const menuBody = (c) => `
    <div class="card"><div class="list"><div class="item" data-goto="you"><div class="avatar"><svg viewBox="0 0 48 48" aria-hidden="true"><circle cx="24" cy="19" r="8"/><ellipse cx="24" cy="44" rx="15" ry="12"/></svg></div><div class="grow"><div class="t-headline">You</div><div class="t-foot" style="font-size:14px">6 badges</div></div>${chevron(c)}</div></div></div>
    <div class="card" style="margin-top:12px"><div class="list">${MENU_ROWS.map(([t, s, go]) =>
      `<div class="item hit" ${go ? `data-goto="${go}"` : ""}><div class="grow"><div class="t-headline">${t}</div><div class="t-foot" style="font-size:14px;margin-top:2px">${s}</div></div>${chevron(c)}</div>`).join("")}</div></div>`;
  R.menu = (c) => page(c, { title: "Menu", sub: "Everything that isn’t needed mid-workout", body: menuBody(c) });

  R.progress = (c) => page(c, { title: "Progress", sub: "Cindy — AMRAP 20:00", body: `
    <div class="card pad" style="padding:24px 18px 20px">
      <div class="t-title2" style="font-size:25px;line-height:1.35">Train today to make it 3 days.</div>
      <div style="display:flex;gap:30px;margin-top:20px">
        <div><div class="t-eyebrow">Daily streak</div><div style="display:flex;align-items:center;gap:8px;margin-top:14px;color:var(--achievement)"><span>${ico("flame", 24, c.icons)}</span><span class="t-metric-l" style="color:#fff">2</span><span class="t-headline" style="color:var(--label-secondary);font-weight:500;font-size:18px">days</span></div></div>
        <div><div class="t-eyebrow">Weekly streak</div><div style="display:flex;align-items:baseline;gap:8px;margin-top:14px"><span class="t-metric-l">2</span><span class="t-headline" style="color:var(--label-secondary);font-weight:500;font-size:18px">weeks</span></div></div>
      </div>
      <div class="dot-row" style="margin-top:22px">${["M","T","W","T","F","S","S"].map((d, i) => `<div><span class="t-callout" style="color:var(--label-secondary)">${d}</span><span class="day ${i===2||i===3?"on":i===4?"today":i>4?"future":""}"></span></div>`).join("")}</div>
      <div class="t-callout" style="margin-top:14px;color:var(--label-tertiary);font-size:15px">1 more day to a 3-day streak.</div>
      <div style="height:.5px;background:var(--hairline);margin:14px 0"></div>
      <div class="t-callout" style="color:var(--label-tertiary);font-size:15px">7 days trained · 13 sessions</div>
    </div>
    <div class="sect t-eyebrow" style="margin-top:14px">This week</div>
    <div class="card pad"><div class="tiles" style="gap:0">
      ${[["Sessions","3","−7"],["Reps","64","−118"],["Time","2 min","−17 min"]].map(([a,b,d]) => `<div><div class="t-callout" style="color:var(--label-tertiary);font-size:15px">${a}</div><div class="t-metric-m" style="margin-top:12px;font-size:30px">${b}</div><div class="t-foot" style="font-size:15px;margin-top:10px">${d}</div></div>`).join("")}
    </div></div>
    <div class="sect t-eyebrow" style="margin-top:14px">Peaks</div>
    <div class="card"><div class="list">${[["gold","1","Best score","5 Nov 2026 · 60 reps","2"],["silver","2","2nd best","28 Oct 2026 · 35 reps","1 + 10"],["off","3","3rd best","29 Oct 2026 · 30 reps","1"]].map(([k,n,t,s,v]) =>
      `<div class="item hit" data-goto="session"><span class="disc ${k}">${n}</span><div class="grow"><div class="t-headline">${t}</div><div class="t-foot" style="font-size:12px">${s}</div></div><span class="t-metric-s tnum">${v}</span>${chevron(c)}</div>`).join("")}</div></div>
    <div class="sect t-eyebrow" style="margin-top:14px">Leaderboard</div>
    <div class="card"><div class="list">${[["2","5 Nov 2026 · First Steps · 0.45/round","2"],["3","28 Oct 2026 · First Steps · 1.06/round","1 + 10"],["4","29 Oct 2026 · First Steps · 0.51/round","1"]].map(([n,s,v]) =>
      `<div class="item hit" data-goto="session"><span class="t-foot" style="width:14px;text-align:center">${n}</span><div class="grow"><div class="t-headline">You</div><div class="t-foot" style="font-size:12px">${s}</div></div><span class="t-metric-s tnum">${v}</span>${chevron(c)}</div>`).join("")}</div></div>` });

  R.session = (c) => page(c, { barTitle: "Session", body: `
    <div class="t-eyebrow" style="padding:0 4px;margin-top:${c.nav === "bar" ? 0 : 0}px">Wed 4 Nov 2026 · 17:20</div>
    <div style="display:flex;align-items:baseline;gap:6px;margin:34px 0 0 0"><span class="t-metric-xl tnum" style="font-size:96px">0</span><span class="t-metric-l tnum" style="color:var(--label-tertiary);font-size:44px;letter-spacing:-.04em">+1</span></div>
    <div class="t-body" style="margin-top:22px;color:var(--label-secondary)">1 reps in 0:11 of clock · 0:13 real</div>
    <div class="card" style="margin-top:22px;height:70px;display:flex;align-items:center;gap:18px;padding:0 24px;color:var(--achievement)">${ico("flame", 28, c.icons)}<span class="t-metric-m" style="font-size:27px;letter-spacing:-.03em">2 weeks in a row.</span></div>
    <div class="tiles" style="margin-top:18px">${[["Rounds","0","+1 rep into round 1"],["Reps","1","5.1 reps/min"],["Time","0:11","plus 0:01 paused"]].map(([a,b,d]) => `<div class="tile"><div class="t-eyebrow">${a}</div><div class="t-metric-m tnum" style="font-size:30px">${b}</div><div class="t-foot" style="font-size:13px;margin-top:8px">${d}</div></div>`).join("")}</div>
    <div class="tiles">${[["Avg"],["Fastest"],["Slowest"]].map(([a]) => `<div class="tile" style="min-height:84px"><div class="t-eyebrow">${a}</div><div class="t-metric-m" style="font-size:30px;color:var(--label-secondary)">—</div><div class="t-foot" style="font-size:13px;margin-top:6px">no full round</div></div>`).join("")}</div>
    <div class="sect t-eyebrow" style="margin-top:12px;padding-left:8px">Round by round</div>
    <div class="card pad" style="margin-top:0"><div style="width:30px;height:30px;border-radius:9px;border:1.5px solid var(--label-quaternary);margin-bottom:14px"></div><div class="t-headline" style="font-weight:400;font-size:17px;color:var(--label-body)">Tap a round to see what went into it.</div><div class="t-foot" style="margin-top:12px;font-size:13px">A round is 5 pull-ups, 10 push-ups, 15 squats, in that order, left to right. What was not done stays hollow.</div></div>`,
    footer: (c, done) => `<div class="pillbar"><button class="btn-glass btn-danger t-button hit" style="${done ? "" : "flex:1"};font-size:15px" data-back>DISCARD</button>${done ? `<button class="btn-primary t-button hit" data-back>DONE</button>` : ""}</div>` });

  R.you = (c) => page(c, { title: "You", sub: "Your name, photo and badges. They stay on this phone.", subLines: 2, body: `
    <div class="card pad" style="padding:28px 18px 22px;text-align:center"><div class="avatar" style="width:96px;height:96px;margin:0 auto"><svg viewBox="0 0 48 48" aria-hidden="true"><circle cx="24" cy="19" r="8"/><ellipse cx="24" cy="44" rx="15" ry="12"/></svg></div>
      <div class="t-title2" style="margin-top:24px;color:var(--label-secondary);font-size:26px">Add your name</div>
      <div class="t-callout" style="margin-top:6px;color:var(--label-tertiary);font-size:14px">Training since 26 Oct 2026 · 13 sessions</div></div>
    <div class="sect t-eyebrow" style="margin-top:14px">Badges · 6 of 26</div>
    <div class="t-eyebrow" style="padding:6px 4px 0">Sessions</div>
    <div class="card pad" style="margin-top:6px"><div style="display:grid;grid-template-columns:repeat(3,1fr);row-gap:20px;text-align:center">${[["gold","1st","First Cindy",""],["gold","×10","10 sessions",""],["off","×25","25 sessions","13 of 25 sessions"],["off","×50","50 sessions","13 of 50 sessions"],["off","×100","100 sessions","13 of 100"]].map(([k,t,n,s]) =>
      `<div style="display:grid;justify-items:center;gap:8px"><span class="disc ${k}" style="width:56px;height:56px;font-size:${t.length>3?15:18}px">${t}</span><span class="t-callout" style="color:#fff">${n}</span><span class="t-foot" style="font-size:12px;margin-top:-4px">${s}</span></div>`).join("")}</div></div>` });

  R.sheet = (c) => {
    const radio = (g, items, on) => `<div class="card list" style="margin-top:6px;border-radius:24px">${items.map(([t, s], i) =>
      `<div class="item hit" data-pick="${g}:${i}" style="min-height:${s ? 76 : 58}px;padding:12px 18px"><div class="grow"><div class="t-headline" style="font-size:19px;font-weight:600">${t}</div>${s ? `<div class="t-foot" style="font-size:15px;margin-top:2px">${s}</div>` : ""}</div>${i === on ? `<span data-check>${ico("check", 24, c.icons)}</span>` : ""}</div>`).join("")}</div>`;
    return `<div class="page">${status()}
      <div class="t-title" style="position:absolute;left:16px;top:62px;opacity:.22">Menu</div>
      <div class="dim"></div>
      <div class="sheet"><div class="handle"></div>
        <div class="body">
          <div class="t-title2" style="font-size:28px">Make Cindy yours</div>
          <div class="t-body" style="margin-top:12px;font-size:17px;line-height:1.55">Anything other than the standard three is saved as an Adaptive Cindy and ranked against your own sessions at the same movements.</div>
          <div class="t-eyebrow" style="margin-top:28px;padding-left:8px">Pull</div>${radio("pull", [["Strict pull-up"], ["Band-assisted"], ["Inverted row", "you tap +1"], ["Foot-assisted", "you tap +1"], ["Negatives", "you tap +1"]], 0)}
          <div class="t-eyebrow" style="margin-top:28px;padding-left:8px">Push</div>${radio("push", [["Standard"], ["Knee push-up"], ["Incline"]], 0)}
          <div style="height:24px"></div>
        </div>
        <div class="foot"><button class="btn-glass t-button hit" data-back>CANCEL</button><button class="btn-primary t-button hit" data-back>SAVE</button></div>
      </div></div>`;
  };

  const NO_CLOSE = { camera: "The camera screen has nothing to close; only icons and type apply here." };
  const KEEPS_ACTIONS = {
    session: "DISCARD is a real action, so the session page keeps a bottom bar in both variants; only DONE goes.",
    sheet: "A sheet keeps SAVE / CANCEL: both are actions. Its icon change is the check; type applies to all of it.",
  };

  // ------------------------------------------------------------------ rendering
  function phone(c, screen) {
    const el = document.createElement("div");
    el.className = `phone type-${c.type}`;
    el.dataset.icons = c.icons;
    el.innerHTML = R[screen](c) + `<div class="edge"></div><div class="bubble">${ico("chevron_left", 22, "current")}</div>`;
    return el;
  }

  function label(c) {
    const set = SETS.find((s) => s[0] === c.icons)[1];
    const nav = c.nav === "done" ? "DONE pill" : `Top bar · ${c.ctl === "close" ? "close ×" : "back ‹"} · ${c.ttl === "center" ? "centred title" : c.ttl === "left" ? "left title" : "large title below"}`;
    return `${set} · ${nav} · ${c.type === "inter" ? "Inter" : "Manrope"}`;
  }

  function realPane(screen) {
    const cap = CAPTURES[screen];
    const pane = document.createElement("div");
    pane.className = "pane real";
    pane.innerHTML = `<p class="cap"><b>Real capture</b><span class="badge real">adb · P40 · 2026-11-06</span></p><div class="shell realwrap" style="width:360px"></div><p class="note">${cap.what}</p>`;
    const wrap = $(".realwrap", pane);
    const img = new Image();
    img.alt = `Real capture of the ${screen} screen`;
    img.onload = () => wrap.appendChild(img);
    img.onerror = () => {
      wrap.innerHTML = `<div class="realmissing"><span class="badge missing">no capture</span><br>Nothing fakes this one. Drop a 1080 × 2340 PNG at <code>${cap.file}</code> (see <code>capture.sh</code>) and reload.</div>`;
    };
    img.src = cap.file;
    return pane;
  }

  function variants() {
    if (st.view === "icons") return SETS.map(([k]) => ({ ...st, icons: k }));
    if (st.view === "nav") return [{ ...st, nav: "done" }, { ...st, nav: "bar" }];
    if (st.view === "type") return [{ ...st, type: "manrope" }, { ...st, type: "inter" }];
    return [{ ...st }];
  }

  function render() {
    save();
    $("#tab-screens").hidden = st.tab !== "screens";
    $("#tab-inventory").hidden = st.tab !== "inventory";
    $$("[data-tab]").forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.tab === st.tab)));
    for (const [k, v] of Object.entries(st)) {
      $$(`[data-set="${k}"] button`).forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.v === String(v))));
    }
    $$(".seg[data-set='ctl'], .seg[data-set='ttl']").forEach((s) => s.classList.toggle("disabled", st.nav !== "bar" && st.view !== "nav"));
    $$("#real, #targets").forEach((i) => { i.checked = st[i.id] === "1"; });
    document.body.classList.toggle("show-targets", st.targets === "1");
    if (st.tab === "inventory") { renderInventory(); return; }

    const stage = $("#stage");
    stage.innerHTML = "";
    const scr = st.screen;
    const note = [NO_CLOSE[scr], KEEPS_ACTIONS[scr]].filter(Boolean).join(" ");
    for (const c of variants()) {
      const pane = document.createElement("div");
      pane.className = "pane";
      pane.innerHTML = `<p class="cap"><b>${label(c)}</b><span class="badge mock">recreation, not a capture</span></p><div class="shell"><div class="scaler"></div></div>${note ? `<p class="note">${note}</p>` : ""}`;
      $(".scaler", pane).appendChild(phone(c, scr));
      stage.appendChild(pane);
    }
    if (st.real === "1") stage.appendChild(realPane(scr));
    wire();
    fit();
  }

  function fit() {
    const stage = $("#stage");
    const panes = $$(".pane", stage);
    if (!panes.length) return;
    const gap = 28, avail = Math.max(320, window.innerWidth - 32);
    const n = panes.length;
    const availH = Math.max(420, window.innerHeight - $("header.bench").offsetHeight - 110);
    const s = Math.min(1, (avail - gap * (n - 1)) / (n * 360), availH / 780);
    const scale = Math.max(0.4, s);
    for (const p of panes) {
      const shell = $(".shell", p);
      if (p.classList.contains("real")) { shell.style.width = 360 * scale + "px"; continue; }
      const scaler = $(".scaler", p);
      scaler.style.transform = `scale(${scale})`;
      shell.style.width = 360 * scale + "px";
      shell.style.height = 780 * scale + "px";
      p.style.width = 360 * scale + "px";
    }
    for (const p of panes) if (p.classList.contains("real")) p.style.width = 360 * scale + "px";
    stage.style.justifyContent = "center";
  }

  // ------------------------------------------------------------------ behaviour inside the phones
  function go(screen) { st.screen = screen; render(); }
  function back() { const p = PARENT[st.screen]; if (p) go(p); }

  function wire() {
    for (const ph of $$(".phone")) {
      ph.addEventListener("click", (e) => {
        const pick = e.target.closest("[data-pick]");
        if (pick) {
          const [g] = pick.dataset.pick.split(":");
          for (const it of $$(`[data-pick^="${g}:"]`, ph)) $("[data-check]", it)?.remove();
          const chk = document.createElement("span");
          chk.dataset.check = "";
          const set = ph.dataset.icons;
          chk.innerHTML = ico("check", 24, set);
          pick.appendChild(chk);
          return;
        }
        if (e.target.closest("[data-back]")) return back();
        const g = e.target.closest("[data-goto]");
        if (g && g.dataset.goto) go(g.dataset.goto);
      });
      // The back gesture: a drag that starts at the left edge and travels. Android's system gesture does this on the phone.
      const edge = $(".edge", ph), bubble = $(".bubble", ph);
      let x0 = null;
      const sc = () => ph.getBoundingClientRect().width / 360;
      edge.addEventListener("pointerdown", (e) => { x0 = e.clientX; edge.setPointerCapture(e.pointerId); bubble.style.opacity = 1; });
      edge.addEventListener("pointermove", (e) => {
        if (x0 === null) return;
        const dx = Math.max(0, Math.min(80, (e.clientX - x0) / sc()));
        bubble.style.transform = `translateX(${dx - 46}px)`;
      });
      const end = (e) => {
        if (x0 === null) return;
        const dx = (e.clientX - x0) / sc();
        x0 = null; bubble.style.opacity = 0; bubble.style.transform = "translateX(-48px)";
        if (dx > 70) back();
      };
      edge.addEventListener("pointerup", end);
      edge.addEventListener("pointercancel", () => { x0 = null; bubble.style.opacity = 0; });
    }
  }

  // ------------------------------------------------------------------ inventory
  function renderInventory() {
    const m = D.meta;
    const used = m.filter((i) => !i.isNew && !i.unreferenced);
    const row = (i) => `<tr>
      <td><code>ic_${i.key}</code>${i.unreferenced ? '<span class="tag">unreferenced today</span>' : ""}${i.isNew ? '<span class="tag">new for the redesign</span>' : ""}<br><span style="color:var(--chrome-dim)">${i.role}</span><br><span style="color:var(--chrome-dim);font-size:12px">${i.where}</span></td>
      ${SETS.map(([k]) => { const d = D.sets[k][i.key]; const cls = d.substitute ? "absent" : (d.synthesised ? "sub" : ""); return `<td><div class="glyph ${cls}">${ico(i.key, 28, k)}</div></td>`; }).join("")}
      <td style="font-size:12px">${i.missing ? `<div class="gap">${["lucide","phosphor","tabler"].filter((s) => i.missing[s]).map((s) => `<b>${s}</b>: ${i.missing[s]}`).join("<br>")}</div>` : ""}${i.note ? `<div style="color:var(--chrome-dim)">${i.note}</div>` : ""}${i.filled ? '<div style="color:var(--chrome-dim)">Filled in the app today.</div>' : ""}</td></tr>`;
    $("#tab-inventory").innerHTML = `<div class="inv">
      <h2>Every icon the app uses today (${used.length}), plus two unreferenced and one new</h2>
      <p class="hint">Source: <code>app/src/main/res/drawable/ic_*.xml</code> and where each is set in the Kotlin and layouts at the commit this branch was cut from. Red dashed = the set lacks the glyph and the page falls back to the app's own mark. Orange dashed = drawn by the page because the app (or the set) has no such file.</p>
      <table><thead><tr><th>Icon</th>${SETS.map(([, n]) => `<th>${n}</th>`).join("")}<th>Gaps and notes</th></tr></thead><tbody>${m.map(row).join("")}</tbody></table>
      <h2>Icons a set lacks</h2>
      <ul>
        <li><b>ic_dont_move</b> (hold still, setup tips): no set has a matching glyph. Lucide <code>person-standing</code> and Phosphor <code>person-simple</code> are nearest and are used; Tabler has nothing close enough, so the app's own mark stands in.</li>
        <li><b>Filled variants</b>: Lucide ships none. play, pause, stop, skip-forward, flame are the outline icons with a fill applied; check-circle is the set's circle with the page's disc and check. Phosphor (fill weight) and Tabler (filled) ship real ones.</li>
        <li><b>ic_menu</b>: the app's mark has a short third line. Lucide and Tabler <code>align-left</code> and Phosphor <code>list-dashes</code> match it; plain three-line <code>menu</code> / <code>list</code> also exist in all three.</li>
        <li><b>ic_rec</b>: a plain ring in each set. Phosphor <code>record</code> and Lucide <code>circle-dot</code> carry an inner dot and would clash with the red recording state.</li>
        <li><b>Not icons, so not covered by a set</b>: the arcs mark (<code>mark_arcs</code>), the compatible-with-Strava logo (brand artwork, must stay as supplied), the launcher icon, and the reminder notification icon (a monochrome Android drawable, <code>ic_flame</code>).</li>
      </ul></div>`;
  }

  // ------------------------------------------------------------------ chrome
  document.addEventListener("click", (e) => {
    const b = e.target.closest(".seg button");
    if (b) { const k = b.parentElement.dataset.set; st[k] = b.dataset.v; render(); return; }
    const t = e.target.closest("[data-tab]");
    if (t) { st.tab = t.dataset.tab; render(); }
  });
  $("#real").addEventListener("change", (e) => { st.real = e.target.checked ? "1" : "0"; render(); });
  $("#targets").addEventListener("change", (e) => { st.targets = e.target.checked ? "1" : "0"; render(); });
  $("#reset").addEventListener("click", () => { Object.assign(st, DEFAULTS); render(); });
  document.addEventListener("keydown", (e) => {
    if (e.target.matches("input,button")) return;
    if (e.key === "Escape" || e.key === "ArrowLeft") back();
  });
  window.addEventListener("resize", fit);

  const mk = (set, items) => $(`[data-set="${set}"]`).innerHTML = items.map(([v, n]) => `<button data-v="${v}" aria-pressed="false">${n}</button>`).join("");
  mk("screen", SCREENS);
  mk("icons", SETS);
  mk("nav", [["done", "DONE pill"], ["bar", "Top bar + back"]]);
  mk("ctl", [["back", "Back ‹"], ["close", "Close ×"]]);
  mk("ttl", [["center", "Centred title"], ["left", "Left title"], ["large", "Large title below"]]);
  mk("type", [["manrope", "Manrope"], ["inter", "Inter"]]);
  mk("sub", [["show", "As today"], ["hide", "Hidden"]]);
  mk("view", [["single", "One phone"], ["icons", "All icon sets"], ["nav", "DONE vs top bar"], ["type", "Manrope vs Inter"]]);
  render();
})();
