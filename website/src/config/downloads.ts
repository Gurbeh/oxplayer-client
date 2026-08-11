import { WEB_APP_ORIGIN, WEB_APP_ORIGIN_IRAN } from "@/config/site";

export const GITHUB_REPO = "Gurbeh/oxplayer-client";

export const RELEASES_PAGE_URL = `https://github.com/${GITHUB_REPO}/releases/latest`;

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

/** Match primary release asset per platform from GitHub Releases. */
export const PLATFORM_ASSET_PATTERNS: Record<
  Exclude<PlatformId, "Web" | "Android">,
  RegExp
> = {
  /** Modern phones (64-bit ARM). */
  AndroidPhone: /^OXPlayer-Android-.+-arm64-v8a\.apk$/,
  /** Android TV + older 32-bit phones. */
  AndroidTV: /^OXPlayer-Android-.+-armeabi-v7a\.apk$/,
  iOS: /^OXPlayer-iOS-.+\.ipa$/,
  macOS: /^OXPlayer-macOS-.+\.dmg$/,
  Windows: /^OXPlayer-Windows-.+-Setup\.exe$/,
  Linux: /^OXPlayer-Linux-.+\.AppImage$/,
};

export function resolvePlatformUrl(
  platformId: PlatformId,
  assets: { name: string; browser_download_url: string }[],
): string {
  if (platformId === "Web") {
    return WEB_APP_URL;
  }

  if (platformId === "Android") {
    return PLAY_STORE_ANDROID_URL;
  }

  const pattern = PLATFORM_ASSET_PATTERNS[platformId];
  const asset = assets.find((a) => pattern.test(a.name));
  return asset?.browser_download_url ?? RELEASES_PAGE_URL;
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
