// 原图只裁切、对齐与最近邻缩小；不重新绘制生成素材。node export_ch02_v1.cjs
const fs = require('node:fs');
const path = require('node:path');
let sharp;
try { sharp = require('sharp'); }
catch (_) { sharp = require(process.env.CH02_SHARP_PATH || path.join(process.env.USERPROFILE, '.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp')); }
const root = __dirname;
const output = path.join(root, 'runtime/ch02_v1');
const specs = [['overload', 'robots', 24], ['builder', 'enemies', 22], ['special_ore', 'facilities', 48]];
function bbox(data, width, height) {
  let l = width, t = height, r = -1, b = -1;
  for (let y = 0; y < height; y++) for (let x = 0; x < width; x++) {
    if (data[(y * width + x) * 4 + 3] < 96) continue;
    l = Math.min(l, x); t = Math.min(t, y); r = Math.max(r, x); b = Math.max(b, y);
  }
  if (r < l) throw new Error('Empty alpha frame');
  return {left: l, top: t, width: r - l + 1, height: b - t + 1};
}
async function main() {
  fs.mkdirSync(path.join(output, 'ui'), {recursive: true});
  const manifest = [];
  for (const [kind, folder, size] of specs) {
    const source = path.join(root, 'source/ch02_v1', `${kind}_generated.png`);
    const meta = await sharp(source).metadata();
    if (meta.width % 3) throw new Error('Expected three equal cells');
    const cw = meta.width / 3, ch = meta.height;
    const frames = [];
    for (let i = 0; i < 3; i++) {
      const cell = await sharp(source).extract({left: i * cw, top: 0, width: cw, height: ch}).ensureAlpha().raw().toBuffer();
      const bounds = bbox(cell, cw, ch);
      frames.push({bounds, cell});
    }
    const factor = Math.min((size - 2) / Math.max(...frames.map(f => f.bounds.width)), (size - 2) / Math.max(...frames.map(f => f.bounds.height)));
    const sheets = [];
    const pixelBounds = [];
    fs.mkdirSync(path.join(output, folder), {recursive: true});
    for (let i = 0; i < 3; i++) {
      const f = frames[i];
      const w = Math.max(1, Math.round(f.bounds.width * factor)), h = Math.max(1, Math.round(f.bounds.height * factor));
      const sprite = await sharp(f.cell, {raw: {width: cw, height: ch, channels: 4}}).extract(f.bounds).resize(w, h, {kernel: 'nearest'}).raw().toBuffer();
      for (let p = 3; p < sprite.length; p += 4) sprite[p] = sprite[p] < 96 ? 0 : 255;
      const frame = await sharp({create: {width: size, height: size, channels: 4, background: '#00000000'}}).composite([{input: sprite, raw: {width: w, height: h, channels: 4}, left: Math.floor((size - w) / 2), top: size - 1 - h}]).png().toBuffer();
      await sharp(frame).toFile(path.join(output, folder, `${kind}_${i}.png`));
      const raw = await sharp(frame).raw().toBuffer();
      pixelBounds.push(bbox(raw, size, size));
      sheets.push({input: frame, left: i * size, top: 0});
      if (i === 0) await sharp(frame).resize(24, 24, {kernel: 'nearest'}).toFile(path.join(output, 'ui', `icon_${kind}.png`));
    }
    await sharp({create: {width: size * 3, height: size, channels: 4, background: '#00000000'}}).composite(sheets).png().toFile(path.join(output, folder, `${kind}_sheet.png`));
    manifest.push({kind, sourceSize: [meta.width, meta.height], sourceBounds: frames.map(f => f.bounds), frameSize: size, pixelBounds, sampling: 'nearest; alpha >= 96; common scale; bottom aligned'});
  }
  for (const name of ['laser', 'overload_range', 'chapter']) {
    await sharp(path.join(root, 'source/ch02_v1', `icon_${name}.svg`)).png().toFile(path.join(output, 'ui', `icon_${name}.png`));
  }
  fs.writeFileSync(path.join(output, 'export_manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
  console.log(JSON.stringify(manifest, null, 2));
}
main().catch(e => { console.error(e); process.exitCode = 1; });
