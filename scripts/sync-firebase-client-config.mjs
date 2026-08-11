#!/usr/bin/env node
/**
 * Materialize oxplayer-client Firebase client config from Infisical CONSOLE_FIREBASE
 * (Firebase Admin SDK service account JSON).
 *
 * Writes:
 *   android/app/src/production/google-services.json  (app.oxplayer)
 *   android/app/src/direct/google-services.json       (app.oxplayer, same Firebase app as production —
 *                                                       `direct` flavor shares its applicationId)
 *   android/app/src/development/google-services.json (app.oxplayer.dev, if registered)
 *   lib/firebase_options.dart
 *
 * Env (CI after Infisical export, or local):
 *   CONSOLE_FIREBASE — full service account JSON string
 *
 * Local with Infisical identity (Tailscale):
 *   node scripts/sync-firebase-client-config.mjs
 */
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const clientRoot = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const beRoot = path.resolve(clientRoot, "..", "oxplayer-be");

const PRODUCTION_PACKAGE = "app.oxplayer";
const DEVELOPMENT_PACKAGE = "app.oxplayer.dev";
const FIREBASE_SCOPE = "https://www.googleapis.com/auth/firebase";
const SECRET_KEYS = ["CONSOLE_FIREBASE", "FIREBASE_ADMIN_SDK_JSON", "FIREBASE_SERVICE_ACCOUNT_JSON"];

function b64url(input) {
  return Buffer.from(input)
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

function normalizeSecretValue(raw) {
  let val = String(raw || "").trim();
  if (!val) return "";

  for (let i = 0; i < 3; i++) {
    if (
      (val.startsWith('"') && val.endsWith('"')) ||
      (val.startsWith("'") && val.endsWith("'"))
    ) {
      val = val.slice(1, -1).trim();
    }
  }

  // Do not unescape \\n inside JSON blobs — breaks JSON.parse(private_key).
  if (!val.startsWith("{") && !val.startsWith("[")) {
    val = val
      .replace(/\\n/g, "\n")
      .replace(/\\r/g, "\r")
      .replace(/\\t/g, "\t")
      .replace(/\\"/g, '"')
      .replace(/\\'/g, "'")
      .replace(/\\\\/g, "\\");
  }

  return val;
}

function parseServiceAccount(raw) {
  let text = normalizeSecretValue(raw);
  if (!text) return null;
  if (!text.startsWith("{")) {
    try {
      const decoded = Buffer.from(text, "base64").toString("utf8").trim();
      if (decoded.startsWith("{")) text = decoded;
    } catch {
      /* not base64 */
    }
  }
  try {
    const json = JSON.parse(text);
    if (!json.client_email || !json.private_key || !json.project_id) {
      throw new Error("missing client_email/private_key/project_id");
    }
    return json;
  } catch (err) {
    throw new Error(`CONSOLE_FIREBASE is not valid service account JSON: ${err.message || err}`);
  }
}

function signJwt(sa) {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const payload = {
    iss: sa.client_email,
    sub: sa.client_email,
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
    scope: FIREBASE_SCOPE,
  };
  const unsigned = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(payload))}`;
  const sign = crypto.createSign("RSA-SHA256");
  sign.update(unsigned);
  sign.end();
  const signature = sign.sign(sa.private_key);
  return `${unsigned}.${b64url(signature)}`;
}

async function accessToken(sa) {
  const assertion = signJwt(sa);
  const body = new URLSearchParams({
    grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
    assertion,
  });
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body,
  });
  const json = await res.json();
  if (!res.ok || !json.access_token) {
    throw new Error(`Google OAuth failed: ${JSON.stringify(json).slice(0, 300)}`);
  }
  return json.access_token;
}

async function firebaseGet(token, url) {
  const res = await fetch(url, {
    headers: { Authorization: `Bearer ${token}` },
  });
  const text = await res.text();
  let json;
  try {
    json = JSON.parse(text);
  } catch {
    json = { raw: text };
  }
  if (!res.ok) {
    throw new Error(`Firebase API ${res.status} ${url}: ${JSON.stringify(json).slice(0, 400)}`);
  }
  return json;
}

async function firebasePost(token, url, body) {
  const res = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
  const text = await res.text();
  let json;
  try {
    json = JSON.parse(text);
  } catch {
    json = { raw: text };
  }
  if (!res.ok) {
    throw new Error(`Firebase API ${res.status} ${url}: ${JSON.stringify(json).slice(0, 400)}`);
  }
  return json;
}

async function waitForOperation(token, operationName, { timeoutMs = 120_000 } = {}) {
  const started = Date.now();
  while (Date.now() - started < timeoutMs) {
    const op = await firebaseGet(token, `https://firebase.googleapis.com/v1beta1/${operationName}`);
    if (op.done) {
      if (op.error) {
        throw new Error(`Firebase operation failed: ${JSON.stringify(op.error).slice(0, 400)}`);
      }
      return op.response || op;
    }
    await new Promise((r) => setTimeout(r, 2000));
  }
  throw new Error(`Firebase operation timed out: ${operationName}`);
}

