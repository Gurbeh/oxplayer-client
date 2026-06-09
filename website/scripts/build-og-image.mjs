#!/usr/bin/env node
/**
 * Build a 1200×630 Open Graph image for link previews (WhatsApp, Telegram, etc.).
 * Output: public/images/og-image.png (target ≤ 300 KB).
 *
 * Dev-only (requires `sharp` in devDependencies). CI uses the committed og-image.png.
 * Regenerate locally: npm run build:og-image
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

let sharp;
try {
  sharp = (await import("sharp")).default;
} catch {
  console.error(
    "[build-og-image] sharp is not installed. Run: npm install && npm run build:og-image",
  );
  process.exit(1);
}

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const imagesDir = path.join(root, "public", "images");
const outPath = path.join(imagesDir, "og-image.png");
const logoPath = path.join(imagesDir, "logo.png");
const showcasePath = path.join(imagesDir, "app-showcase-0.png");

const W = 1200;
const H = 630;

const backgroundSvg = Buffer.from(
  `<svg width="${W}" height="${H}" xmlns="http://www.w3.org/2000/svg">
    <defs>
      <linearGradient id="bg" x1="0%" y1="0%" x2="100%" y2="100%">
        <stop offset="0%" stop-color="#0f172a"/>
        <stop offset="55%" stop-color="#111827"/>
        <stop offset="100%" stop-color="#1a0f0a"/>
      </linearGradient>
      <radialGradient id="glow" cx="75%" cy="35%" r="45%">
        <stop offset="0%" stop-color="#EDAE49" stop-opacity="0.22"/>
        <stop offset="100%" stop-color="#EDAE49" stop-opacity="0"/>
      </radialGradient>
    </defs>
    <rect width="${W}" height="${H}" fill="url(#bg)"/>
    <rect width="${W}" height="${H}" fill="url(#glow)"/>
  </svg>`,
);

const textSvg = Buffer.from(
  `<svg width="520" height="360" xmlns="http://www.w3.org/2000/svg">
    <text x="0" y="56" font-family="Segoe UI, system-ui, sans-serif" font-size="52" font-weight="700" fill="#f8fafc">OXPlayer</text>
    <text x="0" y="118" font-family="Segoe UI, system-ui, sans-serif" font-size="30" font-weight="600" fill="#EDAE49">Your Personal Telegram Cinema</text>
    <text x="0" y="168" font-family="Segoe UI, system-ui, sans-serif" font-size="20" fill="#cbd5e1">Netflix-style media library</text>
    <text x="0" y="198" font-family="Segoe UI, system-ui, sans-serif" font-size="20" fill="#cbd5e1">for videos you send to the bot</text>
    <text x="0" y="260" font-family="Segoe UI, system-ui, sans-serif" font-size="16" fill="#94a3b8">Android · iOS · macOS · Windows · Linux · Web</text>
  </svg>`,
);

const logo = await sharp(logoPath).resize(112, 112, { fit: "contain", background: { r: 0, g: 0, b: 0, alpha: 0 } }).png().toBuffer();
const showcase = await sharp(showcasePath)
  .resize(700, 565, { fit: "inside", background: { r: 0, g: 0, b: 0, alpha: 0 } })
  .png()
  .toBuffer();

let quality = 88;
let buffer;

for (let attempt = 0; attempt < 6; attempt++) {
  buffer = await sharp(backgroundSvg)
    .composite([
      { input: logo, top: 72, left: 56 },
      { input: textSvg, top: 200, left: 56 },
      { input: showcase, top: 32, left: 470 },
    ])
    .png({ compressionLevel: 9, quality, palette: quality < 80 })
    .toBuffer();

  if (buffer.length <= 300_000 || quality <= 60) {
    break;
  }
  quality -= 8;
}

fs.writeFileSync(outPath, buffer);

const meta = await sharp(buffer).metadata();
console.log(
  `[build-og-image] Wrote ${outPath} — ${meta.width}x${meta.height}, ${buffer.length} bytes (quality=${quality})`,
);

if (buffer.length > 300_000) {
  console.warn("[build-og-image] Warning: file exceeds 300 KB WhatsApp recommendation.");
}
