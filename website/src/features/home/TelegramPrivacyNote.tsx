import Container from "@/components/ui/Container";
import Paragraph from "@/components/ui/Paragraph";
import TelegramBotLink from "@/components/ui/TelegramBotLink";
import { OXPLAYER_BOT } from "@/config/bots";

const TelegramPrivacyNote = () => {
  return (
    <section className="relative z-20 pt-10 pb-4 md:pt-24 md:pb-6">
      <Container>
        <Paragraph
          align="center"
          size="sm"
          className="text-gray-500 max-w-2xl mx-auto"
        >
          <span className="text-primary font-medium">
            Your Telegram stays yours.
          </span>{" "}
          Send or forward videos to{" "}
          <TelegramBotLink
            {...OXPLAYER_BOT}
            className="text-primary hover:underline font-medium"
          />
          .<br />
          Sign in to OXPlayer with a login code from the bot — no Telegram login required.
          <br />
          We only process media you send to our bot; we cannot access your account or private chats.
        </Paragraph>
      </Container>
    </section>
  );
};

export default TelegramPrivacyNote;
