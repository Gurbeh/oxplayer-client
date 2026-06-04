/** GitHub Pages project site — must match repo name and next.config basePath. */
export const SITE_BASE_PATH = "/oxplayer-client";

export const SITE_ORIGIN = `https://gurbeh.github.io${SITE_BASE_PATH}`;

/** Public asset path safe for static export + client hydration. */
export function assetPath(path: string): string {
  const normalized = path.startsWith("/") ? path : `/${path}`;
  const base = process.env.NODE_ENV === "development" ? "" : SITE_BASE_PATH;
  return `${base}${normalized}`;
}
