"use client";

import { type PlatformId, resolvePlatformUrl } from "@/config/downloads";
import { platforms } from "@/config/platforms";

/** Sync map of platform → download URL (R2 latest / Play / web). */
export function useReleaseDownloads(): Partial<Record<PlatformId, string>> {
  const urls: Partial<Record<PlatformId, string>> = {};
  for (const platform of platforms) {
    urls[platform.id] = resolvePlatformUrl(platform.id);
  }
  return urls;
}
