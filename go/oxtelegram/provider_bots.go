package oxtelegram

import (
	"context"
	"crypto/rand"
	"encoding/binary"
	"fmt"
	"log"
	"math"
	"strings"

	"github.com/gotd/td/tg"
)

// archiveFolderID is Telegram's built-in Archive folder. 0 is the main chat list.
const archiveFolderID = 1

// muteForever is the sentinel account.updateNotifySettings uses for "muted indefinitely" —
// Telegram treats a mute_until far in the future as permanent.
const muteForever = math.MaxInt32

// ProviderBot is one delivery sender, as published by the backend's GET /telegram/provider-bots.
// The username is needed only for first contact; everything afterwards addresses the bot by id.
type ProviderBot struct {
	ID       int64  `json:"id"`
	Username string `json:"username"`
}

// EnsureProviderBotsReady makes every delivery sender ready to receive media on this account,
// without the user ever seeing it happen: started (so the bot is allowed to message them at all),
// muted, and filed in Archive.
//
// This is what keeps warmup copies out of the user's inbox. It runs on every app enter, not just
// after login, because a sender can be added to the backend's list at any time and a user who
// never re-logs in would otherwise never start it.
//
// Session accounts only. A bot-token login is not a user account: it has no dialog list to archive
// and no notification settings, and the B2B DM was already opened by /connectbot. Calling this
// there is a no-op rather than an error, so callers do not have to branch.
//
// Errors are per-bot and non-fatal: one unreachable sender must not stop the others from being
// prepared, because the backend can round-robin onto any of them.
func (c *Client) EnsureProviderBotsReady(ctx context.Context, bots []ProviderBot) error {
	if len(bots) == 0 {
		return nil
	}
	if c.Auth != nil && c.Auth.IsBotMode() {
		return nil
	}
	api := c.API()
	if api == nil {
		return fmt.Errorf("client not configured")
	}

	selfID := c.selfUserID(ctx)
	log.Printf("oxtelegram: preparing %d provider bot(s) for telegram user %d", len(bots), selfID)

	var failures []string
	for _, bot := range bots {
		if err := c.ensureProviderBotReady(ctx, api, bot, selfID); err != nil {
			log.Printf("oxtelegram: provider bot @%s not prepared: %v", bot.Username, err)
			failures = append(failures, fmt.Sprintf("@%s: %v", bot.Username, err))
		}
	}
	if len(failures) == len(bots) {
		return fmt.Errorf("no provider bot could be prepared: %s", strings.Join(failures, "; "))
	}
	return nil
}

