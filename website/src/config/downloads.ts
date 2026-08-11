import { WEB_APP_ORIGIN, WEB_APP_ORIGIN_IRAN } from "@/config/site";

export const GITHUB_REPO = "Gurbeh/oxplayer-client";

export const RELEASES_PAGE_URL = `https://github.com/${GITHUB_REPO}/releases/latest`;

/**
 * Public R2 origin for stable "latest" release binaries.
 * Same bucket as channel-news; objects live under `releases/` (no TTL on that prefix).
 */
export const RELEASES_CDN_ORIGIN =
  "https://pub-620251e8a4724a0b8a0b01903c727616.r2.dev";

/** Google Play listing for the Android phone app. */
export const PLAY_STORE_ANDROID_URL =
  "https://play.google.com/store/apps/details?id=app.oxplayer";

/** Live Flutter web app — global cohort. */
export const WEB_APP_URL = `${WEB_APP_ORIGIN}/`;

/** Live Flutter web app — Iran CDN.ir cohort. */
export const WEB_APP_URL_IRAN = `${WEB_APP_ORIGIN_IRAN}/`;

export type PlatformId =
  | "Android"
  | "AndroidPhone"
  | "AndroidTV"
  | "iOS"
  | "macOS"
  | "Windows"
  | "Linux"
  | "Web";

/**
 * Stable R2 object keys under `releases/latest/` (overwritten each stable release).
 * Filenames intentionally omit version so short links stay forever.
 */
export const PLATFORM_LATEST_KEYS: Record<
  Exclude<PlatformId, "Web" | "Android">,
  string
> = {
  AndroidPhone: "releases/latest/OXPlayer-Android-arm64-v8a.apk",
  AndroidTV: "releases/latest/OXPlayer-Android-armeabi-v7a.apk",
  iOS: "releases/latest/OXPlayer-iOS.ipa",
  macOS: "releases/latest/OXPlayer-macOS.dmg",
  Windows: "releases/latest/OXPlayer-Windows-Setup.exe",
  Linux: "releases/latest/OXPlayer-Linux.AppImage",
};

/** Match versioned GitHub/CI asset names → stable latest key (for mirror upload). */
export const PLATFORM_ASSET_PATTERNS: Record<
  Exclude<PlatformId, "Web" | "Android">,
  RegExp
> = {
  AndroidPhone: /^OXPlayer-Android-.+-arm64-v8a\.apk$/,
  AndroidTV: /^OXPlayer-Android-.+-armeabi-v7a\.apk$/,
  iOS: /^OXPlayer-iOS-.+\.ipa$/,
  macOS: /^OXPlayer-macOS-.+\.dmg$/,
  Windows: /^OXPlayer-Windows-.+-Setup\.exe$/,
  Linux: /^OXPlayer-Linux-.+\.AppImage$/,
};

/** Resolve download URL for a platform — R2 latest for binaries, store/web otherwise. */
export function resolvePlatformUrl(platformId: PlatformId): string {
  if (platformId === "Web") {
    return WEB_APP_URL;
  }

  if (platformId === "Android") {
    return PLAY_STORE_ANDROID_URL;
  }

  return `${RELEASES_CDN_ORIGIN}/${PLATFORM_LATEST_KEYS[platformId]}`;
}

/** Short-link slug served at oxplayer.app/dl/{slug} — kept in sync with oxplayer-be main-bot. */
export const PLATFORM_DL_SLUGS: Record<Exclude<PlatformId, "Web">, string> = {
  Android: "google",
  AndroidPhone: "a",
  AndroidTV: "tv",
  iOS: "i",
  macOS: "m",
  Windows: "w",
  Linux: "l",
};

export const DL_SLUG_TO_PLATFORM: Record<string, Exclude<PlatformId, "Web">> =
  Object.fromEntries(
    Object.entries(PLATFORM_DL_SLUGS).map(([platform, slug]) => [
      slug,
      platform,
    ]),
  ) as Record<string, Exclude<PlatformId, "Web">>;

/** Shareable short download link for a platform, relative to the site root. */
export function dlPath(platformId: Exclude<PlatformId, "Web">): string {
  return `/dl/${PLATFORM_DL_SLUGS[platformId]}/`;
}
