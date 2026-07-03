import type { Metadata } from "next";
import { Suspense } from "react";

import Container from "@/components/ui/Container";
import TelegramVerifyClient from "@/features/verify/TelegramVerifyClient";

export const metadata: Metadata = {
  title: "تأیید حساب",
  description: "تأیید حساب برای استفاده از ربات تلگرام OXPlayer.",
  robots: { index: false, follow: false },
};

export default function VerifyPage() {
  return (
    <Suspense fallback={<Container className="py-24 text-center">Loading…</Container>}>
      <TelegramVerifyClient />
    </Suspense>
  );
}
