import Container from "@/components/ui/Container";
import Heading from "@/components/ui/Heading";
import TelegramBotLink from "@/components/ui/TelegramBotLink";
import { OXPLAYER_BOT, SUPPORT_BOT, SUPPORT_EMAIL } from "@/config/bots";
import type { ReactNode } from "react";

const faqs: { q: string; a: ReactNode }[] = [
  {
    q: "What is OXPlayer?",
    a: "OXPlayer is a personal media library app with a Netflix-style interface. You sync videos by sending or forwarding them to our Telegram bot and stream content you added yourself. We do not host or sell movies.",
  },
  {
    q: "How do I connect Telegram?",
    a: (
      <>
        Open OXPlayer and tap <b>Sign in with Telegram</b>. Approve the device request in{" "}
        <TelegramBotLink {...OXPLAYER_BOT} /> — the app signs you in automatically. OXPlayer uses its own sign-in —
        not Telegram Login — and we never collect your Telegram account data, password, or private chats. We only
        process media you send or forward to our bot.
      </>
    ),
  },
  {
    q: "How do I add movies and videos?",
    a: (
      <>
        Send or forward a video file to <TelegramBotLink {...OXPLAYER_BOT} />. After the bot finishes processing,
        the title appears in your OXPlayer library with posters and metadata.
      </>
    ),
  },
  {
    q: "Does OXPlayer provide movies or TV shows?",
    a: "No. OXPlayer does not host, sell, or distribute content. It only organizes and plays videos that you personally send or forward to the bot.",
  },
  {
    q: "Which platforms are available?",
    a: "OXPlayer is available on Android, Android TV, iOS, macOS, Windows, Linux, and Web. Use the download links on this page to get the latest release for your device.",
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
        Your library belongs to your account. Only media you send or forward to{" "}
        <TelegramBotLink {...OXPLAYER_BOT} /> is indexed — not your other Telegram messages or files.
      </>
    ),
  },
  {
    q: "How do I get help?",
    a: (
      <>
        Message our support bot <TelegramBotLink {...SUPPORT_BOT} /> on Telegram or email us at{" "}
        <a href={`mailto:${SUPPORT_EMAIL}`} className="text-primary hover:underline">
          {SUPPORT_EMAIL}
        </a>
        .
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
              <div
                key={i}
                tabIndex={0}
                className="collapse collapse-arrow border  bg-slate-900 border-slate-700"
              >
                <div className="collapse-title text-lg font-medium">
                  {item.q}
                </div>

                <div className="collapse-content text-base-content/80 leading-relaxed">
                  {item.a}
                </div>
              </div>
            ))}
          </div>
        </div>
      </Container>
    </section>
  );
};

export default FAQ;
