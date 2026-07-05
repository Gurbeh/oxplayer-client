import type { Metadata } from "next";
import { Suspense } from "react";

import ProviderUserVerifyPageClient, {
  ProviderUserVerifyPageFallback,
} from "@/features/provider-user-verify/ProviderUserVerifyPageClient";
import { providerUserVerifyMessages } from "@/features/provider-user-verify/messages";

export const metadata: Metadata = {
  title: providerUserVerifyMessages.fa.pageTitle,
  description: providerUserVerifyMessages.fa.pageDescription,
  robots: { index: false, follow: false },
};

export default function ProviderUserVerifyPage() {
  return (
    <Suspense fallback={<ProviderUserVerifyPageFallback />}>
      <ProviderUserVerifyPageClient />
    </Suspense>
  );
}