func (c *Client) ensureProviderBotReady(ctx context.Context, api *tg.Client, bot ProviderBot, selfID int64) error {
	if strings.TrimSpace(bot.Username) == "" {
		return fmt.Errorf("no username")
	}
	// contacts.resolveUsername is the only way to obtain the access_hash an InputPeerUser needs
	// before any dialog exists. Once the dialog does exist the backend addresses this bot by id
	// (decision 11), so this call happens on app enter and nowhere near the playback path.
	resolved, err := api.ContactsResolveUsername(ctx, &tg.ContactsResolveUsernameRequest{
		Username: strings.TrimPrefix(bot.Username, "@"),
	})
	if err != nil {
		return fmt.Errorf("ContactsResolveUsername: %w", err)
	}
	var user *tg.User
	for _, u := range resolved.Users {
		if candidate, ok := u.(*tg.User); ok {
			user = candidate
			break
		}
	}
	if user == nil {
		return fmt.Errorf("username did not resolve to a user")
	}
	if bot.ID > 0 && user.ID != bot.ID {
		// The backend's id is authoritative (it comes from the token itself). A mismatch means the
		// username now belongs to somebody else — deliver nothing to it.
		return fmt.Errorf("username resolves to %d, backend expects %d", user.ID, bot.ID)
	}

	inputPeer := &tg.InputPeerUser{UserID: user.ID, AccessHash: user.AccessHash}
	c.rememberProviderPeer(inputPeer)

	hasMessages, err := c.dialogHasMessages(ctx, api, inputPeer)
	if err != nil {
		// Not fatal on its own — fall through and try to start. Worst case is a duplicate /start.
		log.Printf("oxtelegram: dialog check for @%s failed: %v", bot.Username, err)
	}
	// resolveUsername can leave an empty peer dialog (TopMessage=0). Treating that as "already
	// started" skipped messages.startBot, Flutter logged ok, and Bot API copy still returned
	// chat not found. Always startBot unless a real message already exists in the DM.
	if !hasMessages {
		if _, err := api.MessagesStartBot(ctx, &tg.MessagesStartBotRequest{
			Bot:        &tg.InputUser{UserID: user.ID, AccessHash: user.AccessHash},
			Peer:       inputPeer,
			RandomID:   cryptoRandomID(),
			StartParam: "oxplayer",
		}); err != nil {
			return fmt.Errorf("MessagesStartBot: %w", err)
		}
		log.Printf("oxtelegram: startBot @%s ok self=%d bot=%d", bot.Username, selfID, user.ID)
	} else {
		log.Printf("oxtelegram: skip startBot @%s (dialog has messages) self=%d bot=%d", bot.Username, selfID, user.ID)
	}

	// Mute and archive are idempotent and cheap, so they run every launch rather than only on the
	// first: a user who un-archived the chat by hand, or a Telegram-side reset, silently repairs.
	if _, err := api.AccountUpdateNotifySettings(ctx, &tg.AccountUpdateNotifySettingsRequest{
		Peer: &tg.InputNotifyPeer{Peer: inputPeer},
		Settings: tg.InputPeerNotifySettings{
			ShowPreviews: false,
			Silent:       true,
			MuteUntil:    muteForever,
		},
	}); err != nil {
		return fmt.Errorf("AccountUpdateNotifySettings: %w", err)
	}

	if _, err := api.FoldersEditPeerFolders(ctx, []tg.InputFolderPeer{{
		Peer:     inputPeer,
		FolderID: archiveFolderID,
	}}); err != nil {
		return fmt.Errorf("FoldersEditPeerFolders: %w", err)
	}
	return nil
}

// dialogHasMessages reports whether this account already has a real conversation with peer.
// getPeerDialogs can return an empty dialog after resolveUsername alone; Bot API still sees
// chat not found until messages.startBot posts /start. TopMessage>0 is the proof.
func (c *Client) dialogHasMessages(ctx context.Context, api *tg.Client, peer *tg.InputPeerUser) (bool, error) {
	res, err := api.MessagesGetPeerDialogs(ctx, []tg.InputDialogPeerClass{
		&tg.InputDialogPeer{Peer: peer},
	})
	if err != nil {
		return false, err
	}
	return peerDialogHasMessages(res), nil
}

func cryptoRandomID() int64 {
	var b [8]byte
	if _, err := rand.Read(b[:]); err != nil {
		return 1
	}
	id := int64(binary.LittleEndian.Uint64(b[:]))
	if id == 0 {
		return 1
	}
	return id
}

func (c *Client) rememberProviderPeer(peer *tg.InputPeerUser) {
	if peer == nil || peer.UserID == 0 {
		return
	}
	c.providerPeersMu.Lock()
	defer c.providerPeersMu.Unlock()
	if c.providerPeers == nil {
		c.providerPeers = make(map[int64]*tg.InputPeerUser)
	}
	c.providerPeers[peer.UserID] = peer
}

func (c *Client) providerPeerSnapshot() []*tg.InputPeerUser {
	c.providerPeersMu.Lock()
	defer c.providerPeersMu.Unlock()
	out := make([]*tg.InputPeerUser, 0, len(c.providerPeers))
	for _, p := range c.providerPeers {
		out = append(out, p)
	}
	return out
}

func peerDialogHasMessages(res *tg.MessagesPeerDialogs) bool {
	if res == nil {
		return false
	}
	for _, d := range res.Dialogs {
		dialog, ok := d.(*tg.Dialog)
		if !ok {
			continue
		}
		if dialog.TopMessage > 0 {
			return true
		}
	}
	return false
}
