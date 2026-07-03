"use client";

import Container from "@/components/ui/Container";
import Heading from "@/components/ui/Heading";
import Paragraph from "@/components/ui/Paragraph";
import { TELEGRAM_VERIFY_API } from "@/config/api";
import { OXPLAYER_BOT } from "@/config/bots";
import clsx from "clsx";
import { useSearchParams } from "next/navigation";
import { useCallback, useMemo, useState } from "react";

type VerifyState = "idle" | "loading" | "success" | "error";

const primaryButtonClass = clsx(
  "inline-flex w-full items-center justify-center rounded-xl px-5 py-3 font-bold",
  "bg-gradient-to-r from-primary via-secondary-500 to-secondary text-white",
  "transition-all duration-300 hover:-translate-y-1 hover:shadow-lg",
  "disabled:cursor-wait disabled:opacity-60 disabled:hover:translate-y-0",
);

const botReturnUrl = `${OXPLAYER_BOT.url}?start=verified`;

type VerifyResponse = {
  ok?: boolean;
  iran?: boolean;
  botDeepLink?: string;
  error?: string;
};

export default function TelegramVerifyClient() {
  const searchParams = useSearchParams();
  const token = useMemo(() => searchParams.get("token")?.trim() ?? "", [searchParams]);
  const [state, setState] = useState<VerifyState>(token ? "idle" : "error");
  const [errorText, setErrorText] = useState(
    token ? "" : "لینک تأیید نامعتبر است. از ربات دوباره لینک بگیرید.",
  );
  const [botLink, setBotLink] = useState(botReturnUrl);

  const verify = useCallback(async () => {
    if (!token) {
      setState("error");
      setErrorText("لینک تأیید نامعتبر است. از ربات دوباره لینک بگیرید.");
      return;
    }
    setState("loading");
    setErrorText("");
    try {
      const res = await fetch(TELEGRAM_VERIFY_API, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ token }),
      });
      const data = (await res.json()) as VerifyResponse;
      if (!res.ok || !data.ok) {
        setState("error");
        if (data.error === "expired_token") {
          setErrorText("لینک منقضی شده — از ربات دوباره لینک بگیرید.");
        } else {
          setErrorText("تأیید انجام نشد. دوباره تلاش کنید.");
        }
        return;
      }
      setBotLink(data.botDeepLink?.trim() || botReturnUrl);
      setState("success");
    } catch {
      setState("error");
      setErrorText("اتصال برقرار نشد. اینترنت یا VPN را بررسی کنید.");
    }
  }, [token]);

  if (state === "success") {
    return (
      <Container className="py-16 md:py-24">
        <div className="mx-auto max-w-lg text-center">
          <Heading level="h1">✅ با موفقیت تأیید شدید</Heading>
          <Paragraph className="mt-4 text-gray-300">
            حساب شما تأیید شد. برای ادامه به ربات تلگرام برگردید.
          </Paragraph>
          <a href={botLink} className={clsx(primaryButtonClass, "mt-8")}>
            بازگشت به ربات تلگرام
          </a>
          <Paragraph className="mt-8 text-sm text-gray-500 text-center" align="center">
            Verified successfully. Return to the Telegram bot to continue.
          </Paragraph>
        </div>
      </Container>
    );
  }

  if (state === "error") {
    return (
      <Container className="py-16 md:py-24">
        <div className="mx-auto max-w-lg text-center">
          <Heading level="h1">خطا</Heading>
          <Paragraph className="mt-4 text-red-300">{errorText}</Paragraph>
          <button type="button" className={clsx(primaryButtonClass, "mt-8")} onClick={() => verify()}>
            تلاش دوباره
          </button>
        </div>
      </Container>
    );
  }

  return (
    <Container className="py-16 md:py-24">
      <div className="mx-auto max-w-lg text-center">
        <Heading level="h1">تأیید حساب OXPlayer</Heading>
        <Paragraph className="mt-4 text-gray-300">
          برای استفاده از <b>ربات تلگرام</b> باید حساب خود را تأیید کنید. اپ OXPlayer بدون تأیید هم
          کار می‌کند.
        </Paragraph>
        <Paragraph className="mt-3 text-gray-300">
          اگر در <b>ایران</b> هستید، قبل از تأیید <b>VPN را خاموش</b> کنید.
        </Paragraph>
        <button
          type="button"
          className={clsx(primaryButtonClass, "mt-8")}
          disabled={state === "loading"}
          onClick={() => verify()}
        >
          {state === "loading" ? "در حال تأیید…" : "تأیید حساب"}
        </button>
        <Paragraph className="mt-8 text-sm text-gray-500 text-center" align="center">
          Account verification for the Telegram bot only. If you are in Iran, turn VPN off, then tap
          Verify.
        </Paragraph>
      </div>
    </Container>
  );
}
