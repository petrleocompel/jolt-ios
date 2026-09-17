// Builds fastlane/design_screenshots/compare.html: the design render next to
// the app screenshot for every screen, per appearance, plus screens that
// exist on only one side. Pairing is by name — the app's
// "iPhone 17 Pro-01-Remote-Dashboard.png" matches the design's
// "01-Remote-Dashboard.png".
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "../../fastlane/design_screenshots");
const list = (dir) => (fs.existsSync(dir) ? fs.readdirSync(dir).filter((f) => f.endsWith(".png")) : []);

const design = new Map(list(path.join(root, "design")).map((f) => [f.replace(/\.png$/, ""), `design/${f}`]));
const sections = [];
for (const appearance of ["dark", "light"]) {
  const dir = path.join(root, appearance, "en-US");
  const app = new Map(list(dir).map((f) => [f.replace(/^.*?-(\d\d\w?-)/, "$1").replace(/\.png$/, ""), `${appearance}/en-US/${f}`]));
  if (!app.size) continue;
  const names = [...new Set([...design.keys(), ...app.keys()])].sort();
  const rows = names.map((n) => `
    <section><h2>${n}</h2><div class="pair">
      <figure><figcaption>Design</figcaption>${design.has(n) ? `<img src="${encodeURI(design.get(n))}">` : `<div class="missing">not in design</div>`}</figure>
      <figure><figcaption>App (${appearance})</figcaption>${app.has(n) ? `<img src="${encodeURI(app.get(n))}">` : `<div class="missing">not captured</div>`}</figure>
    </div></section>`);
  sections.push(`<h1>${appearance}</h1>${rows.join("")}`);
}

fs.writeFileSync(path.join(root, "compare.html"), `<!doctype html><meta charset="utf-8"><title>Jolt — design vs app</title>
<style>body{background:#111;color:#ddd;font:14px -apple-system,sans-serif;margin:24px}
h1{text-transform:uppercase;letter-spacing:2px}h2{font-size:14px;margin:32px 0 8px}
.pair{display:flex;gap:24px;align-items:flex-start}figure{margin:0}figcaption{color:#888;margin-bottom:6px}
img{width:360px;border-radius:24px;border:1px solid #333}.missing{width:360px;height:120px;display:grid;place-items:center;border:1px dashed #444;border-radius:24px;color:#777}</style>
${sections.join("")}`);
console.log(`Comparison in ${path.join(root, "compare.html")}`);
