import Container from "@/components/ui/Container";
import Heading from "@/components/ui/Heading";
import Paragraph from "@/components/ui/Paragraph";
import TelegramBotLink from "@/components/ui/TelegramBotLink";
import { OXPLAYER_BOT } from "@/config/bots";
import { assetPath } from "@/config/site";
import Image from "next/image";
import type { ReactNode } from "react";
import { GlowDot } from "../hero";

const Card = ({
  title,
  img,
  des,
}: {
  title: string;
  img: string;
  des: ReactNode;
}) => {
  return (
    <div className="flex flex-col md:items-center z-10 relative">
      <div className="h-2 bg-gradient-to-r from-primary to-secondary absolute top-10 left-[90px] w-[110%] -z-30 rounded-full md:hidden"></div>

      <div className="bg-slate-900 rounded-xl border border-slate-700 w-fit p-5">
        <div className="relative w-full h-[50px] sm:h-[100px] aspect-square">
          <Image src={img} alt="movie-scene" fill className="object-contain" />
        </div>
      </div>

      <Heading level="h6" size="md" className="mt-3 md:text-center">
        {title}
      </Heading>
      <Paragraph size="sm" className="text-gray-400 mt-2 md:text-center">
        {des}
      </Paragraph>
    </div>
  );
};

const HowItWorks = () => {
  return (
    <section
      id="how-it-works"
      className="relative pt-24 lg:pt-40 overflow-hidden"
    >
      {/* Glow Dots */}
      <GlowDot
        size="xs"
        color="cyan"
        className="bottom-96 left-[4%] !blur-none"
      />
      <GlowDot
        size="xs"
        color="cyan"
        className="bottom-80 left-[2%] !blur-none"
      />
      <GlowDot
        size="md"
        color="cyan"
        className="bottom-32 left-[5%] !blur-none"
      />
      <GlowDot
        size="sm"
        color="cyan"
        className="bottom-48 left-[10%] !blur-none"
      />
      <GlowDot
        size="lg"
        color="cyan"
        className="bottom-64 left-[7%] !blur-none"
      />
      <GlowDot
        size="sm"
        color="cyan"
        className="bottom-80 left-[5%] !blur-none"
      />
      <GlowDot
        size="md"
        color="cyan"
        className="bottom-60 left-[2%] !blur-none"
      />

      <GlowDot
        size="sm"
        color="purple"
        className="top-[405px] right-[10%] !blur-none"
      />
      <GlowDot
        size="sm"
        color="purple"
        className="top-96 right-[2%] !blur-none"
      />
      <GlowDot
        size="sm"
        color="purple"
        className="top-60 right-[5%] !blur-none"
      />
      <GlowDot
        size="md"
        color="purple"
        className="top-64 right-[10%] !blur-none"
      />
      <GlowDot
        size="md"
        color="purple"
        className="top-80 right-[4%] !blur-none"
      />
      <GlowDot
        size="lg"
        color="purple"
        className="top-40 right-[5%] !blur-none"
      />

      {/* 🔵 Primary Gradient (Top Left) */}
      <div className="absolute bottom-10 -left-40 w-[420px] h-[520px] bg-primary opacity-30 blur-3xl rounded-full z-0" />

      {/* 🟣 Secondary Gradient (Top Right) */}
      <div className="absolute top-10 -right-40 w-[420px] h-[520px] bg-gradient-to-r from-secondary to-secondary opacity-30 blur-3xl rounded-full" />

      <Container>
        <Heading align="center" className="!text-gray-100 mb-10">
          How It Works
        </Heading>

        <div className="relative grid grid-cols-2 md:grid-cols-1">
          {/* <div className="absolute left-0 top-0 h-[70%] border-l-8 border-primary"></div> */}

          <div
            className="absolute top-20 bottom-40 -right-3 border-y-8 border-r-8 w-[90%] hidden md:block"
            style={{
              borderImage:
                "linear-gradient(to right, var(--color-primary), #FF6900, var(--color-secondary)) 1",
            }}
          ></div>

          {/* <div className="w-2 bg-gradient-to-b from-secondary to-primary absolute top-20 -right-10 h-[67%] z-0 rounded-full hidden md:block"></div> */}

          <div className="grid grid-cols-1 md:grid-cols-4 gap-20 md:gap-7 relative">
            {/* <div className="h-2 bg-gradient-to-r from-primary to-secondary absolute top-20 left-[100px] w-[95%] z-0 rounded-full hidden md:block"></div> */}

            <Card
              title="Sync with our bot"
              img={assetPath("/images/FT-5.png")}
              des={
                <>
                  Your library syncs through{" "}
                  <TelegramBotLink {...OXPLAYER_BOT} /> only open the bot in
                  Telegram and connect OXPlayer. We never ask for your password
                  or read your private chats.
                </>
              }
            />

            <Card
              title="Send Movie to Bot"
              img={assetPath("/images/FT-7.png")}
              des={
                <>
                  Send a video or movie file to{" "}
                  <TelegramBotLink {...OXPLAYER_BOT} />. The bot processes your
                  upload and adds it to your library with posters and metadata.
                </>
              }
            />

            <Card
              title="Movie Appears in OXPlayer"
              img={assetPath("/images/logo.png")}
              des="Your video is organized with posters and metadata, then added to your library for easy browsing."
            />

            <Card
              title="Watch Anywhere"
              img={assetPath("/images/FT-6.png")}
              des="Enjoy a smooth streaming experience with resume playback, watchlists, and smart media management."
            />
          </div>

          <div className="grid grid-cols-1 md:grid-cols-4 gap-20 md:gap-7 md:mt-10 relative">
            {/* <div className="h-2 bg-gradient-to-r from-secondary to-primary absolute top-[162px] left-[100px] w-[95%] z-0 rounded-full hidden md:block"></div> */}

            {[
              assetPath("/images/H-1.png"),
              assetPath("/images/H-2.png"),
              assetPath("/images/ss-2.png"),
              assetPath("/images/H-3.png"),
            ].map((item, index) => (
              <div
                key={index}
                className="relative w-full h-[230px] md:h-[300px] z-10"
              >
                <Image
                  src={item}
                  alt={`movie-scene-${index + 1}`}
                  fill
                  className="object-contain"
                />
              </div>
            ))}
          </div>
        </div>
      </Container>
    </section>
  );
};

export default HowItWorks;
