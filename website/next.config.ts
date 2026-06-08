import type { NextConfig } from "next";
import path from "node:path";
import { fileURLToPath } from "node:url";

/** Website package root — avoids Turbopack picking oxplayer-client/ lockfile as workspace root. */
const websiteRoot = path.dirname(fileURLToPath(import.meta.url));

const nextConfig: NextConfig = {
  output: "export",
  trailingSlash: true,
  images: { unoptimized: true },
  turbopack: {
    root: websiteRoot,
  },
  outputFileTracingRoot: websiteRoot,
};

export default nextConfig;
