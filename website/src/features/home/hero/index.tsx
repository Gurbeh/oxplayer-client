"use client";
import Container from "@/components/ui/Container";
import Heading from "@/components/ui/Heading";
import Image from "next/image";
import { Fragment } from "react";
import { assetPath } from "@/config/site";
import PlatformDownloads from "@/features/home/PlatformDownloads";
import { heroMobilePlatforms } from "@/config/platforms";

export const GlowDot = ({
  size = "md",
  color = "cyan",
  className = "",
}: {
  size?: "xs" | "sm" | "md" | "lg";
  color?: "cyan" | "purple" | "pink";
  className?: string;
}) => {
  const sizes = {
    xs: "w-1 h-1",
    sm: "w-1.5 h-1.5",
    md: "w-3 h-3",
    lg: "w-5 h-5",
  };

  const colors = {
    cyan: "bg-primary shadow-primary-400",
    purple: "bg-secondary shadow-secondary-400",
    pink: "bg-secondary shadow-secondary",
  };

  return (
    <div
      className={`
        absolute rounded-full blur-xs z-0
        ${sizes[size]}
        ${colors[color]}
        shadow-[0_0_15px]
        animate-pulse
        ${className}
      `}
    />
  );
};

const Hero = () => {
  return (
    <Fragment>
      <section className="relative py-10 sm:py-10 lg:py-14 2xl:py-20 3xl:py-40 overflow-hidden">
        {/* Glow Dots */}
        <GlowDot size="sm" color="cyan" className="top-20 left-[25%]" />
        <GlowDot size="md" color="cyan" className="bottom-10 left-[25%]" />
        <GlowDot size="lg" color="cyan" className="top-52 left-[15%]" />
        <GlowDot size="lg" color="purple" className="bottom-10 right-[20%]" />
        <GlowDot size="md" color="purple" className="top-32 right-[20%]" />
        <GlowDot size="lg" color="purple" className="top-72 right-[15%]" />

        {/* 🔵 Primary Gradient (Top Left) */}
        <div className="absolute -top-20 -left-20 w-60 h-60 md:w-72 md:h-72 lg:w-96 lg:h-96 bg-primary opacity-30 blur-3xl rounded-full" />

        {/* 🟣 Secondary Gradient (Top Right) */}
        <div className="absolute -top-20 -right-20  w-60 h-60 md:w-72 md:h-72 lg:w-96 lg:h-96 bg-gradient-to-r from-secondary to-secondary opacity-30 blur-3xl rounded-full" />

        <Container>
          <div className="flex justify-center">
            <div className="flex gap-3 sm:gap-5 items-center">
              <div className="relative h-[70px] w-[70px] sm:h-[100px] sm:w-[100px]">
                <Image src={assetPath("/images/logo.png")} alt="movie-scene" fill className="object-contain" />
              </div>
              <Heading
                level="h1"
                size="2xl"
                font="space"
                align="center"
                className="bg-gradient-to-r from-primary to-secondary bg-clip-text text-transparent"
              >
                OXPlayer
              </Heading>
            </div>
          </div>
          <Heading level="h1" size="2xl" font="space" align="center" className="!text-gray-100 mt-7 hidden sm:block">
            Your Personal Telegram Cinema
          </Heading>
          <Heading level="h1" size="2xl" font="space" align="center" className="!text-gray-100 mt-7 sm:hidden">
            Telegram Cinema
          </Heading>

          <Heading level="h1" size="2xl" font="space" align="center" className="!text-gray-100 mt-2">
            Organize . Watch . Enjoy
          </Heading>

          <PlatformDownloads items={heroMobilePlatforms} showDownloadMore className="mt-7 sm:hidden" />
          <PlatformDownloads className="mt-7 hidden sm:block" />
        </Container>
      </section>
    </Fragment>
  );
};
export default Hero;
