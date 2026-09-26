// Rendert keep-bumper.html Bild für Bild zu einem MP4.
//
//   node render.mjs                    → bumper-video.mp4   (2160×3840, ohne Ton, fürs App-Bundle)
//   node render.mjs --preview          → vorschau-hoch.mp4  (1080×1920, mit Beispieltitel)
//   node render.mjs --preview --wide   → vorschau-quer.mp4  (1920×1080, Ausschnitt im Querformat)
//   node render.mjs --still 1.2        → still-1.2.png
//
// Danach legt `python3 sound.py` den Ton darunter und schreibt
// Keep/Resources/Videos/BumperIntro.mp4.
// Env: FFMPEG=/pfad/zu/ffmpeg, CHROMIUM=/pfad/zu/chrome.
import { chromium } from 'playwright';
import { spawn } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';

const here = path.dirname(fileURLToPath(import.meta.url));
const FPS = 30, SECONDS = 2.5;
const args = process.argv.slice(2);
const has = f => args.includes(f);
const stillAt = has('--still') ? parseFloat(args[args.indexOf('--still') + 1]) : null;
const preview = has('--preview'), wide = has('--wide');
const W = wide ? 1920 : 1080, H = wide ? 1080 : 1920;
// Das Bundle-Video in doppelter Auflösung: die App skaliert es auf die
// Export-Leinwand, bei 4K sind das 2160×3840.
const scale = preview || stillAt !== null ? 1 : 2;

const browser = await chromium.launch(process.env.CHROMIUM ? { executablePath: process.env.CHROMIUM } : {});
const page = await browser.newPage({ viewport: { width: W, height: H }, deviceScaleFactor: scale });
const q = [preview && 'preview', wide && 'wide'].filter(Boolean).join('&');
await page.goto(pathToFileURL(path.join(here, 'keep-bumper.html')).href + (q ? '?' + q : ''));
await page.evaluate(() => document.fonts.ready);

if (stillAt !== null) {
  await page.evaluate(t => window.render(t), stillAt);
  const out = path.join(here, `still-${stillAt}${wide ? '-quer' : ''}.png`);
  await page.screenshot({ path: out });
  console.log(out);
  await browser.close();
  process.exit(0);
}

const out = path.join(here, preview ? (wide ? 'vorschau-quer.mp4' : 'vorschau-hoch.mp4') : 'bumper-video.mp4');
const ff = spawn(process.env.FFMPEG || 'ffmpeg', [
  '-y', '-loglevel', 'error',
  '-f', 'image2pipe', '-framerate', String(FPS), '-c:v', 'png', '-i', '-',
  '-c:v', 'libx264', '-preset', 'slow', '-crf', scale > 1 ? '20' : '17', '-pix_fmt', 'yuv420p',
  '-movflags', '+faststart', out,
], { stdio: ['pipe', 'inherit', 'inherit'] });
const done = new Promise((res, rej) => ff.on('close', c => c === 0 ? res() : rej(new Error('ffmpeg ' + c))));

const total = Math.round(FPS * SECONDS);
for (let i = 0; i < total; i++) {
  await page.evaluate(t => window.render(t), i / FPS);
  // PNG statt JPEG: auf dem fast schwarzen Grund zeigt JPEG sonst Blockstufen im Glühen.
  const png = await page.screenshot({ type: 'png' });
  if (!ff.stdin.write(png)) await new Promise(r => ff.stdin.once('drain', r));
}
ff.stdin.end();
await done;
await browser.close();
console.log(out);
