// Records each feature's spot as a square 1080 px video with a transparent background:
// WebM (VP9 with alpha) into public/spots, and with --mov also MOV (ProRes 4444, for video
// editors and Safari-friendly exports; large, so not kept in git).
// Usage: npm run build && npm run render-spots [-- <id> ...] [--mov] [--sheet]
// --sheet only writes a contact sheet of a few frames per spot, to check them.
// Needs ffmpeg, and Playwright's Chromium.
import { chromium } from "playwright";
import { createServer } from "node:http";
import { readFile, mkdir, rm } from "node:fs/promises";
import { existsSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { extname, join } from "node:path";

const SIZE = 1080;
const FPS = 30;
const dist = new URL("../dist/", import.meta.url).pathname;
const out = new URL("../public/spots/", import.meta.url).pathname;
const frames = new URL("../.frames/", import.meta.url).pathname;
const args = process.argv.slice(2);
const sheet = args.includes("--sheet");
const mov = args.includes("--mov");
const only = args.filter((arg) => !arg.startsWith("--"));

const types = { ".html": "text/html", ".css": "text/css", ".js": "text/javascript", ".svg": "image/svg+xml" };
const server = createServer(async (request, response) => {
  let path = join(dist, decodeURIComponent(request.url.split("?")[0]));
  if (!extname(path)) path = join(path, "index.html");
  try {
    const body = await readFile(path);
    response.writeHead(200, { "content-type": types[extname(path)] ?? "application/octet-stream" });
    response.end(body);
  } catch {
    response.writeHead(404).end();
  }
}).listen(4329);

const { features } = await import("../src/data/features.ts").catch(async () => {
  // Plain Node can't import TypeScript: read the ids and lengths from the built pages instead.
  const ids = (await import("node:fs")).readdirSync(join(dist, "spots"));
  return { features: ids.map((id) => ({ id, seconds: null })) };
});

const browser = await chromium.launch(existsSync("/opt/pw-browsers/chromium") ? { executablePath: "/opt/pw-browsers/chromium" } : {});
const page = await browser.newPage({ viewport: { width: SIZE, height: SIZE } });
await mkdir(out, { recursive: true });

for (const feature of features.filter((f) => !only.length || only.includes(f.id))) {
  await page.goto(`http://localhost:4329/spots/${feature.id}/`);
  await page.waitForTimeout(300);
  const seconds = await page.evaluate(() => parseFloat(getComputedStyle(document.querySelector(".spot")).getPropertyValue("--d")));
  const seek = (ms) => page.evaluate((ms) => {
    for (const animation of document.getAnimations()) { animation.pause(); animation.currentTime = ms; }
  }, ms);

  if (sheet) {
    const shots = [];
    for (const t of [0, 0.15, 0.3, 0.45, 0.6, 0.75, 0.9, 1]) {
      await seek(t * seconds * 1000 - (t === 1 ? 1 : 0));
      shots.push(`${frames}${feature.id}-${String(Math.round(t * 100)).padStart(3, "0")}.png`);
      await mkdir(frames, { recursive: true });
      await page.screenshot({ path: shots.at(-1) });
    }
    execFileSync("ffmpeg", ["-y", "-loglevel", "error", ...shots.flatMap((s) => ["-i", s]),
      "-filter_complex", `${shots.map((_, i) => `[${i}]scale=360:360,pad=380:380:10:10:color=0x777777[s${i}]`).join(";")};${shots.map((_, i) => `[s${i}]`).join("")}xstack=inputs=${shots.length}:layout=0_0|w0_0|w0+w1_0|w0+w1+w2_0|0_h0|w0_h0|w0+w1_h0|w0+w1+w2_h0`,
      `${frames}${feature.id}-sheet.png`]);
    console.log(`${feature.id}: ${frames}${feature.id}-sheet.png`);
    continue;
  }

  await rm(frames, { recursive: true, force: true });
  await mkdir(frames, { recursive: true });
  const count = Math.round(seconds * FPS);
  for (let frame = 0; frame < count; frame++) {
    await seek((frame / FPS) * 1000);
    await page.screenshot({ path: `${frames}${String(frame).padStart(4, "0")}.png`, omitBackground: true });
  }
  const input = ["-y", "-loglevel", "error", "-framerate", String(FPS), "-i", `${frames}%04d.png`];
  execFileSync("ffmpeg", [...input, "-c:v", "libvpx-vp9", "-pix_fmt", "yuva420p", "-b:v", "0", "-crf", "32", "-row-mt", "1", `${out}${feature.id}.webm`]);
  if (mov) execFileSync("ffmpeg", [...input, "-c:v", "prores_ks", "-profile:v", "4444", "-pix_fmt", "yuva444p10le", `${out}${feature.id}.mov`]);
  console.log(`${feature.id}: ${count} frames → public/spots/${feature.id}.webm${mov ? " and .mov" : ""}`);
}

if (!sheet) await rm(frames, { recursive: true, force: true }).catch(() => {});
await browser.close();
server.close();
