"use client";

import Container from "@/components/ui/Container";
import TelegramVerifyClient from "@/features/verify/TelegramVerifyClient";
import { parseVerifyLocale } from "@/features/verify/messages";
import { useSearchParams } from "next/navigation";
import { useEffect } from "react";
import { verifyMessages } from "@/features/verify/messages";

export default function VerifyPageClient() {
  const searchParams = useSearchParams();
  const locale = parseVerifyLocale(searchParams.get("lang"));
  const token = searchParams.get("token")?.trim() ?? "";

  useEffect(() => {
    document.title = verifyMessages[locale].pageTitle;
    document.documentElement.lang = locale;
    document.documentElement.dir = locale === "fa" ? "rtl" : "ltr";
  }, [locale]);

  return <TelegramVerifyClient locale={locale} token={token} />;
}

export function VerifyPageFallback() {
  return <Container className="py-24 text-center">Loading…</Container>;
}
