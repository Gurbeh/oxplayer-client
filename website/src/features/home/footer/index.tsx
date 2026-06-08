"use client";
import Container from "@/components/ui/Container";
import Heading from "@/components/ui/Heading";
import Paragraph from "@/components/ui/Paragraph";
import { SUPPORT_BOT } from "@/config/bots";
import PlatformDownloads from "@/features/home/PlatformDownloads";
import Link from "next/link";

const issuesUrl = "https://github.com/Gurbeh/oxplayer-client/issues";

const Footer = () => {
  return (
    <section
      id="footer"
      className="relative pt-20 pb-1 border-t border-slate-700 overflow-hidden"
    >
      {/* 🔵 Primary Gradient */}
      <div className="absolute -top-20 -left-20 w-60 h-60 md:w-72 md:h-72 lg:w-96 lg:h-96 bg-primary opacity-30 blur-3xl rounded-full" />

      {/* 🟣 Secondary Gradient */}
      <div className="absolute -top-20 -right-20 w-60 h-60 md:w-72 md:h-72 lg:w-96 lg:h-96 bg-secondary opacity-30 blur-3xl rounded-full" />

      <Container className="flex flex-col items-center relative z-10">
        <Heading level="h2" align="center" className="!text-gray-100">
          Experience{" "}
          <span className="bg-gradient-to-r from-primary to-secondary bg-clip-text text-transparent">
            OXPlayer
          </span>{" "}
          Everywhere
        </Heading>

        <div className="max-w-2xl mt-4">
          <Paragraph align="center" className="text-gray-400">
            Watch, organize, and enjoy your Telegram media library seamlessly
            across all your devices.
          </Paragraph>
        </div>

        <div id="download" className="mt-10">
          <PlatformDownloads />
        </div>

        <ul className="flex flex-wrap justify-center gap-2 sm:gap-7 mt-20">
          <li>
            <a href={SUPPORT_BOT.url} target="_blank" rel="noopener noreferrer">
              <Paragraph
                size="sm"
                className="!text-gray-400 cursor-pointer hover:!text-primary transition-all duration-300"
              >
                Support (@{SUPPORT_BOT.username})
              </Paragraph>
            </a>
          </li>

          <li className="">
            <Paragraph className="!text-gray-500">•</Paragraph>
          </li>

          <li>
            <Link href="/privacy-policy/">
              <Paragraph
                size="sm"
                className="!text-gray-400 cursor-pointer hover:!text-primary transition-all duration-300"
              >
                Privacy Policy
              </Paragraph>
            </Link>
          </li>

          <li className="">
            <Paragraph className="!text-gray-500">•</Paragraph>
          </li>

          <li>
            <a href={issuesUrl} target="_blank" rel="noopener noreferrer">
              <Paragraph
                size="sm"
                className="!text-gray-400 cursor-pointer hover:!text-primary transition-all duration-300"
              >
                Terms of Service
              </Paragraph>
            </a>
          </li>
        </ul>

        <Paragraph size="sm" className="!text-gray-500 mt-8 text-center">
          © {new Date().getFullYear()} OXPlayer. All rights reserved.
        </Paragraph>
      </Container>
    </section>
  );
};

export default Footer;
