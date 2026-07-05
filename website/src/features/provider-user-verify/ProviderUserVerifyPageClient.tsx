"use client";

import Container from "@/components/ui/Container";
import ProviderUserVerifyClient from "@/features/provider-user-verify/ProviderUserVerifyClient";
import {
  parseProviderUserVerifyLocale,
  providerUserVerifyMessages,
} from "@/features/provider-user-verify/messages";
import { useSearchParams } from "next/navigation";
import { useEffect } from "react";

export default function ProviderUserVerifyPageClient() {
  const searchParams = useSearchParams();
  const locale = parseProviderUserVerifyLocale(searchParams.get("lang"));
  const token = searchParams.get("token")?.trim() ?? "";

  useEffect(() => {
    document.title = providerUserVerifyMessages[locale].pageTitle;
    document.documentElement.lang = locale;
    document.documentElement.dir = locale === "fa" ? "rtl" : "ltr";
  }, [locale]);

  return <ProviderUserVerifyClient locale={locale} token={token} />;
}

export function ProviderUserVerifyPageFallback() {
  return <Container className="py-24 text-center">Loading…</Container>;
}
