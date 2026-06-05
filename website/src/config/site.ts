/** Production site origin (custom domain). */
export const SITE_ORIGIN = "https://oxplayer.app";

/** Public asset path safe for static export + client hydration. */
export function assetPath(path: string): string {
  return path.startsWith("/") ? path : `/${path}`;
}
