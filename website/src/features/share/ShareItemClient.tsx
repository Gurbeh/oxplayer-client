"use client";

import { useSearchParams } from "next/navigation";

import ShareLanding from "@/features/share/ShareLanding";

export default function ShareItemClient() {
  const params = useSearchParams();
  const id = params.get("id") ?? "";
  const mediaSourceId = params.get("mediaSourceId") ?? undefined;
  return <ShareLanding catalogId={id} mediaSourceId={mediaSourceId} />;
}
