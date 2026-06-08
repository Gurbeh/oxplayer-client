"use client";

import { createContext, useContext, type ReactNode } from "react";
import type { PlatformId } from "@/config/downloads";
import { useReleaseDownloads } from "@/hooks/useReleaseDownloads";

const ReleaseDownloadsContext = createContext<Partial<Record<PlatformId, string>>>({});

export function ReleaseDownloadsProvider({ children }: { children: ReactNode }) {
  const urls = useReleaseDownloads();
  return <ReleaseDownloadsContext.Provider value={urls}>{children}</ReleaseDownloadsContext.Provider>;
}

export function useReleaseDownloadUrls() {
  return useContext(ReleaseDownloadsContext);
}
