/** Production marketing site origin (custom domain). */
export const SITE_ORIGIN = "https://oxplayer.app";

/** Flutter web app — global (Cloudflare → Hetzner). */
export const WEB_APP_ORIGIN = "https://web.oxplayer.app";

/** Flutter web app — Iran CDN.ir (free plan: *.ir.cdn.ir URL). */
export const WEB_APP_ORIGIN_IRAN = "https://oxweb.449494.ir.cdn.ir";

/** Public asset path safe for static export + client hydration. */
export function assetPath(path: string): string {
  return path.startsWith("/") ? path : `/${path}`;
}
