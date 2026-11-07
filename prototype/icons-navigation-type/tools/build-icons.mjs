// Builds icons.js from the app's own vector drawables and the three open icon sets.
//
//   NM=/path/to/node_modules node tools/build-icons.mjs
//
// NM needs lucide-static, @phosphor-icons/core and @tabler/icons. The chosen SVGs are copied
// into icons/<set>/ the first time, so the page and this script work without node_modules
// afterwards. Run from prototype/icons-navigation-type/ in the repo.

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(here, "..");
const repo = path.join(root, "..", "..");
const res = path.join(repo, "app/src/main/res/drawable");
const NM = process.env.NM;

// key: the app's drawable (ic_<key>), or a new icon the redesign needs.
// For each set: [file name, "outline" | "filled"]. A null file means the set has no
// equivalent glyph; `sub` then names the closest substitute that the page draws instead.
const ICONS = [
  { key: "flip", role: "Switch camera", where: "Camera screen, left slot of the action row", filled: false,
    lucide: ["switch-camera"], phosphor: ["camera-rotate"], tabler: ["camera-rotate"] },
  { key: "menu", role: "Open the menu", where: "Camera screen, top band", filled: false,
    lucide: ["align-left"], phosphor: ["list-dashes"], tabler: ["align-left"],
    note: "Today's mark has a short third line; align-left / list-dashes are the nearest. menu (three equal lines) is the plainer option in all three." },
  { key: "rec", role: "Record the film (REC)", where: "Camera screen, top band; red while filming", filled: false,
    lucide: ["circle"], phosphor: ["circle"], tabler: ["circle"],
    note: "A plain ring in every set, as today. Phosphor record and Lucide circle-dot carry an inner dot that would collide with the red recording state." },
  { key: "minus", role: "Take a rep off", where: "Camera screen, count row", filled: false,
    lucide: ["minus"], phosphor: ["minus"], tabler: ["minus"] },
  { key: "plus", role: "Add a rep", where: "Camera screen, count row", filled: false,
    lucide: ["plus"], phosphor: ["plus"], tabler: ["plus"] },
  { key: "play", role: "Start / resume (shutter)", where: "Camera screen shutter; session page and Progress rows", filled: true,
    lucide: ["play"], phosphor: ["play"], tabler: ["player-play"] },
  { key: "pause", role: "Pause", where: "Camera screen shutter while running", filled: true,
    lucide: ["pause"], phosphor: ["pause"], tabler: ["player-pause"] },
  { key: "stop", role: "Stop / END", where: "Camera screen left slot while a workout is live", filled: true,
    lucide: ["square"], phosphor: ["stop"], tabler: ["player-stop"] },
  { key: "skip", role: "Skip the setup check", where: "Camera screen, right slot of the action row", filled: true,
    lucide: ["skip-forward"], phosphor: ["skip-forward"], tabler: ["player-skip-forward"] },
  { key: "check", role: "Chosen row", where: "Movements sheet", filled: false,
    lucide: ["check"], phosphor: ["check"], tabler: ["check"] },
  { key: "check_filled", role: "Reached (filled disc)", where: "Help, tier list", filled: true,
    lucide: ["circle-check", "synth"], phosphor: ["check-circle"], tabler: ["circle-check"],
    note: "Lucide ships no filled variant: the page draws the disc in the ok colour and the set's own check over it." },
  { key: "chevron_left", role: "Back", where: "Pushed pages, tour", filled: false,
    lucide: ["chevron-left"], phosphor: ["caret-left"], tabler: ["chevron-left"] },
  { key: "chevron_right", role: "Row opens a page", where: "Menu rows, Progress rows, You", filled: false,
    lucide: ["chevron-right"], phosphor: ["caret-right"], tabler: ["chevron-right"] },
  { key: "flame", role: "Streak", where: "Progress, session page, You; also the reminder's notification icon", filled: true,
    lucide: ["flame"], phosphor: ["flame"], tabler: ["flame"],
    note: "The notification icon must be a monochrome Android drawable whatever the set." },
  { key: "frame", role: "Keep head and feet in shot", where: "Setup tips", filled: false,
    lucide: ["scan"], phosphor: ["corners-out"], tabler: ["scan"] },
  { key: "link", role: "Link", where: "Help", filled: false,
    lucide: ["link"], phosphor: ["link"], tabler: ["link"] },
  { key: "external", role: "Opens outside the app", where: "Help, tour", filled: false,
    lucide: ["arrow-up-right"], phosphor: ["arrow-up-right"], tabler: ["arrow-up-right"] },
  { key: "phone_stand", role: "Stand the phone up", where: "Setup tips", filled: false,
    lucide: ["smartphone"], phosphor: ["device-mobile"], tabler: ["device-mobile"] },
  { key: "dont_move", role: "Hold still while the bar is learned", where: "Setup tips, drawn in the caution colour", filled: false,
    lucide: ["person-standing"], phosphor: ["person-simple"], tabler: [null],
    missing: {
      lucide: "No \"hold still\" glyph; person-standing is the nearest (a figure, not a target with ticks).",
      phosphor: "No \"hold still\" glyph; person-simple is the nearest (a figure, not a target with ticks).",
      tabler: "No \"hold still\" or standing-figure glyph close enough (walk shows motion, the opposite); the page draws the app's own mark.",
    } },
  { key: "ring_empty", role: "Not reached yet (empty ring)", where: "Help, tier list", filled: false,
    lucide: ["circle"], phosphor: ["circle"], tabler: ["circle"] },
  { key: "music", role: "Music (unreferenced today)", where: "Not used since music moved to the menu", filled: false, unreferenced: true,
    lucide: ["music"], phosphor: ["music-notes"], tabler: ["music"] },
  { key: "voice", role: "Voice (unreferenced today)", where: "Not used since voice moved to the menu", filled: false, unreferenced: true,
    lucide: ["volume-2"], phosphor: ["speaker-high"], tabler: ["volume"] },
  // New: needed by the top-bar close shape, not in the app today.
  { key: "close", role: "Close (new)", where: "Top bar, close shape", filled: false, isNew: true,
    lucide: ["x"], phosphor: ["x"], tabler: ["x"], current: "synth" },
];

