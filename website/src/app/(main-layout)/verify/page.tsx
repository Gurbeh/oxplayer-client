import type { Metadata } from "next";
import { Suspense } from "react";

import VerifyPageClient, { VerifyPageFallback } from "@/features/verify/VerifyPageClient";
import { verifyMessages } from "@/features/verify/messages";

export const metadata: Metadata = {
  title: verifyMessages.en.pageTitle,
  description: verifyMessages.en.pageDescription,
  robots: { index: false, follow: false },
};

export default function VerifyPage() {
  return (
    <Suspense fallback={<VerifyPageFallback />}>
      <VerifyPageClient />
    </Suspense>
  );
}
