"use client";

import { useEffect, useState } from "react";
import { GITHUB_REPO, type PlatformId, resolvePlatformUrl } from "@/config/downloads";
import { platforms } from "@/config/platforms";

type ReleaseAsset = { name: string; browser_download_url: string };

export function useReleaseDownloads() {
  const [urls, setUrls] = useState<Partial<Record<PlatformId, string>>>({});

  useEffect(() => {
    let cancelled = false;

    fetch(`https://api.github.com/repos/${GITHUB_REPO}/releases/latest`)
      .then((res) => (res.ok ? res.json() : Promise.reject(res)))
      .then((release: { assets?: ReleaseAsset[] }) => {
        if (cancelled) return;
        const assets = release.assets ?? [];
        const next: Partial<Record<PlatformId, string>> = {};
        for (const platform of platforms) {
          next[platform.id] = resolvePlatformUrl(platform.id, assets);
        }
        setUrls(next);
      })
      .catch(() => {
        if (cancelled) return;
        const fallback: Partial<Record<PlatformId, string>> = {};
        for (const platform of platforms) {
          fallback[platform.id] = resolvePlatformUrl(platform.id, []);
        }
        setUrls(fallback);
      });

    return () => {
      cancelled = true;
    };
  }, []);

  return urls;
}
