// Renders the Claude Design replica (docs/design/Jolt Replica.dc.html) into
// one PNG per screen, named like the app's DesignReferenceUITests snapshots
// so compare.mjs can pair them up.
//
//   npm install && npx playwright install chromium
//   node render.mjs [--out ../../fastlane/design_screenshots/design]
//
// The prototype is a single stateful component. Every screen is reached by
// dispatching one of its own `data-action` strings (nav:…, push:…, sheet:…,
// toggle:…) through the index sidebar's click handler, so no selector in
// here depends on the prototype's markup beyond the sidebar and the 393×852
// phone frame.
import { chromium } from "playwright";
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, "../..");
const designDir = path.join(repo, "docs/design");
const designFile = "Jolt Replica.dc.html";
const outArg = process.argv.indexOf("--out");
const outDir = path.resolve(outArg > 0 ? process.argv[outArg + 1] : path.join(repo, "fastlane/design_screenshots/design"));

// [screenshot name, actions…]. "scroll" / "scrollSheet" scroll to the bottom;
// "wait" gives the scan list time to appear.
const steps = [
  ["00-FirstRun", "firstrun"],
  ["01-Remote-Dashboard", "nav:remote"],
  ["01b-Remote-NoDevice", "forget"],
  ["01c-Remote-OutOfRange", "link:offline"],
  ["01d-Remote-Connecting", "link:connecting"],
  ["01e-Remote-ConnectFailed", "link:failed"],
  ["02-Remote-StimulusEditor", "nav:remote", "sheet:stim:Zap"],
  ["03-Remote-Customize", "nav:remote", "sheet:customize"],
  ["03b-Remote-Customize-Bottom", "nav:remote", "sheet:customize", "scrollSheet"],
  ["04-Remote-DeviceDetail", "goto:deviceDetail:remote"],
  ["04b-Remote-DeviceDetail-Bottom", "goto:deviceDetail:remote", "scroll"],
  ["04c-Remote-DeviceDetail-OutOfRange", "link:offline", "goto:deviceDetail:remote"],
  ["05-Remote-Diagnostics", "goto:diagnostics:remote"],
  ["05b-Remote-Diagnostics-Bottom", "goto:diagnostics:remote", "scroll"],
  ["06-Remote-ButtonConfig", "goto:buttonConfig:remote"],
  ["07-Remote-ProtocolLab", "goto:deviceDetail:remote", "lab:instant"],
  ["07a-Remote-ProtocolLab-Reading", "goto:deviceDetail:remote", "lab:error", "wait:100"],
  ["07b-Remote-ProtocolLab-ReadFailed", "goto:deviceDetail:remote", "lab:error", "wait:1400"],
  ["08-Remote-BluetoothLog", "goto:btLog:remote"],
  ["09-Remote-ConfirmFire", "nav:remote", "mode:Zap", "mode:Zap", "fire:Zap"],
  ["09b-Remote-HoldMode", "nav:remote", "mode:Vibe"],
  ["09c-Remote-NoDeviceFireBanner", "forget", "fire:Zap"],
  ["10-Alarms-List", "nav:alarms"],
  ["11-Alarms-EditExisting", "nav:alarms", "sheet:alarmEdit"],
  ["12-Alarms-EditExisting-Bottom", "nav:alarms", "sheet:alarmEdit", "scrollSheet"],
  ["13-Alarms-New", "nav:alarms", "sheet:alarmNew"],
  ["14-Alarms-Ringing", "goto:alarmActive:alarms"],
  ["15-Alarms-ChallengeMath", "goto:chMath:alarms"],
  ["16-Alarms-ChallengeJacks", "goto:chJacks:alarms", "ch:jack", "ch:jack", "ch:jack"],
  ["17-Alarms-ChallengeQR", "goto:chQR:alarms"],
  ["20-Friends-SignIn", "signout", "set:authMode:Log In"],
  ["21-Friends-SignUp", "signout", "set:authMode:Sign Up"],
  ["22-Friends-List", "signin"],
  ["23-Friends-AddFriend", "signin", "sheet:addFriend"],
  ["24-Friends-Profile", "goto:profile:friends"],
  ["24b-Friends-Profile-Bottom", "goto:profile:friends", "scroll"],
  ["25-Friends-Activity", "goto:activity:friends"],
  ["26-Friends-Detail-NothingAllowed", "goto:friendBob:friends"],
  ["27-Friends-Detail-Composer", "goto:friendAlice:friends"],
  ["28-Friends-Permissions", "goto:permissions:friends"],
  ["29-Friends-Permissions-Bottom", "goto:permissions:friends", "scroll"],
  ["30-Settings-QuickPoke-Off", "set:qpOn:0", "goto:qpSettings:settings"],
  ["31-Settings-QuickPoke-On", "set:qpOn:1", "goto:qpSettings:settings"],
  ["32-Settings-PokeTrigger", "goto:pokeTrigger:settings"],
  ["33-Settings-PokeTrigger-Bottom", "goto:pokeTrigger:settings", "scroll"],
  ["34-Remote-WithQuickPoke", "set:qpOn:1", "nav:remote", "scroll"],
  ["34b-Remote-WithoutQuickPoke", "set:qpOn:0", "nav:remote", "scroll"],
  ["35-Remote-QuickPokeComposer", "set:qpOn:1", "pokestate:none"],
  ["35a-Remote-QuickPokeComposer-Sending", "pokestate:sending"],
  ["36-Remote-QuickPokeComposer-Error", "pokestate:error"],
  ["37-Remote-QuickPokeComposer-NotFound", "pokestate:notfound"],
  ["40-Settings", "nav:settings"],
  ["41-Settings-Bottom", "nav:settings", "scroll"],
  ["42-Settings-Firing", "goto:firing:settings"],
  ["43-Settings-PokeFeedback", "goto:pokeFeedback:settings"],
  ["44-Settings-Notifications", "goto:notifications:settings"],
  ["44b-Settings-Notifications-Arrived", "goto:notifications:settings", "notiftest", "wait:1600"],
  ["45-Settings-PavlokAccount", "goto:pavlokAccount:settings"],
  ["46-Settings-Server", "goto:server:settings"],
  ["47-Settings-About", "goto:about:settings"],
  ["40b-Settings-NoDevice", "forget", "nav:settings"],
  ["40c-Settings-OutOfRange", "link:offline", "nav:settings"],
  ["52-PairDevice", "forget", "nav:settings", "pair"],
  ["52b-PairDevice-Scanning", "forget", "nav:settings", "pair", "scan", "wait:300"],
  ["52c-PairDevice-Found", "forget", "nav:settings", "pair", "scan", "wait:1700"],
  ["52d-PairDevice-ConnectFailed", "forget", "nav:settings", "pair", "scanfail"],
];

