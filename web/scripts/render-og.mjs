// Records the page shared on social sites, /og, into public/og.png (1200 × 630), with its
// animation paused at a moment that shows what it does. Run after `npm run build`.
import { chromium } from "playwright";
import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { extname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("..", import.meta.url));
const dist = join(root, "dist");
const types = { ".html": "text/html", ".css": "text/css", ".js": "text/javascript", ".svg": "image/svg+xml" };
const server = createServer(async (request, response) => {
  let path = join(dist, request.url.split("?")[0]);
  if (!extname(path)) path = join(path, "index.html");
  try {
    const body = await readFile(path);
    response.writeHead(200, { "content-type": types[extname(path)] ?? "application/octet-stream" });
    response.end(body);
  } catch {
    response.writeHead(404).end();
  }
}).listen(4330);

// Seconds into the animation: a window dragged to the left edge, its outline showing.
const moment = Number(process.argv[2] ?? 2.2);
const browser = await chromium.launch(process.env.CHROMIUM ? { executablePath: process.env.CHROMIUM } : {});
const page = await browser.newPage({ viewport: { width: 1200, height: 630 }, deviceScaleFactor: 1 });
await page.goto("http://localhost:4330/og/");
await page.evaluate((seconds) => {
  for (const animation of document.getAnimations()) {
    animation.pause();
    animation.currentTime = seconds * 1000;
  }
}, moment);
await page.screenshot({ path: join(root, "public/og.png") });
await browser.close();
server.close();
console.log("Wrote public/og.png");
