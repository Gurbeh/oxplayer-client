#!/usr/bin/env node
/**
 * OXPlayer playback E2E runner — drives integration_test/oxplayer_playback_e2e_test.dart
 * against a real, already-logged-in dev build on Windows or Android. This is the "always easy
 * to re-run" tool the suite exists for.
 *
 * Requires dart_defines.dev.json (see windows/oxtelegram/README.md) and a device that is already
 * authenticated (Telegram session + server account) — this exercises the real playback pipeline
 * end to end, nothing is stubbed.
 *
 * Usage:
 *   node scripts/e2e-playback.mjs --platform windows
 *   node scripts/e2e-playback.mjs --platform android [--device emulator-5554]
 *   node scripts/e2e-playback.mjs --platform windows --show1 "From" --show2 "Manifest"
 *
 * From oxplayer-be: pnpm run test:e2e:windows / pnpm run test:e2e:android
 */
import { existsSync } from "node:fs";
import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const clientRoot = path.dirname(path.dirname(fileURLToPath(import.meta.url)));

const TEMURIN_JDK = "C:\\Program Files\\Eclipse Adoptium\\jdk-21.0.12.8-hotspot";
const WIN_SYSTEM32 = "C:\\Windows\\System32";
const WIN_ROOT = "C:\\Windows";
const WIN_POWERSHELL = "C:\\Windows\\System32\\WindowsPowerShell\\v1.0";
const PWSH7 = "C:\\Program Files\\PowerShell\\7";
const GIT_CMD = "C:\\Program Files\\Git\\cmd";
const GIT_BIN = "C:\\Program Files\\Git\\bin";

function parseArgs(argv) {
  const args = { platform: null, device: null, show1: null, show2: null };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--platform") args.platform = argv[++i];
    else if (a === "--device" || a === "-d") args.device = argv[++i];
    else if (a === "--show1") args.show1 = argv[++i];
    else if (a === "--show2") args.show2 = argv[++i];
  }
  return args;
}

function run(cmd, cmdArgs, opts = {}) {
  console.log(`\n> ${cmd} ${cmdArgs.join(" ")}`);
  return spawnSync(cmd, cmdArgs, {
    cwd: clientRoot,
    stdio: "inherit",
    shell: process.platform === "win32",
    ...opts,
  });
}

function pathHasDir(pathValue, dir) {
  const needle = path.normalize(dir).toLowerCase();
  return String(pathValue || "")
    .split(path.delimiter)
    .some((p) => path.normalize(p).toLowerCase() === needle);
}

function ensureBaseWindowsPath(env) {
  const must = [WIN_SYSTEM32, WIN_ROOT, WIN_POWERSHELL, PWSH7, GIT_CMD, GIT_BIN].filter((d) => existsSync(d));
  const missing = must.filter((d) => !pathHasDir(env.PATH, d));
  if (missing.length) {
    env.PATH = `${missing.join(path.delimiter)}${path.delimiter}${env.PATH || ""}`;
  }
}

function resolveFlutterBat(env) {
  const fromEnv = (env.FLUTTER_ROOT || process.env.FLUTTER_ROOT || "").trim();
  if (fromEnv) {
    const bat = path.join(fromEnv, "bin", "flutter.bat");
    if (existsSync(bat)) return bat;
  }
  const candidates = [
    path.join(clientRoot, ".fvm", "flutter_sdk", "bin", "flutter.bat"),
    "C:\\flutter\\bin\\flutter.bat",
    path.join(process.env.LOCALAPPDATA || "", "fvm", "default", "bin", "flutter.bat"),
  ];
  for (const c of candidates) {
    if (c && existsSync(c)) return c;
  }
  const whereExe = path.join(WIN_SYSTEM32, "where.exe");
  const which = spawnSync(existsSync(whereExe) ? whereExe : "where.exe", ["flutter"], {
    encoding: "utf8",
    shell: true,
    env,
  });
  if (which.status === 0 && which.stdout) {
    const line = which.stdout
      .split(/\r?\n/)
      .map((s) => s.trim())
      .find((s) => s.toLowerCase().endsWith("flutter.bat") || s.toLowerCase().endsWith("flutter"));
    if (line && existsSync(line)) return line;
  }
  return "flutter.bat";
}

