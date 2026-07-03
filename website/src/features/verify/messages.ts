export type VerifyLocale = "en" | "fa";

export function parseVerifyLocale(raw: string | null | undefined): VerifyLocale {
  const v = raw?.trim().toLowerCase();
  return v === "fa" ? "fa" : "en";
}

export type VerifyMessages = {
  pageTitle: string;
  pageDescription: string;
  title: string;
  /** Persian title before Latin brand (e.g. تأیید حساب). */
  titlePrefix?: string;
  brandName: string;
  intro: string;
  vpnHint: string;
  verifyButton: string;
  verifying: string;
  successTitle: string;
  successBody: string;
  returnToBot: string;
  errorTitle: string;
  invalidLink: string;
  expiredLink: string;
  verifyFailed: string;
  networkError: string;
  retry: string;
};

export const verifyMessages: Record<VerifyLocale, VerifyMessages> = {
  en: {
    pageTitle: "Account verification",
    pageDescription: "Verify your account to use the OXPlayer Telegram bot.",
    title: "OXPlayer account verification",
    brandName: "OXPlayer",
    intro:
      "You must verify to use the Telegram bot. The OXPlayer app works fine without verification.",
    vpnHint: "If you are in Iran, turn VPN off before verifying.",
    verifyButton: "Verify account",
    verifying: "Verifying…",
    successTitle: "Verified successfully",
    successBody: "Your account is verified. Return to the Telegram bot to continue.",
    returnToBot: "Return to Telegram bot",
    errorTitle: "Error",
    invalidLink: "Invalid verification link. Open a new link from the bot.",
    expiredLink: "This link expired — open a new link from the bot.",
    verifyFailed: "Verification failed. Please try again.",
    networkError: "Could not connect. Check your internet or VPN.",
    retry: "Try again",
  },
  fa: {
    pageTitle: "تأیید حساب",
    pageDescription: "تأیید حساب برای استفاده از ربات تلگرام OXPlayer.",
    title: "تأیید حساب",
    titlePrefix: "تأیید حساب",
    brandName: "OXPlayer",
    intro:
      "برای استفاده از ربات تلگرام باید حساب خود را تأیید کنید. اپ OXPlayer بدون تأیید هم کار می‌کند.",
    vpnHint: "اگر در ایران هستید، قبل از تأیید VPN را خاموش کنید.",
    verifyButton: "تأیید حساب",
    verifying: "در حال تأیید…",
    successTitle: "با موفقیت تأیید شدید",
    successBody: "حساب شما تأیید شد. برای ادامه به ربات تلگرام برگردید.",
    returnToBot: "بازگشت به ربات تلگرام",
    errorTitle: "خطا",
    invalidLink: "لینک تأیید نامعتبر است. از ربات دوباره لینک بگیرید.",
    expiredLink: "لینک منقضی شده — از ربات دوباره لینک بگیرید.",
    verifyFailed: "تأیید انجام نشد. دوباره تلاش کنید.",
    networkError: "اتصال برقرار نشد. اینترنت یا VPN را بررسی کنید.",
    retry: "تلاش دوباره",
  },
};
