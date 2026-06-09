import { SITE_ORIGIN } from "@/config/site";

export const GITHUB_REPO = "Gurbeh/oxplayer-client";

export const RELEASES_PAGE_URL = `https://github.com/${GITHUB_REPO}/releases/latest`;

/** Live web app (deployed from release builds). */
export const WEB_APP_URL = `${SITE_ORIGIN}/web/`;

export type PlatformId = "Android" | "AndroidTV" | "iOS" | "macOS" | "Windows" | "Linux" | "Web";

/** Match primary release asset per platform from GitHub Releases. */
export const PLATFORM_ASSET_PATTERNS: Record<Exclude<PlatformId, "Web">, RegExp> = {
  Android: /^OXPlayer-Android-.+-arm64-v8a\.apk$/,
  AndroidTV: /^OXPlayer-Android-.+-armeabi-v7a\.apk$/,
  iOS: /^OXPlayer-iOS-.+\.ipa$/,
  macOS: /^OXPlayer-macOS-.+\.dmg$/,
  Windows: /^OXPlayer-Windows-.+-Setup\.exe$/,
  Linux: /^OXPlayer-Linux-.+\.AppImage$/,
};

export function resolvePlatformUrl(platformId: PlatformId, assets: { name: string; browser_download_url: string }[]): string {
  if (platformId === "Web") {
    return WEB_APP_URL;
  }

  const pattern = PLATFORM_ASSET_PATTERNS[platformId];
  const asset = assets.find((a) => pattern.test(a.name));
  return asset?.browser_download_url ?? RELEASES_PAGE_URL;
}
