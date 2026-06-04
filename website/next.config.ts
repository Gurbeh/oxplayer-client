import type { NextConfig } from "next";

import { SITE_BASE_PATH } from "./src/config/site";

const isProd = process.env.NODE_ENV === "production";
const basePath = isProd ? SITE_BASE_PATH : "";

const nextConfig: NextConfig = {
  output: "export",
  basePath,
  assetPrefix: basePath ? `${basePath}/` : undefined,
  trailingSlash: true,
  images: { unoptimized: true },
};

export default nextConfig;
