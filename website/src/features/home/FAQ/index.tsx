import type { ReactNode } from "react";
import Container from "@/components/ui/Container";
import Heading from "@/components/ui/Heading";
import TelegramBotLink from "@/components/ui/TelegramBotLink";
import { OXPLAYER_BOT, SUPPORT_BOT } from "@/config/bots";

const faqs: { q: string; a: ReactNode }[] = [
  {
    q: "What is OXPlayer?",
    a: "OXPlayer is a personal media library app with a Netflix-style interface. You sync through our Telegram bot and stream videos you upload yourself — we do not host or sell movies.",
  },
  {
    q: "How do I connect Telegram?",
    a: (
      <>
        Sync only with <TelegramBotLink {...OXPLAYER_BOT} />. Open the bot in Telegram, sign in to the OXPlayer app with Telegram&apos;s
        official authorization, and your library stays linked to your account. We never ask for your Telegram password or access your
        private chats.
      </>
    ),
  },
  {
    q: "How do I add movies and videos?",
    a: (
      <>
        Send a video file to <TelegramBotLink {...OXPLAYER_BOT} />. After the bot finishes processing, the title appears in your OXPlayer
        library with posters and metadata.
      </>
    ),
  },
  {
    q: "Does OXPlayer provide movies or TV shows?",
    a: "No. OXPlayer does not host, sell, or distribute content. It only organizes and plays videos that you personally send to the bot.",
  },
  {
    q: "Which platforms are available?",
    a: "Android is available now. iOS and Web are coming soon. Windows and Linux are on the roadmap.",
  },
  {
    q: "Can I continue watching from where I left off?",
    a: "Yes. Watch progress is saved to your account so you can resume where you stopped.",
  },
  {
    q: "Are favorites and watchlists synced?",
    a: "Yes. Favorites, watchlists, history, and playback progress stay tied to your OXPlayer account when you sign in again.",
  },
  {
    q: "Is my content private?",
    a: (
      <>
        Your library belongs to your account. Only media you send to <TelegramBotLink {...OXPLAYER_BOT} /> is indexed — not your other
        Telegram messages or files.
      </>
    ),
  },
  {
    q: "How do I get help?",
    a: (
      <>
        Message our support bot <TelegramBotLink {...SUPPORT_BOT} /> on Telegram for questions or issues.
      </>
    ),
  },
];

const FAQ = () => {
  return (
    <section className="pt-24 pb-20">
      <Container>
        <div>
          <Heading level="h2" align="center" className="mb-7 !text-gray-100">
            FAQ
          </Heading>

          <div className="max-w-3xl mx-auto space-y-4">
            {faqs.map((item, i) => (
              <div key={i} tabIndex={0} className="collapse collapse-arrow border  bg-slate-900 border-slate-700">
                <div className="collapse-title text-lg font-medium">{item.q}</div>

                <div className="collapse-content text-base-content/80 leading-relaxed">{item.a}</div>
              </div>
            ))}
          </div>
        </div>
      </Container>
    </section>
  );
};

export default FAQ;
