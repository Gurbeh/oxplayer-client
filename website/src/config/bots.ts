export const OXPLAYER_BOT = {
  username: "OXPlayerBot",
  url: "https://telegram.me/OXPlayerBot",
} as const;

const providerUserBotUsername =
  process.env.NEXT_PUBLIC_PROVIDER_USER_BOT_USERNAME ?? "OXPlayerProviderBot";

export const PROVIDER_USER_BOT = {
  username: providerUserBotUsername,
  url: `https://telegram.me/${providerUserBotUsername}`,
} as const;

export const SUPPORT_BOT = {
  username: "MySupport2026Bot",
  url: "https://telegram.me/MySupport2026Bot",
} as const;

export const SUPPORT_EMAIL = "oxplayerapp@gmail.com";
