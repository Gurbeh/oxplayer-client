"use client";

import type { PlatformId } from "@/config/downloads";
import { platforms, type Platform } from "@/config/platforms";
import { useReleaseDownloadUrls } from "@/providers/ReleaseDownloadsProvider";
import { FaDownload } from "react-icons/fa";
import clsx from "clsx";

const scrollToDownloadSection = () => {
  document.getElementById("download")?.scrollIntoView({
    behavior: "smooth",
    block: "start",
  });
};

const cardClassName = (compact: boolean) =>
  clsx(
    "flex items-center rounded-xl border border-slate-700 bg-slate-900/50 backdrop-blur-sm transition-all duration-300 cursor-pointer hover:border-primary shrink-0",
    compact ? "gap-2 px-3 py-3" : "gap-3 px-6 py-4",
  );

type PlatformCardProps = {
  platform: Platform;
  href: string;
  compact?: boolean;
};

const PlatformCard = ({ platform, href, compact = false }: PlatformCardProps) => {
  const { Icon } = platform;

  return (
    <a
      href={href}
      target="_blank"
      rel="noopener noreferrer"
      className={cardClassName(compact)}
    >
      <Icon className={compact ? "text-2xl" : "text-3xl"} />
      <span className={clsx("font-medium text-gray-100 whitespace-nowrap", compact && "text-sm")}>{platform.label}</span>
    </a>
  );
};

const DownloadMoreCard = ({ compact = false }: { compact?: boolean }) => (
  <button type="button" onClick={scrollToDownloadSection} className={cardClassName(compact)}>
    <FaDownload className={compact ? "text-2xl" : "text-3xl"} />
    <span className={clsx("font-medium text-gray-100 whitespace-nowrap", compact && "text-sm")}>Other platforms</span>
  </button>
);

type PlatformDownloadsProps = {
  items?: Platform[];
  showDownloadMore?: boolean;
  className?: string;
};

const PlatformDownloads = ({ items = platforms, showDownloadMore = false, className = "" }: PlatformDownloadsProps) => {
  const urls = useReleaseDownloadUrls();

  return (
    <div className={className}>
      <div className="flex flex-wrap justify-center gap-2 sm:gap-4">
        {items.map((platform) => (
          <PlatformCard
            key={platform.id}
            platform={platform}
            href={urls[platform.id as PlatformId] ?? "#"}
            compact={showDownloadMore}
          />
        ))}
        {showDownloadMore && <DownloadMoreCard compact />}
      </div>
    </div>
  );
};

export default PlatformDownloads;