const readSet = {
  lucide: (n) => fs.readFileSync(path.join(root, "icons/lucide", n + ".svg"), "utf8"),
  phosphor: (n, filled) => fs.readFileSync(path.join(root, "icons/phosphor", n + (filled ? "-fill" : "") + ".svg"), "utf8"),
  tabler: (n, filled) => fs.readFileSync(path.join(root, "icons/tabler", n + (filled ? "-filled" : "") + ".svg"), "utf8"),
};

function copyFromNodeModules(set, name, filled) {
  if (!NM) return;
  const dst = path.join(root, "icons", set);
  fs.mkdirSync(dst, { recursive: true });
  if (set === "lucide") fs.copyFileSync(path.join(NM, "lucide-static/icons", name + ".svg"), path.join(dst, name + ".svg"));
  if (set === "phosphor") {
    const w = filled ? "fill" : "regular";
    const f = name + (filled ? "-fill" : "") + ".svg";
    fs.copyFileSync(path.join(NM, "@phosphor-icons/core/assets", w, f), path.join(dst, f));
  }
  if (set === "tabler") {
    const dir = filled ? "filled" : "outline";
    const f = name + (filled ? "-filled" : "") + ".svg";
    // @tabler/icons names filled files without a suffix; store them with one so both weights can live in one folder.
    fs.copyFileSync(path.join(NM, "@tabler/icons/icons", dir, name + ".svg"), path.join(dst, f));
  }
}

const inner = (svg) =>
  svg
    .replace(/<!--[\s\S]*?-->/g, "")
    .replace(/<svg[^>]*>/, "")
    .replace(/<\/svg>\s*$/, "")
    .replace(/<path stroke="none" d="M0 0h24v24H0z" fill="none"\s*\/>/, "")
    .trim();

// ---- the app's own icons, from the vector drawables ----
function parseAndroid(file) {
  const xml = fs.readFileSync(file, "utf8").replace(/<!--[\s\S]*?-->/g, "");
  const paths = [...xml.matchAll(/<path\b([\s\S]*?)\/>/g)].map((m) => {
    const a = {};
    for (const x of m[1].matchAll(/android:(\w+)="([^"]*)"/g)) a[x[1]] = x[2];
    return a;
  });
  const colour = (c) => {
    if (!c || c === "#00000000") return "none";
    if (c === "@color/state_ok") return "var(--ok)";
    if (c === "#FFFFFFFF") return "currentColor";
    if (c === "#FF000000") return "#000";
    const m = /^#([0-9A-F]{2})([0-9A-F]{6})$/i.exec(c);
    if (m) return { c: "currentColor", o: (parseInt(m[1], 16) / 255).toFixed(2) };
    return "currentColor";
  };
  const body = paths
    .map((p) => {
      const at = [`d="${p.pathData}"`];
      const f = colour(p.fillColor), s = colour(p.strokeColor);
      const paint = (name, v) => {
        if (typeof v === "object") { at.push(`${name}="${v.c}"`, `${name}-opacity="${v.o}"`); }
        else at.push(`${name}="${v}"`);
      };
      paint("fill", f); paint("stroke", s);
      if (p.strokeWidth) at.push(`stroke-width="${p.strokeWidth}"`);
      if (p.strokeLineCap) at.push(`stroke-linecap="${p.strokeLineCap}"`);
      if (p.strokeLineJoin) at.push(`stroke-linejoin="${p.strokeLineJoin}"`);
      if (p.fillType === "evenOdd") at.push(`fill-rule="evenodd"`);
      return `<path ${at.join(" ")}/>`;
    })
    .join("");
  return body;
}

