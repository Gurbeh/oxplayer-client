import type { PlatformId } from "@/config/downloads";
import type { IconType } from "react-icons";
import {
  FaAndroid,
  FaApple,
  FaGlobe,
  FaGooglePlay,
  FaLinux,
  FaTv,
  FaWindows,
} from "react-icons/fa";

export type Platform = {
  id: PlatformId;
  label: string;
  Icon: IconType;
  /** Shown in the hero on small screens. */
  heroMobile: boolean;
  /** Temporarily unavailable — rendered disabled with Coming soon. */
  comingSoon?: boolean;
};

export const platforms: Platform[] = [
  { id: "Android", label: "Google Play", Icon: FaGooglePlay, heroMobile: true },
  {
    id: "AndroidPhone",
    label: "Android",
    Icon: FaAndroid,
    heroMobile: true,
  },
  {
    id: "AndroidTV",
    label: "TV & old Android",
    Icon: FaTv,
    heroMobile: true,
  },
  { id: "iOS", label: "iOS", Icon: FaApple, heroMobile: true },
  { id: "macOS", label: "macOS", Icon: FaApple, heroMobile: false },
  { id: "Windows", label: "Windows", Icon: FaWindows, heroMobile: false },
  { id: "Linux", label: "Linux", Icon: FaLinux, heroMobile: false },
  {
    id: "Web",
    label: "Web",
    Icon: FaGlobe,
    heroMobile: true,
    comingSoon: true,
  },
];

export const heroMobilePlatforms = platforms.filter((p) => p.heroMobile);
