import type { MetadataRoute } from "next";

import { SITE_DESCRIPTION, SITE_NAME } from "@/config/seo";
import { assetPath } from "@/config/site";

export const dynamic = "force-static";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: SITE_NAME,
    short_name: SITE_NAME,
    description: SITE_DESCRIPTION,
    start_url: "/",
    display: "standalone",
    background_color: "#ffffff",
    theme_color: "#EDAE49",
    icons: [
      {
        src: assetPath("/images/logo.png"),
        sizes: "512x512",
        type: "image/png",
      },
    ],
  };
}
