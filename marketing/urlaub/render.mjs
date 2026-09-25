// Renders keep-urlaub.html to an MP4, one deterministic frame at a time.
//
//   node render.mjs                 → keep-urlaub-24s.mp4
//   node render.mjs --still 5.2     → still-5.2.png (one frame, for checking)
//
// Env: FFMPEG=/path/to/ffmpeg (default "ffmpeg"), CHROMIUM=/path/to/chrome
// (default: whatever Playwright installed).
//
// Frames are piped straight into ffmpeg rather than written to disk: 600
// full-HD stills would otherwise be a quarter of a gigabyte of temp files.
import { chromium } from 'playwright';
import { spawn } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';

const here = path.dirname(fileURLToPath(import.meta.url));
const FPS = 30, SECONDS = 24, W = 1080, H = 1920;
const args = process.argv.slice(2);
const stillAt = args[0] === '--still' ? parseFloat(args[1]) : null;

const browser = await chromium.launch(process.env.CHROMIUM ? { executablePath: process.env.CHROMIUM } : {});
const page = await browser.newPage({ viewport: { width: W, height: H }, deviceScaleFactor: 1 });
await page.goto(pathToFileURL(path.join(here, 'keep-urlaub.html')).href);
// Fonts and the end-card image have to be in before the first frame, or the
// opening seconds render in a fallback face and the end card pops in late.
await page.evaluate(async () => {
  await document.fonts.ready;
  await Promise.all([...document.images].map(i => i.complete ? 0 : new Promise(r => { i.onload = i.onerror = r; })));
});

if (stillAt !== null) {
  await page.evaluate(t => window.render(t), stillAt);
  const out = path.join(here, `still-${stillAt}.png`);
  await page.screenshot({ path: out });
  console.log(out);
  await browser.close();
  process.exit(0);
}

const out = path.join(here, 'keep-urlaub-24s.mp4');
const ff = spawn(process.env.FFMPEG || 'ffmpeg', [
  '-y', '-loglevel', 'error',
  '-f', 'image2pipe', '-framerate', String(FPS), '-c:v', 'mjpeg', '-i', '-',
  '-c:v', 'libx264', '-preset', 'slow', '-crf', '17', '-pix_fmt', 'yuv420p',
  '-movflags', '+faststart', out,
], { stdio: ['pipe', 'inherit', 'inherit'] });
const done = new Promise((res, rej) => ff.on('close', c => c === 0 ? res() : rej(new Error('ffmpeg ' + c))));

const total = FPS * SECONDS;
for (let i = 0; i < total; i++) {
  await page.evaluate(t => window.render(t), i / FPS);
  const jpg = await page.screenshot({ type: 'jpeg', quality: 95 });
  if (!ff.stdin.write(jpg)) await new Promise(r => ff.stdin.once('drain', r));
  if (i % 60 === 0) process.stdout.write(`\r${Math.round(i / total * 100)} %`);
}
ff.stdin.end();
await done;
await browser.close();
console.log(`\r100 % → ${out}`);
