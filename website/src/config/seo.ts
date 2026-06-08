import type { Metadata } from "next";

import { assetPath, SITE_ORIGIN } from "./site";

export const SITE_NAME = "OXPlayer";

export const SITE_DESCRIPTION =
  "Transform your Telegram videos into a beautiful Netflix-style media library with smart organization, seamless playback, and powerful streaming features.";

/** Social preview image — 1200×630, built by scripts/build-og-image.mjs */
export const OG_IMAGE = {
  path: assetPath("/images/og-image.png"),
  width: 1200,
  height: 630,
  alt: "OXPlayer — Your Personal Telegram Cinema",
} as const;

export function siteUrl(path = ""): string {
  const normalized = path.startsWith("/") ? path : path ? `/${path}` : "";
  return `${SITE_ORIGIN}${normalized}`;
}

type PageMetadataOptions = {
  title?: string;
  description?: string;
  /** Path with leading slash; trailing slash optional (added when missing). */
  path?: string;
  ogImage?: typeof OG_IMAGE;
};

export function createPageMetadata({
  title,
  description = SITE_DESCRIPTION,
  path = "",
  ogImage = OG_IMAGE,
}: PageMetadataOptions = {}): Metadata {
  const pageTitle = title ?? SITE_NAME;
  const canonicalPath = path
    ? path.endsWith("/")
      ? path
      : `${path}/`
    : "/";
  const url = siteUrl(canonicalPath);

  return {
    metadataBase: new URL(`${SITE_ORIGIN}/`),
    title: title
      ? { absolute: pageTitle.includes(SITE_NAME) ? pageTitle : `${pageTitle} — ${SITE_NAME}` }
      : { default: SITE_NAME, template: `%s — ${SITE_NAME}` },
    description,
    keywords: [
      "OXPlayer",
      "Telegram",
      "media library",
      "streaming",
      "Netflix style",
      "video organizer",
      "personal cinema",
    ],
    alternates: {
      canonical: url,
    },
    openGraph: {
      type: "website",
      locale: "en_US",
      url,
      siteName: SITE_NAME,
      title: pageTitle,
      description,
      images: [
        {
          url: siteUrl(ogImage.path),
          width: ogImage.width,
          height: ogImage.height,
          alt: ogImage.alt,
        },
      ],
    },
    twitter: {
      card: "summary_large_image",
      title: pageTitle,
      description,
      images: [siteUrl(ogImage.path)],
    },
    robots: {
      index: true,
      follow: true,
      googleBot: {
        index: true,
        follow: true,
        "max-image-preview": "large",
        "max-snippet": -1,
      },
    },
  };
}