async function ensureAndroidApp(token, projectId, packageName, displayName) {
  let apps = await listAndroidApps(token, projectId);
  const existing = apps.find((app) => app.packageName === packageName);
  if (existing?.name) return existing.name;

  console.log(`[firebase-sync] Registering Android app ${packageName} in ${projectId}`);
  const op = await firebasePost(
    token,
    `https://firebase.googleapis.com/v1beta1/projects/${projectId}/androidApps`,
    { packageName, displayName },
  );
  if (op.name?.includes("/operations/")) {
    await waitForOperation(token, op.name);
  }

  for (let attempt = 1; attempt <= 15; attempt++) {
    apps = await listAndroidApps(token, projectId);
    const created = apps.find((app) => app.packageName === packageName);
    if (created?.name) return created.name;
    await new Promise((r) => setTimeout(r, 2000));
  }

  throw new Error(`Android app ${packageName} not visible after registration`);
}

async function listAndroidApps(token, projectId) {
  const apps = [];
  let pageToken = "";
  for (;;) {
    const q = new URLSearchParams();
    if (pageToken) q.set("pageToken", pageToken);
    const url = `https://firebase.googleapis.com/v1beta1/projects/${projectId}/androidApps?${q}`;
    const page = await firebaseGet(token, url);
    apps.push(...(page.apps || []));
    pageToken = page.nextPageToken || "";
    if (!pageToken) break;
  }
  return apps;
}

async function downloadGoogleServices(token, projectId, appName) {
  const url = `https://firebase.googleapis.com/v1beta1/${appName}/config`;
  const cfg = await firebaseGet(token, url);
  if (!cfg.configFileContents) {
    throw new Error(`No configFileContents for ${appName}`);
  }
  const jsonText = Buffer.from(cfg.configFileContents, "base64").toString("utf8");
  return JSON.parse(jsonText);
}

function pickClient(googleServices, packageName) {
  const clients = googleServices.client || [];
  const match = clients.find((c) => c.client_info?.android_client_info?.package_name === packageName);
  if (!match) {
    throw new Error(`Package ${packageName} not found in google-services.json clients`);
  }
  return match;
}

function firebaseOptionsFromGoogleServices(googleServices, packageName, constName) {
  const client = pickClient(googleServices, packageName);
  const project = googleServices.project_info || {};
  const apiKey = client.api_key?.[0]?.current_key || "";
  const appId = client.client_info?.mobilesdk_app_id || "";
  const messagingSenderId = String(project.project_number || "");
  const projectId = project.project_id || "";
  const storageBucket = project.storage_bucket || "";
  if (!apiKey || !appId || !messagingSenderId || !projectId) {
    throw new Error(`Incomplete Firebase client config for ${packageName}`);
  }
  return {
    constName,
    apiKey,
    appId,
    messagingSenderId,
    projectId,
    storageBucket,
  };
}

function dartString(value) {
  return `'${String(value).replace(/\\/g, "\\\\").replace(/'/g, "\\'")}'`;
}

