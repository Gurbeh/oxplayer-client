/** Jellyfin-compatible API (telegram verify, auth, catalog). */
export const API_ORIGIN =
  process.env.NEXT_PUBLIC_OXPLAYER_API_ORIGIN ?? "https://api.oxplayer.app";

export const TELEGRAM_VERIFY_API = `${API_ORIGIN}/web/verify`;
