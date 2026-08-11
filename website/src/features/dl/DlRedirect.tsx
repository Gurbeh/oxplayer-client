"use client";

import Container from "@/components/ui/Container";
import Heading from "@/components/ui/Heading";
import Paragraph from "@/components/ui/Paragraph";
import type { PlatformId } from "@/config/downloads";
import { platforms } from "@/config/platforms";
import { useReleaseDownloads } from "@/hooks/useReleaseDownloads";
import { useEffect } from "react";

type DlRedirectProps = {
  platformId: PlatformId;
};

export default function DlRedirect({ platformId }: DlRedirectProps) {
  const urls = useReleaseDownloads();
  const url = urls[platformId];
  const label = platforms.find((p) => p.id === platformId)?.label ?? "OXPlayer";

  useEffect(() => {
    if (url) window.location.replace(url);
  }, [url]);

  return (
    <Container className="py-24 text-center">
      <Heading level="h1">Redirecting…</Heading>
      <Paragraph className="mt-4 text-gray-400">
        Starting your {label} download.
      </Paragraph>
      {url ? (
        <a href={url} className="mt-8 inline-block text-primary hover:underline">
          Click here if the download doesn&apos;t start automatically
        </a>
      ) : null}
    </Container>
  );
}