function writeFirebaseOptionsDart(optionsList) {
  const blocks = optionsList
    .map(
      (o) => `  static const FirebaseOptions ${o.constName} = FirebaseOptions(
    apiKey: ${dartString(o.apiKey)},
    appId: ${dartString(o.appId)},
    messagingSenderId: ${dartString(o.messagingSenderId)},
    projectId: ${dartString(o.projectId)},
    storageBucket: ${dartString(o.storageBucket)},
  );`,
    )
    .join("\n\n");

  const hasDev = optionsList.some((o) => o.constName === "androidDev");

  const content = `// Generated by scripts/sync-firebase-client-config.mjs — do not edit manually.
// Source: Infisical CONSOLE_FIREBASE (Firebase Admin SDK) + Firebase Management API.
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:package_info_plus/package_info_plus.dart';

/// Default [FirebaseOptions] for use with your Firebase apps.
class DefaultFirebaseOptions {
  static FirebaseOptions? _resolvedAndroid;

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        final cached = _resolvedAndroid;
        if (cached != null) return cached;
        throw UnsupportedError(
          'Android FirebaseOptions not resolved yet — call DefaultFirebaseOptions.ensureAndroidResolved() before Firebase.initializeApp.',
        );
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not configured for $defaultTargetPlatform.',
        );
    }
  }

  /// Picks [android] vs [androidDev] from installed package name (Play flavors).
  static Future<FirebaseOptions> ensureAndroidResolved() async {
    if (_resolvedAndroid != null) return _resolvedAndroid!;
    final packageName = (await PackageInfo.fromPlatform()).packageName;
    _resolvedAndroid = packageName == ${dartString(DEVELOPMENT_PACKAGE)}${hasDev ? " ? androidDev : android" : " ? android : android"};
    return _resolvedAndroid!;
  }

${blocks}
}
`;
  const outPath = path.join(clientRoot, "lib", "firebase_options.dart");
  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  fs.writeFileSync(outPath, content, "utf8");
  return outPath;
}

function writeGoogleServices(subpath, json) {
  const outPath = path.join(clientRoot, "android", "app", subpath, "google-services.json");
  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  fs.writeFileSync(outPath, `${JSON.stringify(json, null, 2)}\n`, "utf8");
  return outPath;
}

function infisicalBin() {
  return process.platform === "win32" ? "infisical.cmd" : "infisical";
}

function loadIdentity() {
  const candidates = [
    process.env.INFISICAL_IDENTITY_FILE,
    path.join(beRoot, "deploy", "infisical", "dev.import-identity"),
    path.join(beRoot, "deploy", "infisical", "client-ci.import-identity"),
  ].filter(Boolean);
  for (const file of candidates) {
    if (!fs.existsSync(file)) continue;
    const env = {};
    for (const line of fs.readFileSync(file, "utf8").split(/\r?\n/)) {
      const m = line.match(/^([^=]+)=(.*)$/);
      if (m) env[m[1]] = m[2];
    }
    return env;
  }
  return null;
}


function fetchSecretFromJsonExport(bin, identity, token, secretPath) {
  const tmp = path.join(os.tmpdir(), "ox-console-firebase.json");
  execFileSync(
    bin,
    [
      "export",
      `--domain=${identity.INFISICAL_API_URL}`,
      `--token=${token}`,
      `--projectId=${identity.INFISICAL_PROJECT_ID}`,
      "--env=core-api",
      `--path=${secretPath}`,
      "--format=json",
      `--output-file=${tmp}`,
      "--silent",
    ],
    { stdio: "pipe", shell: process.platform === "win32" },
  );
  const payload = JSON.parse(fs.readFileSync(tmp, "utf8"));
  const rows = Array.isArray(payload) ? payload : payload.secrets || [];
  for (const row of rows) {
    const key = row.key || row.secretKey || row.Key;
    if (!SECRET_KEYS.includes(key)) continue;
    const val = row.value ?? row.secretValue ?? row.Value;
    if (val == null) continue;
    if (typeof val === "object") return JSON.stringify(val);
    if (String(val).trim()) return String(val);
  }
  return null;
}