const server = http.createServer((req, res) => {
  const file = path.join(designDir, decodeURIComponent(new URL(req.url, "http://x").pathname));
  if (!file.startsWith(designDir) || !fs.existsSync(file)) { res.writeHead(404).end(); return; }
  const type = file.endsWith(".js") ? "text/javascript" : "text/html";
  res.writeHead(200, { "content-type": `${type}; charset=utf-8` }).end(fs.readFileSync(file));
});
await new Promise((r) => server.listen(0, "127.0.0.1", r));
const url = `http://127.0.0.1:${server.address().port}/${encodeURIComponent(designFile)}`;

fs.mkdirSync(outDir, { recursive: true });
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 900, height: 1000 }, deviceScaleFactor: 3 });
page.on("pageerror", (e) => console.error("page error:", e.message));
await page.goto(url);
await page.waitForSelector("aside [data-action]", { timeout: 60_000 });

const dispatch = (action) => page.evaluate((a) => {
  const el = document.querySelector("aside [data-action]");
  const original = el.dataset.action;
  el.dataset.action = a;
  el.click();
  el.dataset.action = original;
}, action);

const scroll = (sheet) => page.evaluate((sheet) => {
  const phone = [...document.querySelectorAll("div")].find((d) => d.style.width === "393px" && d.style.height === "852px");
  const scrollers = [...phone.querySelectorAll("div")].filter((d) =>
    getComputedStyle(d).overflowY === "auto" && d.scrollHeight > d.clientHeight);
  const main = scrollers.find((d) => d.style.top === "54px");
  for (const d of scrollers) if ((d === main) !== sheet) d.scrollTop = d.scrollHeight;
}, sheet);

for (const [name, ...actions] of steps) {
  // Fresh page per screen: the prototype runs timers (connecting → failed,
  // banners, scans) that would otherwise leak into the next screenshot.
  await page.goto(url);
  await page.waitForSelector("aside [data-action]", { timeout: 60_000 });
  for (const action of actions) {
    if (action === "scroll") await scroll(false);
    else if (action === "scrollSheet") await scroll(true);
    else if (action.startsWith("wait:")) await page.waitForTimeout(Number(action.slice(5)));
    else await dispatch(action);
  }
  await page.waitForTimeout(250);
  const phone = page.locator('div[style*="width: 393px"][style*="height: 852px"]').first();
  await phone.screenshot({ path: path.join(outDir, `${name}.png`) });
  console.log("rendered", name);
}

await browser.close();
server.close();
console.log(`Design screenshots in ${outDir}`);
