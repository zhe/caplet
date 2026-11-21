// Renders every clip of demo.html frame by frame and encodes it with ffmpeg.
//
//   NODE_PATH=<dir containing playwright> node scripts/demo/record.cjs [clip ...]
//
// Writes docs/demos/<n>-<clip>.mp4 and .gif, a smaller GIF for the README in docs/demos/small/, plus caplet-demo.mp4 with all clips in a row.
const { chromium } = require('playwright');
const { spawn, execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const FPS = 60;
const root = path.resolve(__dirname, '../..');
const out = path.join(root, 'docs/demos');
const page_url = 'file://' + path.join(__dirname, 'demo.html');

function encode(file) {
  const ff = spawn('ffmpeg', ['-y', '-loglevel', 'error', '-f', 'image2pipe', '-framerate', String(FPS), '-i', '-',
    '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '18', '-preset', 'slow', '-movflags', '+faststart', file],
  { stdio: ['pipe', 'inherit', 'inherit'] });
  const done = new Promise((resolve, reject) => ff.on('close', (code) => code ? reject(new Error(`ffmpeg ${code}`)) : resolve()));
  return { ff, done };
}

(async () => {
  fs.mkdirSync(path.join(out, 'small'), { recursive: true });
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1280, height: 720 }, deviceScaleFactor: 1.5 });
  await page.goto(page_url);
  await page.evaluate(() => document.fonts.ready);
  const all = await page.evaluate(() => Object.keys(window.CLIPS));
  const names = process.argv.slice(2).length ? process.argv.slice(2) : all;

  const mp4s = [];
  for (const name of names) {
    const n = all.indexOf(name) + 1;
    const base = path.join(out, `${n}-${name}`);
    const duration = await page.evaluate((c) => { window.setClip(c); return window.CLIPS[c].duration; }, name);
    await page.waitForLoadState('networkidle');
    const { ff, done } = encode(base + '.mp4');
    const frames = Math.round(duration / 1000 * FPS);
    for (let f = 0; f < frames; f++) {
      await page.evaluate((t) => window.render(t), f * 1000 / FPS);
      const png = await page.screenshot({ type: 'png' });
      if (!ff.stdin.write(png)) await new Promise((r) => ff.stdin.once('drain', r));
    }
    ff.stdin.end();
    await done;
    execFileSync('ffmpeg', ['-y', '-loglevel', 'error', '-i', base + '.mp4', '-vf',
      'fps=25,scale=960:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a',
      base + '.gif']);
    // Smaller copy for the README.
    execFileSync('ffmpeg', ['-y', '-loglevel', 'error', '-i', base + '.mp4', '-vf',
      'fps=20,scale=720:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=full[p];[b][p]paletteuse=dither=bayer:bayer_scale=4',
      path.join(out, 'small', path.basename(base) + '.gif')]);
    mp4s.push(base + '.mp4');
    console.log(`${name}: ${frames} frames`);
  }
  await browser.close();

  if (names.length === all.length) {
    const list = path.join(out, 'list.txt');
    fs.writeFileSync(list, mp4s.map((f) => `file '${f}'`).join('\n'));
    execFileSync('ffmpeg', ['-y', '-loglevel', 'error', '-f', 'concat', '-safe', '0', '-i', list, '-c', 'copy', path.join(out, 'caplet-demo.mp4')]);
    fs.unlinkSync(list);
  }
})();
