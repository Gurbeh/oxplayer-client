"use client";

import Container from "@/components/ui/Container";
import Heading from "@/components/ui/Heading";
import Paragraph from "@/components/ui/Paragraph";
import { TELEGRAM_VERIFY_API } from "@/config/api";
import { OXPLAYER_BOT } from "@/config/bots";
import { verifyMessages, type VerifyLocale } from "@/features/verify/messages";
import clsx from "clsx";
import { useCallback, useState, type ReactNode } from "react";

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

type TelegramVerifyClientProps = {
  locale: VerifyLocale;
  token: string;
};

function VerifyPageShell({
  locale,
  children,
}: {
  locale: VerifyLocale;
  children: ReactNode;
}) {
  const isRtl = locale === "fa";
  return (
    <div
      dir={isRtl ? "rtl" : "ltr"}
      lang={locale}
      className={clsx(isRtl && "font-vazirmatn")}
    >
      {children}
    </div>
  );
}

function VerifyTitle({ locale }: { locale: VerifyLocale }) {
  const t = verifyMessages[locale];
  const isRtl = locale === "fa";

  if (isRtl && t.titlePrefix) {
    return (
      <Heading
        level="h1"
        align="center"
        className="font-vazirmatn !text-center"
      >
        {t.titlePrefix}{" "}
        <bdi dir="ltr" className="inline-block font-space tracking-tight">
          {t.brandName}
        </bdi>
      </Heading>
    );
  }

  return (
    <Heading level="h1" align="center" className="font-space !text-center">
      {t.title}
    </Heading>
  );
}

function VerifyHeading({
  locale,
  children,
}: {
  locale: VerifyLocale;
  children: ReactNode;
}) {
  const isRtl = locale === "fa";
  return (
    <Heading
      level="h1"
      align="center"
      className={clsx(isRtl ? "font-vazirmatn" : "font-space", "!text-center")}
    >
      {children}
    </Heading>
  );
}

function VerifyText({
  locale,
  className,
  children,
}: {
  locale: VerifyLocale;
  className?: string;
  children: ReactNode;
}) {
  const isRtl = locale === "fa";
  return (
    <Paragraph
      align="center"
      className={clsx(isRtl && "font-vazirmatn", className)}
    >
      {children}
    </Paragraph>
  );
}

export default function TelegramVerifyClient({
  locale,
  token,
}: TelegramVerifyClientProps) {
  const t = verifyMessages[locale];
  const isRtl = locale === "fa";

  const [state, setState] = useState<VerifyState>(token ? "idle" : "error");
  const [errorText, setErrorText] = useState(token ? "" : t.invalidLink);
  const [botLink, setBotLink] = useState(botReturnUrl);

  const verify = useCallback(async () => {
    if (!token) {
      setState("error");
      setErrorText(t.invalidLink);
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
        setErrorText(
          data.error === "expired_token" ? t.expiredLink : t.verifyFailed,
        );
        return;
      }
      setBotLink(data.botDeepLink?.trim() || botReturnUrl);
      setState("success");
    } catch {
      setState("error");
      setErrorText(t.networkError);
    }
  }, [token, t.expiredLink, t.invalidLink, t.networkError, t.verifyFailed]);

  const shellClass = "mx-auto max-w-lg text-center";

  if (state === "success") {
    return (
      <VerifyPageShell locale={locale}>
        <Container className="py-16 md:py-24">
          <div className={shellClass}>
            <VerifyHeading locale={locale}>
              {isRtl ? (
                <>
                  {t.successTitle} <span aria-hidden="true">✅</span>
                </>
              ) : (
                <>
                  <span aria-hidden="true">✅</span> {t.successTitle}
                </>
              )}
            </VerifyHeading>
            <VerifyText locale={locale} className="mt-4 text-gray-300">
              {t.successBody}
            </VerifyText>
            <a
              href={botLink}
              className={clsx(
                primaryButtonClass,
                "mt-8",
                isRtl && "font-vazirmatn",
              )}
            >
              {t.returnToBot}
            </a>
          </div>
        </Container>
      </VerifyPageShell>
    );
  }

  if (state === "error") {
    return (
      <VerifyPageShell locale={locale}>
        <Container className="py-16 md:py-24">
          <div className={shellClass}>
            <VerifyHeading locale={locale}>{t.errorTitle}</VerifyHeading>
            <VerifyText locale={locale} className="mt-4 text-red-300">
              {errorText}
            </VerifyText>
            <button
              type="button"
              className={clsx(
                primaryButtonClass,
                "mt-8",
                isRtl && "font-vazirmatn",
              )}
              onClick={() => verify()}
            >
              {t.retry}
            </button>
          </div>
        </Container>
      </VerifyPageShell>
    );
  }

  return (
    <VerifyPageShell locale={locale}>
      <Container className="py-16 md:py-24">
        <div className={shellClass}>
          <VerifyTitle locale={locale} />
          <VerifyText locale={locale} className="mt-4 text-gray-300">
            {t.intro}
          </VerifyText>
          <VerifyText locale={locale} className="mt-3 text-gray-300">
            🚨⚠️ {t.vpnHint} ⚠️🚨
          </VerifyText>
          <button
            type="button"
            className={clsx(
              primaryButtonClass,
              "mt-8",
              isRtl && "font-vazirmatn",
            )}
            disabled={state === "loading"}
            onClick={() => verify()}
          >
            {state === "loading" ? t.verifying : t.verifyButton}
          </button>
        </div>
      </Container>
    </VerifyPageShell>
  );
}
