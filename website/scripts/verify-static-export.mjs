#!/usr/bin/env node
/**
 * Guard: static export must ship complete CSS and resolvable asset links.
 * Fails CI if Tailwind utilities are missing or HTML references missing files.
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const websiteRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const outDir = path.join(websiteRoot, "out");
const indexPath = path.join(outDir, "index.html");

const REQUIRED_CSS_MARKERS = [
  ".flex{",
  ".bg-base-100",
  "--color-primary",
  ".justify-center",
  ".min-h-screen",
];

const REQUIRED_META_MARKERS = [
  'property="og:title"',
  'property="og:description"',
  'property="og:image"',
  'property="og:url"',
  'name="twitter:card"',
];

const REQUIRED_STATIC_ASSETS = ["images/og-image.png"];

function fail(message) {
  console.error(`\n[verify-static-export] ${message}\n`);
  process.exit(1);
}

if (!fs.existsSync(indexPath)) {
  fail(`Missing ${indexPath}. Run "npm run build" in website/ first.`);
}

const html = fs.readFileSync(indexPath, "utf8");

if (/turbopack-[a-f0-9]+\.js/i.test(html)) {
  fail(
    "Production HTML references a turbopack runtime chunk. Use \"next build --webpack\" so CSS is emitted correctly.",
  );
}

const stylesheetHrefs = [
  ...html.matchAll(/<link[^>]+rel=["']stylesheet["'][^>]+href=["']([^"']+)["']/gi),
  ...html.matchAll(/<link[^>]+href=["']([^"']+)["'][^>]+rel=["']stylesheet["']/gi),
].map((match) => match[1].replace(/^\//, ""));

if (stylesheetHrefs.length === 0) {
  fail("No stylesheet <link> tags found in index.html.");
}

const missingMeta = REQUIRED_META_MARKERS.filter((marker) => !html.includes(marker));
if (missingMeta.length > 0) {
  fail(`index.html missing social/SEO meta tags: ${missingMeta.join(", ")}`);
}

for (const asset of REQUIRED_STATIC_ASSETS) {
  const assetPath = path.join(outDir, asset);
  if (!fs.existsSync(assetPath)) {
    fail(`Missing static asset in export: ${asset}`);
  }
}

for (const href of stylesheetHrefs) {
  const filePath = path.join(outDir, href);
  if (!fs.existsSync(filePath)) {
    fail(`Stylesheet missing on disk: ${href}`);
  }
}

function collectCssFiles(dir) {
  if (!fs.existsSync(dir)) {
    return [];
  }
  return fs
    .readdirSync(dir)
    .filter((name) => name.endsWith(".css"))
    .map((name) => path.join(dir, name));
}

const cssDirs = [
  path.join(outDir, "_next", "static", "css"),
  path.join(outDir, "_next", "static", "chunks"),
];

const cssFilePaths = cssDirs.flatMap(collectCssFiles);
if (cssFilePaths.length === 0) {
  fail("No CSS files under out/_next/static/css/ or out/_next/static/chunks/.");
}

let combinedCss = "";
let totalBytes = 0;
for (const filePath of cssFilePaths) {
  const content = fs.readFileSync(filePath, "utf8");
  combinedCss += content;
  totalBytes += Buffer.byteLength(content, "utf8");
}

const MIN_TOTAL_CSS_BYTES = 60_000;
if (totalBytes < MIN_TOTAL_CSS_BYTES) {
  fail(
    `CSS bundle too small (${totalBytes} bytes < ${MIN_TOTAL_CSS_BYTES}). Tailwind utilities likely missing.`,
  );
}

const missingMarkers = REQUIRED_CSS_MARKERS.filter((marker) => !combinedCss.includes(marker));
if (missingMarkers.length > 0) {
  fail(`CSS missing required Tailwind markers: ${missingMarkers.join(", ")}`);
}

console.log(
  `[verify-static-export] OK — ${stylesheetHrefs.length} stylesheet(s), ${cssFilePaths.length} CSS file(s), ${totalBytes} bytes.`,
);