const out = { current: {}, lucide: {}, phosphor: {}, tabler: {} };
const report = [];

for (const ic of ICONS) {
  // current
  if (ic.current !== "synth") {
    const body = parseAndroid(path.join(res, `ic_${ic.key}.xml`));
    fs.writeFileSync(path.join(root, "icons/current", `ic_${ic.key}.svg`),
      `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">${body}</svg>\n`);
    out.current[ic.key] = { vb: "0 0 24 24", kind: "raw", body };
  } else {
    // The app has no close mark today. Drawn in the house stroke (2.2, round) so "Current" is complete.
    out.current[ic.key] = { vb: "0 0 24 24", kind: "raw", synthesised: true,
      body: '<path d="M6,6 L18,18 M18,6 L6,18" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>' };
  }

  for (const set of ["lucide", "phosphor", "tabler"]) {
    const [name, special] = ic[set];
    if (name === null) {
      out[set][ic.key] = { absent: true };
      report.push({ key: ic.key, set, problem: ic.missing?.[set] || "no equivalent" });
      continue;
    }
    // Phosphor and Tabler ship real filled variants; Lucide does not.
    const useFilled = ic.filled && set !== "lucide";
    copyFromNodeModules(set, name, useFilled);
    const svg = readSet[set](name, useFilled);
    const body = inner(svg);
    if (set === "lucide") {
      if (special === "synth") {
        // circle-check: <circle/> + <path/>. Fill the disc, draw the check dark.
        const circle = /<circle[^>]*\/>/.exec(body)[0].replace("<circle", '<circle fill="var(--ok)" stroke="none"');
        const check = /<path[^>]*\/>/.exec(body)[0].replace("<path", '<path stroke="#000"');
        out.lucide[ic.key] = { vb: "0 0 24 24", kind: "raw", body: circle + check };
      } else {
        out.lucide[ic.key] = { vb: "0 0 24 24", kind: "stroke", sw: 2, fillIt: ic.filled, body };
      }
    } else if (set === "phosphor") {
      out.phosphor[ic.key] = { vb: "0 0 256 256", kind: "fill", body };
    } else {
      out.tabler[ic.key] = useFilled
        ? { vb: "0 0 24 24", kind: "fill", body }
        : { vb: "0 0 24 24", kind: "stroke", sw: 2, body };
    }
    if (ic.missing?.[set]) report.push({ key: ic.key, set, problem: ic.missing[set] });
  }
}

// For icons a set lacks, the page draws the app's own mark so the screen is not left with a hole.
for (const ic of ICONS) for (const set of ["lucide", "phosphor", "tabler"]) {
  if (out[set][ic.key].absent) out[set][ic.key] = { ...out.current[ic.key], substitute: "current" };
}

// Filled-variant gaps, listed once.
const lucideFilled = ICONS.filter((i) => i.filled).map((i) => i.key);

const meta = ICONS.map(({ key, role, where, note, unreferenced, isNew, missing, filled }) =>
  ({ key, role, where, note, unreferenced: !!unreferenced, isNew: !!isNew, missing: missing || null, filled }));

const js =
  "// Generated by tools/build-icons.mjs. Do not edit by hand.\n" +
  "window.ICON_DATA = " + JSON.stringify({ sets: out, meta, lucideFilledGaps: lucideFilled }, null, 1) + ";\n";
fs.writeFileSync(path.join(root, "icons.js"), js);
console.log("icons.js written:", ICONS.length, "icons;", report.length, "gaps");
for (const r of report) console.log(" gap", r.set, r.key, "-", r.problem);
