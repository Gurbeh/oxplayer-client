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
          Sync only through{" "}
          <TelegramBotLink
            {...OXPLAYER_BOT}
            className="text-primary hover:underline font-medium"
          />
          .<br />
          We never ask for your password or read your private chats.
          <br />
          Only media you send to the bot is added to your library.
        </Paragraph>
      </Container>
    </section>
  );
};

export default TelegramPrivacyNote;
