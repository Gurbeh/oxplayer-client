// botprobe is a throwaway empirical spike for ONE question:
//
//	Can a Telegram bot-token MTProto session read messages that were delivered to it
//	BEFORE this session connected?
//
// The production code (resolve.go's resolveVideoFileViaBotPush) assumes "no" and therefore makes
// the backend re-forward the video on EVERY playback, tagged with a correlation token. That
// assumption traces back to a comment citing apps/bot2bot-poc, whose code no longer exists — so
// it is currently unverified. If the answer is actually "yes", the whole re-forward + correlation
// token dance can be replaced by "forward once, remember the id, re-read it later".
//
// Run:
//
//	BOT_TOKEN=... TELEGRAM_API_ID=... TELEGRAM_API_HASH=... go run ./cmd/botprobe
//
// Nothing here writes to Telegram — every call is a read.
package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/gotd/td/session"
	"github.com/gotd/td/telegram"
	"github.com/gotd/td/tg"
)

func main() {
	sessionPath := flag.String("session", "botprobe.session", "session file path")
	maxID := flag.Int("max-id", 40, "probe message ids 1..max-id via messages.getMessages")
	searchQ := flag.String("search", "", "optional query for messages.search (e.g. #oxm_dev_6)")
	channelID := flag.Int64("channel-id", 0, "optional base channel id for channels.getMessages")
	channelMsg := flag.Int("channel-msg", 0, "message id within -channel-id")
	flag.Parse()

	token := strings.TrimSpace(os.Getenv("BOT_TOKEN"))
	if token == "" {
		exit("set BOT_TOKEN")
	}
	apiID, err := strconv.Atoi(os.Getenv("TELEGRAM_API_ID"))
	if err != nil {
		exit("invalid/missing TELEGRAM_API_ID: " + err.Error())
	}
	apiHash := strings.TrimSpace(os.Getenv("TELEGRAM_API_HASH"))
	if apiHash == "" {
		exit("set TELEGRAM_API_HASH")
	}

	client := telegram.NewClient(apiID, apiHash, telegram.Options{
		SessionStorage: &session.FileStorage{Path: *sessionPath},
	})

	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Minute)
	defer cancel()

	if err := client.Run(ctx, func(ctx context.Context) error {
		if _, err := client.Auth().Bot(ctx, token); err != nil {
			return fmt.Errorf("bot auth: %w", err)
		}
		api := client.API()

		self, err := client.Self(ctx)
		if err != nil {
			return fmt.Errorf("self: %w", err)
		}
		fmt.Printf("authenticated as @%s (id=%d, bot=%v)\n\n", self.Username, self.ID, self.Bot)

		peers := probeGetMessages(ctx, api, *maxID)
		probeGetHistory(ctx, api, peers)
		if *searchQ != "" {
			probeSearch(ctx, api, peers, *searchQ)
		}
		if *channelID != 0 && *channelMsg != 0 {
			probeChannelGetMessages(ctx, api, *channelID, *channelMsg)
		}
		return nil
	}); err != nil {
		exit(err.Error())
	}
}

// probeGetMessages is THE test: messages.getMessages takes bare message ids with no peer, so it
// needs no bootstrap. In private chats each side has its own id sequence, so these ids are the
// bot's own numbering — exactly the ids a client would have learned from an earlier push.
func probeGetMessages(ctx context.Context, api *tg.Client, maxID int) []tg.InputPeerClass {
	fmt.Println("== TEST 1: messages.getMessages (read arbitrary past messages by id) ==")
	ids := make([]tg.InputMessageClass, 0, maxID)
	for i := 1; i <= maxID; i++ {
		ids = append(ids, &tg.InputMessageID{ID: i})
	}
	res, err := api.MessagesGetMessages(ctx, ids)
	if err != nil {
		fmt.Printf("  RESULT: FAILED — %v\n", err)
		fmt.Print("  => bots cannot read past messages by id; current re-forward design is justified.\n\n")
		return nil
	}
	msgs, seenPeers := describeMessages(res)
	fmt.Printf("  RESULT: OK — %d message(s) returned\n", msgs)
	if msgs > 0 {
		fmt.Println("  => bots CAN read past messages by id; the re-forward-every-play design is unnecessary.")
	} else {
		fmt.Println("  => call allowed but returned nothing (empty chat, or ids outside this bot's range).")
	}
	fmt.Println()
	return seenPeers
}

