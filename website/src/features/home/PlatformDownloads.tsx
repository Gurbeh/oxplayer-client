"use client";

import Button from "@/components/ui/Button";
import { resolvePlatformUrl, type PlatformId } from "@/config/downloads";
import { platforms, type Platform } from "@/config/platforms";
import { useReleaseDownloadUrls } from "@/providers/ReleaseDownloadsProvider";
import clsx from "clsx";
import { useEffect, useState } from "react";
import { FaDownload } from "react-icons/fa";

const WINDOWS_DEFENDER_ISSUE_URL =
  "https://github.com/DonutWare/Fladder/issues/197#issuecomment-2568906874";

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
  onWindowsClick?: () => void;
};

const PlatformCard = ({
  platform,
  href,
  compact = false,
  onWindowsClick,
}: PlatformCardProps) => {
  const { Icon } = platform;
  const content = (
    <>
      <Icon className={compact ? "text-2xl" : "text-3xl"} />
      <span
        className={clsx(
          "font-medium text-gray-100 whitespace-nowrap",
          compact && "text-sm",
        )}
      >
        {platform.label}
      </span>
    </>
  );

  if (platform.id === "Windows" && onWindowsClick) {
    return (
      <button
        type="button"
        onClick={onWindowsClick}
        className={cardClassName(compact)}
      >
        {content}
      </button>
    );
  }

  return (
    <a
      href={href}
      target="_blank"
      rel="noopener noreferrer"
      className={cardClassName(compact)}
    >
      {content}
    </a>
  );
};

type WindowsDownloadModalProps = {
  downloadUrl: string;
  onClose: () => void;
};

const WindowsDownloadModal = ({
  downloadUrl,
  onClose,
}: WindowsDownloadModalProps) => {
  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") onClose();
    };

    document.addEventListener("keydown", onKeyDown);
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";

    return () => {
      document.removeEventListener("keydown", onKeyDown);
      document.body.style.overflow = previousOverflow;
    };
  }, [onClose]);

  const startDownload = () => {
    window.open(downloadUrl, "_blank", "noopener,noreferrer");
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
      <button
        type="button"
        aria-label="Close"
        className="absolute inset-0 bg-black/60 backdrop-blur-sm"
        onClick={onClose}
      />
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="windows-download-modal-title"
        className="relative z-10 w-full max-w-lg rounded-xl border border-slate-700 bg-slate-900 p-6 shadow-2xl"
      >
        <h2
          id="windows-download-modal-title"
          className="text-lg font-semibold text-gray-100"
        >
          Windows download
        </h2>
        <p className="mt-4 text-base leading-relaxed text-gray-300">
          Some Flutter applications are marked as false positives by Windows
          Defender. For more info see{" "}
          <a
            href={WINDOWS_DEFENDER_ISSUE_URL}
            target="_blank"
            rel="noopener noreferrer"
            className="text-primary hover:underline"
          >
            this issue
          </a>
          .
        </p>
        <div className="mt-6 flex flex-wrap justify-end gap-3">
          <Button
            type="button"
            action="secondary"
            variant="outline"
            size="sm"
            onClick={onClose}
          >
            Cancel
          </Button>
          <Button type="button" size="sm" onClick={startDownload}>
            Download
          </Button>
        </div>
      </div>
    </div>
  );
};

const DownloadMoreCard = ({ compact = false }: { compact?: boolean }) => (
  <button
    type="button"
    onClick={scrollToDownloadSection}
    className={cardClassName(compact)}
  >
    <FaDownload className={compact ? "text-2xl" : "text-3xl"} />
    <span
      className={clsx(
        "font-medium text-gray-100 whitespace-nowrap",
        compact && "text-sm",
      )}
    >
      Other platforms
    </span>
  </button>
);

type PlatformDownloadsProps = {
  items?: Platform[];
  showDownloadMore?: boolean;
  className?: string;
};

const PlatformDownloads = ({
  items = platforms,
  showDownloadMore = false,
  className = "",
}: PlatformDownloadsProps) => {
  const urls = useReleaseDownloadUrls();
  const [windowsDownloadUrl, setWindowsDownloadUrl] = useState<string | null>(
    null,
  );

  return (
    <div className={className}>
      <div className="flex flex-wrap justify-center gap-2 sm:gap-4">
        {items.map((platform) => {
          const href =
            urls[platform.id as PlatformId] ??
            resolvePlatformUrl(platform.id, []);

          return (
            <PlatformCard
              key={platform.id}
              platform={platform}
              href={href}
              compact={showDownloadMore}
              onWindowsClick={
                platform.id === "Windows"
                  ? () => setWindowsDownloadUrl(href)
                  : undefined
              }
            />
          );
        })}
        {showDownloadMore && <DownloadMoreCard compact />}
      </div>

      {windowsDownloadUrl && (
        <WindowsDownloadModal
          downloadUrl={windowsDownloadUrl}
          onClose={() => setWindowsDownloadUrl(null)}
        />
      )}
    </div>
  );
};

export default PlatformDownloads;
