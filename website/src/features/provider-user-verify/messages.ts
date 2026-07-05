export type ProviderUserVerifyLocale = "en" | "fa";

export function parseProviderUserVerifyLocale(
  raw: string | null | undefined,
): ProviderUserVerifyLocale {
  const v = raw?.trim().toLowerCase();
  return v === "fa" ? "fa" : "en";
}

export type ProviderUserVerifyMessages = {
  pageTitle: string;
  pageDescription: string;
  title: string;
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
  notApproved: string;
  verifyFailed: string;
  networkError: string;
  retry: string;
};

export const providerUserVerifyMessages: Record<
  ProviderUserVerifyLocale,
  ProviderUserVerifyMessages
> = {
  en: {
    pageTitle: "Provider bot verification",
    pageDescription: "Verify access to the OXPlayer file delivery Telegram bot.",
    title: "File delivery bot verification",
    intro:
      "Access to the delivery bot is available to users in Iran only. Complete the check below to continue.",
    vpnHint: "If you are in Iran, turn VPN off before verifying.",
    verifyButton: "Verify access",
    verifying: "Verifying…",
    successTitle: "Verified successfully",
    successBody:
      "Your access is confirmed. Return to the delivery Telegram bot to continue.",
    returnToBot: "Return to delivery bot",
    errorTitle: "Error",
    invalidLink: "Invalid verification link. Open a new link from the bot.",
    expiredLink: "This link expired — open a new link from the bot.",
    notApproved:
      "You were not approved. Access is for Iran only. If you are in Iran, turn VPN off and try again.",
    verifyFailed: "Verification failed. Please try again.",
    networkError: "Could not connect. Check your internet or VPN.",
    retry: "Try again",
  },
  fa: {
    pageTitle: "تأیید ربات دریافت",
    pageDescription: "تأیید دسترسی به ربات دریافت فایل OXPlayer.",
    title: "تأیید دسترسی ربات دریافت",
    intro:
      "دسترسی به ربات دریافت فقط برای کاربران ایران است. برای ادامه تأیید را انجام دهید.",
    vpnHint: "اگر در ایران هستید، قبل از تأیید VPN را خاموش کنید.",
    verifyButton: "تأیید دسترسی",
    verifying: "در حال تأیید…",
    successTitle: "با موفقیت تأیید شدید",
    successBody:
      "دسترسی شما تأیید شد. برای ادامه به ربات دریافت برگردید.",
    returnToBot: "بازگشت به ربات دریافت",
    errorTitle: "خطا",
    invalidLink: "لینک تأیید نامعتبر است. از ربات دوباره لینک بگیرید.",
    expiredLink: "لینک منقضی شده — از ربات دوباره لینک بگیرید.",
    notApproved:
      "شما تأیید نشدید. دسترسی فقط برای ایران است. اگر در ایران هستید VPN را خاموش کنید و دوباره تلاش کنید.",
    verifyFailed: "تأیید انجام نشد. دوباره تلاش کنید.",
    networkError: "اتصال برقرار نشد. اینترنت یا VPN را بررسی کنید.",
    retry: "تلاش دوباره",
  },
};
