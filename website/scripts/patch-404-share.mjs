#!/usr/bin/env node
/**
 * GitHub Pages serves 404.html for unknown paths. Redirect /share/{uuid}/ to the
 * static share landing page that reads ?id= from the query string.
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const websiteRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const out404 = path.join(websiteRoot, "out", "404.html");

const SHARE_REDIRECT_SCRIPT = `<script>(function(){var p=location.pathname;var m=p.match(/^\\/share\\/([^/]+)\\/?$/);if(m){location.replace("/share/item/?id="+encodeURIComponent(m[1]));}})();</script>`;

if (!fs.existsSync(out404)) {
  console.warn("[patch-404-share] No out/404.html — skip");
  process.exit(0);
}

let html = fs.readFileSync(out404, "utf8");
if (html.includes("/share/item/")) {
  console.log("[patch-404-share] Already patched");
  process.exit(0);
}

if (html.includes("<head>")) {
  html = html.replace("<head>", `<head>${SHARE_REDIRECT_SCRIPT}`);
} else {
  html = SHARE_REDIRECT_SCRIPT + html;
}

fs.writeFileSync(out404, html);
console.log("[patch-404-share] Patched out/404.html for /share/{id} routes");
