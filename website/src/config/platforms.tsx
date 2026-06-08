import type { PlatformId } from "@/config/downloads";
import type { IconType } from "react-icons";
import {
  FaAndroid,
  FaApple,
  FaGlobe,
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
};

export const platforms: Platform[] = [
  { id: "Android", label: "Android", Icon: FaAndroid, heroMobile: true },
  { id: "AndroidTV", label: "Android TV", Icon: FaTv, heroMobile: false },
  { id: "iOS", label: "iOS", Icon: FaApple, heroMobile: true },
  { id: "Windows", label: "Windows", Icon: FaWindows, heroMobile: false },
  { id: "Linux", label: "Linux", Icon: FaLinux, heroMobile: false },
  { id: "Web", label: "Web", Icon: FaGlobe, heroMobile: true },
];

export const heroMobilePlatforms = platforms.filter((p) => p.heroMobile);
