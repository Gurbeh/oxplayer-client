#!/usr/bin/env node
/**
 * Automated Telegram Windows playback smoke (logic layer).
 *
 * Covers what CI can prove without a live Telegram+MPV UI session:
 *   - HTTP bridge seek matrix (start → 70% → +30s → back)
 *   - concurrent Range (seek-stall class)
 *   - stop URI mismatch (episode prev/next killing new session)
 *   - rebuild oxtelegram.dll so Debug runner picks up fixes
 *
 * Still needs ONE short manual/UI pass for: pause/play, subtitle off/on,
 * episode next/prev with real account (Telegram network + MPV).
 *
 * Usage (from oxplayer-be or oxplayer-client):
 *   node ../oxplayer-client/scripts/telegram-windows-smoke.mjs
 *   pnpm run test:telegram-windows-smoke   # from oxplayer-be
 */
import { spawnSync } from "node:child_process";
import { existsSync, copyFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const clientRoot = path.resolve(here, "..");
const oxDir = path.join(clientRoot, "go", "oxtelegram");
const dllSrc = path.join(clientRoot, "windows", "oxtelegram", "oxtelegram.dll");
const dllDst = path.join(clientRoot, "build", "windows", "x64", "runner", "Debug", "oxtelegram.dll");
const buildPs1 = path.join(clientRoot, "windows", "oxtelegram", "build.ps1");

function run(cmd, args, opts = {}) {
  console.log(`\n> ${cmd} ${args.join(" ")}`);
  const r = spawnSync(cmd, args, {
    cwd: opts.cwd ?? clientRoot,
    stdio: "inherit",
    shell: process.platform === "win32",
    env: { ...process.env, CGO_ENABLED: "1", ...(opts.env || {}) },
  });
  if ((r.status ?? 1) !== 0) {
    console.error(`[smoke] FAILED: ${cmd} exit=${r.status}`);
    process.exit(r.status ?? 1);
  }
}

console.log("[smoke] Telegram Windows playback — automated layer");
console.log(`[smoke] clientRoot=${clientRoot}`);

run("go", ["test", "./...", "-count=1", "-timeout", "120s"], { cwd: oxDir });

if (process.platform === "win32" && existsSync(buildPs1)) {
  run("powershell", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", buildPs1]);
  if (existsSync(dllSrc) && existsSync(path.dirname(dllDst))) {
    try {
      copyFileSync(dllSrc, dllDst);
      console.log(`[smoke] Installed DLL → ${dllDst}`);
    } catch (e) {
      console.warn(
        `[smoke] DLL copy skipped (app running / file locked). Quit fladder then re-run smoke, or pnpm run dev:windows.\n  ${e}`,
      );
    }
  } else {
    console.log("[smoke] Debug runner folder missing — skip DLL copy (run flutter once first)");
  }
} else {
  console.log("[smoke] skip DLL rebuild (non-Windows or missing build.ps1)");
}

console.log(`
[smoke] AUTOMATED OK — logic layer green.

Manual UI checklist (one pass, ~10 min) — cannot fully automate Telegram+MPV:
  [ ] play / pause / play
  [ ] seek +30s / -30s several times near start AND near 70%
  [ ] subtitle off → on (expect subtitle_track_external success, not 502 forever)
  [ ] episode next then previous (no eternal loading)
  [ ] leave playing 3+ min after a deep seek (no jump-to-0 then freeze)

Log signals:
  OXPLAY_TDLIB: startPlaybackSession ok -> .../N   (subtitle reuse = same N)
  OX_STREAM phase=subtitle_track_external ... via=data
  NOT: subtitle_track_external_fail status=502 (retry should clear flakes)

Re-run app after this smoke:
  pnpm run dev:windows
`);
