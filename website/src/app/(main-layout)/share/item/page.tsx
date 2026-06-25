import type { Metadata } from "next";
import { Suspense } from "react";

import ShareItemClient from "@/features/share/ShareItemClient";
import Container from "@/components/ui/Container";

export const metadata: Metadata = {
  title: "Open in OXPlayer",
  description: "Open a shared movie or series in OXPlayer.",
};

export default function ShareItemPage() {
  return (
    <Suspense fallback={<Container className="py-24 text-center">Loading…</Container>}>
      <ShareItemClient />
    </Suspense>
  );
}