function fetchConsoleFirebaseFromInfisical() {
  const identity = loadIdentity();
  if (!identity?.INFISICAL_API_URL || !identity?.INFISICAL_MACHINE_CLIENT_ID) return null;
  const bin = infisicalBin();
  const token = execFileSync(
    bin,
    [
      "login",
      `--domain=${identity.INFISICAL_API_URL}`,
      "--method=universal-auth",
      `--client-id=${identity.INFISICAL_MACHINE_CLIENT_ID}`,
      `--client-secret=${identity.INFISICAL_MACHINE_CLIENT_SECRET}`,
      "--silent",
      "--plain",
    ],
    { encoding: "utf8", shell: process.platform === "win32" },
  ).trim();

  const paths = [
    "/core/client-ci",
    "/core/observability",
    "/core/integrations",
    "/core/console",
    "/core",
  ];
  for (const secretPath of paths) {
    try {
      const jsonVal = fetchSecretFromJsonExport(bin, identity, token, secretPath);
      if (jsonVal?.trim()) return jsonVal;
    } catch {
      /* try next path */
    }
  }
  return null;
}

function resolveConsoleFirebaseRaw() {
  for (const key of SECRET_KEYS) {
    const val = process.env[key];
    if (!val?.trim()) continue;
    try {
      parseServiceAccount(val);
      return normalizeSecretValue(val);
    } catch {
      console.warn(`[firebase-sync] ignore invalid ${key} from environment — fetching Infisical`);
    }
  }
  return fetchConsoleFirebaseFromInfisical();
}

async function main() {
  const raw = resolveConsoleFirebaseRaw();
  if (!raw) {
    console.log("[firebase-sync] CONSOLE_FIREBASE not set — skip (Infisical /core/client-ci or env)");
    return;
  }

  const sa = parseServiceAccount(raw);
  const token = await accessToken(sa);

  const productionApp = await ensureAndroidApp(
    token,
    sa.project_id,
    PRODUCTION_PACKAGE,
    "OXPlayer",
  );
  let developmentApp = null;
  try {
    developmentApp = await ensureAndroidApp(
      token,
      sa.project_id,
      DEVELOPMENT_PACKAGE,
      "OXPlayer Dev",
    );
  } catch (err) {
    console.warn(`[firebase-sync] warn: could not register ${DEVELOPMENT_PACKAGE}: ${err.message || err}`);
  }

  const byPackage = new Map([
    [PRODUCTION_PACKAGE, productionApp],
    ...(developmentApp ? [[DEVELOPMENT_PACKAGE, developmentApp]] : []),
  ]);

  const outputs = [];
  const dartOptions = [];

  if (byPackage.has(PRODUCTION_PACKAGE)) {
    const gs = await downloadGoogleServices(token, sa.project_id, byPackage.get(PRODUCTION_PACKAGE));
    outputs.push(writeGoogleServices(path.join("src", "production"), gs));
    // `direct` flavor (GitHub/website APK) shares production's applicationId — same Firebase app.
    outputs.push(writeGoogleServices(path.join("src", "direct"), gs));
    dartOptions.push(firebaseOptionsFromGoogleServices(gs, PRODUCTION_PACKAGE, "android"));
  }

  if (byPackage.has(DEVELOPMENT_PACKAGE)) {
    const gs = await downloadGoogleServices(token, sa.project_id, byPackage.get(DEVELOPMENT_PACKAGE));
    outputs.push(writeGoogleServices(path.join("src", "development"), gs));
    dartOptions.push(firebaseOptionsFromGoogleServices(gs, DEVELOPMENT_PACKAGE, "androidDev"));
  }

  if (!dartOptions.length) {
    throw new Error("No Android Firebase apps configured");
  }

  outputs.push(writeFirebaseOptionsDart(dartOptions));
  for (const p of outputs) {
    console.log(`[firebase-sync] Wrote ${path.relative(clientRoot, p)}`);
  }
}

main().catch((err) => {
  console.error(`[firebase-sync] ${err.message || err}`);
  process.exit(1);
});