function ensureWindowsToolchainEnv(env) {
  ensureBaseWindowsPath(env);
  const jdk = (env.JAVA_HOME || "").trim() || TEMURIN_JDK;
  if (existsSync(path.join(jdk, "include", "jni.h"))) {
    env.JAVA_HOME = jdk;
  }
  if (!(env.CMAKE_GENERATOR || "").trim()) {
    env.CMAKE_GENERATOR = "Visual Studio 17 2022";
  }
  const flutterBat = resolveFlutterBat(env);
  const flutterBin = path.dirname(flutterBat);
  const jdkBin = env.JAVA_HOME ? path.join(env.JAVA_HOME, "bin") : "";
  env.PATH = `${jdkBin}${path.delimiter}${flutterBin}${path.delimiter}${env.PATH || ""}`;
  env.FLUTTER_ROOT = path.dirname(flutterBin);
  return flutterBat;
}

const args = parseArgs(process.argv.slice(2));
if (!args.platform || !["windows", "android"].includes(args.platform)) {
  console.error(
    "Usage: node scripts/e2e-playback.mjs --platform windows|android [--device <id>] [--show1 Title] [--show2 Title]",
  );
  process.exit(1);
}

const defines = path.join(clientRoot, "dart_defines.dev.json");
if (!existsSync(defines)) {
  console.error(
    `[e2e] Missing ${defines} — sync env first: from oxplayer-be, pnpm run env:sync && node ./scripts/sync-client-env.mjs --force`,
  );
  process.exit(1);
}

const env = { ...process.env };
let flutterBin = "flutter";
let deviceId = args.device;

if (args.platform === "windows") {
  if (process.platform !== "win32") {
    console.error("[e2e] --platform windows only runs on a Windows host.");
    process.exit(1);
  }
  flutterBin = ensureWindowsToolchainEnv(env);

  // Rebuild oxtelegram.dll from current Go sources — otherwise this suite silently tests a
  // stale prebuilt binary instead of today's fixes.
  const buildPs1 = path.join(clientRoot, "windows", "oxtelegram", "build.ps1");
  if (existsSync(buildPs1)) {
    const rc = run("powershell", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", buildPs1], { env });
    if ((rc.status ?? 1) !== 0) {
      console.error("[e2e] oxtelegram.dll rebuild failed.");
      process.exit(rc.status ?? 1);
    }
  }

  // Stale fladder.exe locks runner DLLs.
  run("taskkill", ["/F", "/IM", "fladder.exe"], { env });

  deviceId ??= "windows";
} else {
  deviceId ??= null;
  if (!deviceId) {
    console.log(
      "[e2e] No --device given — flutter will target the sole connected Android device/emulator (pass --device if you have more than one).",
    );
  }
}

// `flutter drive` (not `flutter test`) — launches the app the same way `flutter run` does.
// media_kit's native Windows video pipeline (mpv.Player.open()) has been observed to hang
// indefinitely under `flutter test integration_test/...` specifically; `flutter drive` does not
// hit this because it attaches to a normally-launched app instead of the device-test runner.
const testArgs = [
  "drive",
  "--driver=test_driver/integration_test.dart",
  "--target=integration_test/oxplayer_playback_e2e_test.dart",
  "--dart-define-from-file=dart_defines.dev.json",
];
if (args.show1) testArgs.push(`--dart-define=E2E_SHOW_1=${args.show1}`);
if (args.show2) testArgs.push(`--dart-define=E2E_SHOW_2=${args.show2}`);
if (deviceId) testArgs.push("-d", deviceId);

const result = run(flutterBin, testArgs, { env });
process.exit(result.status ?? 1);
