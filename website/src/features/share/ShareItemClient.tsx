"use client";

import { useSearchParams } from "next/navigation";

import ShareLanding from "@/features/share/ShareLanding";

export default function ShareItemClient() {
  const params = useSearchParams();
  const id = params.get("id") ?? "";
  return <ShareLanding catalogId={id} />;
}
