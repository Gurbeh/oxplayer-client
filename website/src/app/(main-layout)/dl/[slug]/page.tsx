import type { Metadata } from "next";
import { notFound } from "next/navigation";

import { DL_SLUG_TO_PLATFORM } from "@/config/downloads";
import DlRedirect from "@/features/dl/DlRedirect";

export const dynamicParams = false;

export function generateStaticParams() {
  return Object.keys(DL_SLUG_TO_PLATFORM).map((slug) => ({ slug }));
}

export const metadata: Metadata = {
  title: "Downloading OXPlayer…",
  robots: { index: false, follow: false },
};

type DlPageProps = {
  params: Promise<{ slug: string }>;
};

export default async function DlPage({ params }: DlPageProps) {
  const { slug } = await params;
  const platformId = DL_SLUG_TO_PLATFORM[slug];
  if (!platformId) notFound();

  return <DlRedirect platformId={platformId} />;
}
