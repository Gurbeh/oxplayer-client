"use client";

import Container from "@/components/ui/Container";
import Heading from "@/components/ui/Heading";
import Paragraph from "@/components/ui/Paragraph";
import { SITE_ORIGIN } from "@/config/site";
import PlatformDownloads from "@/features/home/PlatformDownloads";
import clsx from "clsx";
import { useMemo } from "react";

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

type ShareLandingProps = {
  catalogId: string;
};

function detectPlatform(): "android" | "ios" | "desktop" {
  if (typeof navigator === "undefined") return "desktop";
  const ua = navigator.userAgent || "";
  if (/android/i.test(ua)) return "android";
  if (/iPhone|iPad|iPod/i.test(ua)) return "ios";
  return "desktop";
}

const linkButtonClass = clsx(
  "inline-flex items-center justify-center rounded-xl px-5 py-3 font-bold",
  "bg-gradient-to-r from-primary via-secondary-500 to-secondary text-white",
  "transition-all duration-300 hover:-translate-y-1 hover:shadow-lg",
);

const secondaryLinkClass = clsx(
  "inline-flex items-center justify-center rounded-xl px-5 py-3 font-bold",
  "border border-slate-600 text-gray-100",
  "transition-all duration-300 hover:border-primary",
);

export default function ShareLanding({ catalogId }: ShareLandingProps) {
  const id = catalogId.trim();
  const valid = UUID_RE.test(id);
  const platform = useMemo(() => detectPlatform(), []);

  const shareUrl = `${SITE_ORIGIN}/share/${id}`;
  const webAppUrl = `${SITE_ORIGIN}/web/#/details?id=${encodeURIComponent(id)}`;
  const customSchemeUrl = `oxplayer:///share/${id}`;
  const androidIntent = `intent://share/${id}#Intent;scheme=https;host=oxplayer.app;package=app.oxplayer;S.browser_fallback_url=${encodeURIComponent(shareUrl)};end`;

  const openInAppHref =
    platform === "android"
      ? androidIntent
      : platform === "ios"
        ? shareUrl
        : customSchemeUrl;

  if (!valid) {
    return (
      <Container className="py-24 text-center">
        <Heading level="h1">Invalid link</Heading>
        <Paragraph className="mt-4 text-gray-400">
          This share link is not valid. Ask the sender for a new link.
        </Paragraph>
      </Container>
    );
  }

  return (
    <Container className="py-16 md:py-24">
      <div className="mx-auto max-w-xl text-center">
        <Heading level="h1">Open in OXPlayer</Heading>
        <Paragraph className="mt-4 text-gray-300">
          Someone shared a movie or series with you. Open it in the OXPlayer app if you
          have access, or try the web player on desktop.
        </Paragraph>

        <div className="mt-10 flex flex-col gap-3 sm:flex-row sm:justify-center">
          <a href={openInAppHref} className={linkButtonClass}>
            Open in app
          </a>
          {platform === "desktop" ? (
            <a href={webAppUrl} className={secondaryLinkClass}>
              Open in web player
            </a>
          ) : null}
        </div>

        <div className="mt-14">
          <Paragraph className="mb-6 text-sm text-gray-400">
            Don&apos;t have OXPlayer yet?
          </Paragraph>
          <PlatformDownloads />
        </div>
      </div>
    </Container>
  );
}
