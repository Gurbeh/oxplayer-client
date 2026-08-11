#!/usr/bin/env node
/**
 * One-shot: seed releases/latest/* on R2 from local files.
 * Loads credentials from oxplayer-be/.env (never prints secrets).
 *
 * Usage:
 *   node scripts/seed-r2-releases.mjs <dir> [version]
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { S3Client, PutObjectCommand } from "@aws-sdk/client-s3";

const clientRoot = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const beEnv = path.join(clientRoot, "..", "oxplayer-be", ".env");

function loadEnv(filePath) {
  const out = {};
  if (!fs.existsSync(filePath)) return out;
  for (const line of fs.readFileSync(filePath, "utf8").split(/\r?\n/)) {
    const t = line.trim();
    if (!t || t.startsWith("#")) continue;
    const eq = t.indexOf("=");
    if (eq <= 0) continue;
    out[t.slice(0, eq).trim()] = t.slice(eq + 1).trim().replace(/^["']|["']$/g, "");
  }
  return out;
}

const env = { ...loadEnv(beEnv), ...process.env };
const endpoint = env.CLOUDFLARE_S3_API_ENDPOINT;
const bucket = env.CLOUDFLARE_R2_BUCKET || "oxplayer-channel-news";
const accessKeyId = env.CLOUDFLARE_S3_ACCESS_KEY_ID;
const secretAccessKey = env.CLOUDFLARE_S3_SECRET_ACCESS_KEY;

if (!endpoint || !accessKeyId || !secretAccessKey) {
  console.error("missing R2 S3 credentials in oxplayer-be/.env");
  process.exit(1);
}

const dir = process.argv[2];
const version = process.argv[3] || "1.1.122";
if (!dir || !fs.existsSync(dir)) {
  console.error("usage: node scripts/seed-r2-releases.mjs <dir> [version]");
  process.exit(1);
}

const map = [
  [`OXPlayer-Android-${version}-arm64-v8a.apk`, "releases/latest/OXPlayer-Android-arm64-v8a.apk", "application/vnd.android.package-archive"],
  [`OXPlayer-Android-${version}-armeabi-v7a.apk`, "releases/latest/OXPlayer-Android-armeabi-v7a.apk", "application/vnd.android.package-archive"],
  [`OXPlayer-Windows-${version}-Setup.exe`, "releases/latest/OXPlayer-Windows-Setup.exe", "application/vnd.microsoft.portable-executable"],
];

const s3 = new S3Client({
  region: "auto",
  endpoint,
  credentials: { accessKeyId, secretAccessKey },
  forcePathStyle: true,
});

for (const [name, key, contentType] of map) {
  const src = path.join(dir, name);
  if (!fs.existsSync(src)) {
    console.warn(`skip missing ${name}`);
    continue;
  }
  const body = fs.readFileSync(src);
  const fname = path.basename(key);
  console.log(`put ${key} (${body.length} bytes)`);
  await s3.send(
    new PutObjectCommand({
      Bucket: bucket,
      Key: key,
      Body: body,
      ContentType: contentType,
      ContentDisposition: `attachment; filename="${fname}"`,
      CacheControl: "public, max-age=300, must-revalidate",
    }),
  );
  const versioned = `releases/v${version}/${name}`;
  console.log(`put ${versioned}`);
  await s3.send(
    new PutObjectCommand({
      Bucket: bucket,
      Key: versioned,
      Body: body,
      ContentType: contentType,
      ContentDisposition: `attachment; filename="${name}"`,
      CacheControl: "public, max-age=300, must-revalidate",
    }),
  );
}

console.log("done");
