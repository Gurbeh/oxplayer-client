type TelegramBotLinkProps = {
  username: string;
  url: string;
  className?: string;
};

export default function TelegramBotLink({ username, url, className = "text-primary hover:underline font-medium" }: TelegramBotLinkProps) {
  return (
    <a href={url} target="_blank" rel="noopener noreferrer" className={className}>
      @{username}
    </a>
  );
}