func probeGetHistory(ctx context.Context, api *tg.Client, peers []tg.InputPeerClass) {
	fmt.Println("== TEST 2: messages.getHistory (enumerate a chat) ==")
	peer := tg.InputPeerClass(&tg.InputPeerEmpty{})
	if len(peers) > 0 {
		peer = peers[0]
	}
	_, err := api.MessagesGetHistory(ctx, &tg.MessagesGetHistoryRequest{Peer: peer, Limit: 10})
	if err != nil {
		fmt.Printf("  RESULT: FAILED — %v\n", err)
		fmt.Print("  => expected; this is the restriction the code comments actually describe.\n\n")
		return
	}
	fmt.Print("  RESULT: OK — history enumeration is allowed for this bot.\n\n")
}

func probeSearch(ctx context.Context, api *tg.Client, peers []tg.InputPeerClass, q string) {
	fmt.Printf("== TEST 3: messages.search for %q (locator-tag lookup) ==\n", q)
	peer := tg.InputPeerClass(&tg.InputPeerEmpty{})
	if len(peers) > 0 {
		peer = peers[0]
	}
	res, err := api.MessagesSearch(ctx, &tg.MessagesSearchRequest{
		Peer:   peer,
		Q:      q,
		Filter: &tg.InputMessagesFilterEmpty{},
		Limit:  20,
	})
	if err != nil {
		fmt.Printf("  RESULT: FAILED — %v\n", err)
		fmt.Print("  => the #oxm_… locator-tag search idea will not work from the bot side.\n\n")
		return
	}
	n, _ := describeMessages(res)
	fmt.Printf("  RESULT: OK — %d match(es); locator-tag lookup is viable.\n\n", n)
}

func probeChannelGetMessages(ctx context.Context, api *tg.Client, channelID int64, msgID int) {
	fmt.Printf("== TEST 4: channels.getMessages on base channel %d ==\n", channelID)
	res, err := api.ChannelsGetMessages(ctx, &tg.ChannelsGetMessagesRequest{
		Channel: &tg.InputChannel{ChannelID: channelID},
		ID:      []tg.InputMessageClass{&tg.InputMessageID{ID: msgID}},
	})
	if err != nil {
		fmt.Printf("  RESULT: FAILED — %v\n", err)
		fmt.Print("  => user's bot cannot read the base channel directly (expected: not a member).\n\n")
		return
	}
	n, _ := describeMessages(res)
	fmt.Printf("  RESULT: OK — %d message(s); bot can read the base channel directly.\n\n", n)
}

// describeMessages prints one line per message and collects distinct peers for later probes.
func describeMessages(res tg.MessagesMessagesClass) (int, []tg.InputPeerClass) {
	var msgs []tg.MessageClass
	switch v := res.(type) {
	case *tg.MessagesMessages:
		msgs = v.Messages
	case *tg.MessagesMessagesSlice:
		msgs = v.Messages
	case *tg.MessagesChannelMessages:
		msgs = v.Messages
	default:
		fmt.Printf("  (unexpected response type %T)\n", res)
		return 0, nil
	}

	var peers []tg.InputPeerClass
	seen := map[int64]bool{}
	count := 0
	for _, mc := range msgs {
		m, ok := mc.(*tg.Message)
		if !ok {
			continue
		}
		count++
		desc := "no media"
		if md, ok := m.Media.(*tg.MessageMediaDocument); ok {
			if doc, ok := md.Document.(*tg.Document); ok {
				desc = fmt.Sprintf("document id=%d size=%d mime=%s fileRef=%dB",
					doc.ID, doc.Size, doc.MimeType, len(doc.FileReference))
			}
		}
		caption := m.Message
		if len(caption) > 40 {
			caption = caption[:40] + "…"
		}
		fmt.Printf("    id=%-6d date=%s %s caption=%q\n",
			m.ID, time.Unix(int64(m.Date), 0).Format("01-02 15:04"), desc, caption)

		if pu, ok := m.PeerID.(*tg.PeerUser); ok && !seen[pu.UserID] {
			seen[pu.UserID] = true
			peers = append(peers, &tg.InputPeerUser{UserID: pu.UserID})
		}
	}
	return count, peers
}

func exit(msg string) {
	fmt.Fprintln(os.Stderr, "botprobe: "+msg)
	os.Exit(1)
}
