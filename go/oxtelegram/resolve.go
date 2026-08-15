package oxtelegram

import (
	"context"
	"fmt"
	"log"
	"strings"
	"time"

	"github.com/gotd/td/tg"
)

// deliveryWaitTimeout bounds how long a cold resolve waits for the server's copy to arrive as a
// live push. Only the cold path pays this: once the backend knows which message id the file
// landed on, resolves read it directly and never wait.
//
// This used to be 20s, sized back when a miss here was unrecoverable (bot-mode readers can't
// scan DM history — see findLocatorInRecentMessages — so a lost push meant every future play of
// that file paid the full wait forever). Now that the client force-repairs on this exact timeout
// (see oxplayerIsTelegramDeliveryWaitTimeoutError in oxplayer_tdlib_playback_resolver.dart), that
// 20s is no longer a safety margin — it is dead time paid before recovery even starts. Measured
// on a real stuck delivery: the timeout fired at 20.02s, and the FRESH copy triggered by
// force-repair had its push land 0.66s later. 8s keeps well over an order of magnitude of margin
// above that observed round trip (plus the 1.5s per-sender copy throttle, see
// tgapi.DefaultCopyInterval) while cutting the worst case from ~22s to ~10s.
const deliveryWaitTimeout = 8 * time.Second

// VideoFileRef is the gomobile-safe (all primitive fields — see plan's "100% flat" export-surface
// requirement) description of a resolved video/document file. DocumentID/AccessHash are Telegram
// 64-bit values carried as int64: treat the bit pattern as opaque and round-trip it unchanged,
// never re-interpret it as a real (possibly negative) number.
type VideoFileRef struct {
	DocumentID    int64
	AccessHash    int64
	FileReference []byte
	MimeType      string
	Size          int64
	DCID          int32
	// ProviderBotID is the delivery bot whose DM this document was found in. Echoed back to the
	// backend with the message id so the next play can be answered without any copy.
	ProviderBotID int64
}

// ResolveVideoFile returns the video/document file reference for a subsequent Download call.
//
// One path for every login mode. The video never lives in a public channel: the backend copies it
// out of a base channel straight into a DM this session controls — the user's own account for a
// phone/QR session, the user's personal bot for a bot-token session (apps/api's
// resolveTelegramDelivery) — and it is read back from there.
//
//   - messageID > 0 — the backend remembered where a previous copy landed. providerBotID names the
//     DM it landed in. Read it back with messages.getMessages, which works for bot sessions too:
//     only enumeration (messages.getHistory / messages.search) returns BOT_METHOD_INVALID, verified
//     against a real bot token in go/oxtelegram/cmd/botprobe. Re-fetching by id is also how an
//     expired file_reference is refreshed, so this doubles as the refresh path.
//   - messageID == 0 — nothing remembered; a fresh copy is in flight. providerBotID is 0 too,
//     because the server round-robins across senders and may fail over mid-request; this waits for
//     the live push carrying locator and learns the real sender from the update itself.
//
// locator is the copied message's caption (OXM_PREFIX_recordNo — unique per stored file, no '#').
// It is required: it selects which of several concurrent pushes answers THIS call, and on the
// remembered path it verifies the id still holds the file we expect.
func (c *Client) ResolveVideoFile(ctx context.Context, providerBotID, messageID int64, locator string) (*VideoFileRef, error) {
	if locator == "" {
		return nil, fmt.Errorf("delivery resolve requires a locator")
	}
	if messageID > 0 {
		return c.resolveVideoFileByDMMessageID(ctx, providerBotID, messageID, locator)
	}
	return c.resolveVideoFileByPush(ctx, locator)
}

// resolveVideoFileByDMMessageID reads a message this session already received, by id.
//
// messages.getMessages takes bare ids with no peer, which is exactly right here: the message is in
// a private chat, where ids come from this side's own numbering.
//
// Both a caption mismatch and a sender mismatch are hard errors rather than a silent play. Either
// means the remembered id no longer points at the file we were promised (the DM was cleared and
// re-filled, say), and playing whatever is there would put the wrong video on screen. The Dart
// layer turns this into a force-refresh — drop the server's remembered id and re-copy — see
// oxplayerIsTelegramDmStaleError.
func (c *Client) resolveVideoFileByDMMessageID(ctx context.Context, providerBotID, messageID int64, locator string) (*VideoFileRef, error) {
	api := c.API()
	if api == nil {
		return nil, fmt.Errorf("client not configured")
	}
	res, err := api.MessagesGetMessages(ctx, []tg.InputMessageClass{&tg.InputMessageID{ID: int(messageID)}})
	if err != nil {
		return nil, fmt.Errorf("MessagesGetMessages(%d): %w", messageID, err)
	}
	var msgs []tg.MessageClass
	switch v := res.(type) {
	case *tg.MessagesMessages:
		msgs = v.Messages
	case *tg.MessagesMessagesSlice:
		msgs = v.Messages
	case *tg.MessagesChannelMessages:
		msgs = v.Messages
	default:
		return nil, fmt.Errorf("unexpected messages response type %T", res)
	}
	if len(msgs) == 0 {
		if c.Auth != nil && c.Auth.IsBotMode() {
			return nil, fmt.Errorf("OX_WRONG_ACCOUNT: native MTProto is a bot; cannot read user-session DM message %d — log in with phone/QR", messageID)
		}
		if ref := c.findLocatorInRecentMessages(ctx, locator); ref != nil {
			return ref, nil
		}
		return nil, fmt.Errorf("%s: dm message %d not found", dmStaleErrorMarker, messageID)
	}
	doc, gotLocator, _, senderID := documentFromMessage(msgs[0])
	if doc == nil {
		if ref := c.findLocatorInRecentMessages(ctx, locator); ref != nil {
			return ref, nil
		}
		return nil, fmt.Errorf("%s: dm message %d has no document", dmStaleErrorMarker, messageID)
	}
	if gotLocator != locator && !strings.Contains(gotLocator, locator) {
		if ref := c.findLocatorInRecentMessages(ctx, locator); ref != nil {
			return ref, nil
		}
		return nil, fmt.Errorf("%s: dm message %d holds %q, expected %q", dmStaleErrorMarker, messageID, gotLocator, locator)
	}
	if providerBotID > 0 && senderID > 0 && senderID != providerBotID {
		return nil, fmt.Errorf("%s: dm message %d came from bot %d, expected %d", dmStaleErrorMarker, messageID, senderID, providerBotID)
	}
	if providerBotID <= 0 {
		providerBotID = senderID
	}

	c.rememberDeliveryRef(locator, messageID, providerBotID)
	return videoFileRefFromDocument(doc, providerBotID), nil
}

// dmStaleErrorMarker tags the errors that mean "the remembered message id is no longer usable" —
// as opposed to a network/config failure. The Dart side matches on it to decide whether to force a
// re-copy and retry, instead of showing the user an error. Kept as a string marker because this
// error crosses gomobile/cgo boundaries, where a typed error would be flattened to its message
// anyway.
const dmStaleErrorMarker = "OX_DM_STALE"

// resolveVideoFileByPush waits for the backend's copy carrying locator to arrive (see
// Client.pushWaiters/pushArrived's doc comment — the dispatcher is live from Configure onward, and
// registerPushWaiter checks for an already-arrived push before falling back to actually waiting,
// since there is no guaranteed ordering between the PlaybackInfo HTTP response and this MTProto
// push arriving; ArmDeliveryWaiter closes that window entirely when the caller can arm first).
func (c *Client) resolveVideoFileByPush(ctx context.Context, locator string) (*VideoFileRef, error) {
	if ref := c.findLocatorInRecentMessages(ctx, locator); ref != nil {
		return ref, nil
	}
	ch := c.registerPushWaiter(locator)
	defer c.unregisterPushWaiter(locator)

	timeout := time.NewTimer(deliveryWaitTimeout)
	defer timeout.Stop()
	select {
	case msg := <-ch:
		c.rememberDeliveryRef(locator, msg.messageID, msg.providerBotID)
		return videoFileRefFromDocument(msg.doc, msg.providerBotID), nil
	case <-ctx.Done():
		return nil, ctx.Err()
	case <-timeout.C:
		// Live push can lose the race (ArmDeliveryWaiter dropping an early copy, pts gap).
		// The file is already in the DM — search instead of forcing another copyMessage.
		if ref := c.findLocatorInRecentMessages(ctx, locator); ref != nil {
			return ref, nil
		}
		return nil, fmt.Errorf("timed out waiting for %s to be delivered to this session (%s) — check the delivery bot is started and reachable", locator, deliveryWaitTimeout)
	}
}

func locatorCaptionMatches(got, want string) bool {
	got = strings.TrimSpace(got)
	want = strings.TrimSpace(want)
	return got == want || strings.Contains(got, want)
}

func messagesFromRPC(res tg.MessagesMessagesClass) []tg.MessageClass {
	switch v := res.(type) {
	case *tg.MessagesMessages:
		return v.Messages
	case *tg.MessagesMessagesSlice:
		return v.Messages
	case *tg.MessagesChannelMessages:
		return v.Messages
	default:
		return nil
	}
}

// findLocatorInRecentMessages looks up a copy that already landed in this session's DMs.
// Used when the live-push waiter misses (or a remembered message id is stale) so we do not
// ask the server to copyMessage the same file again.
func (c *Client) findLocatorInRecentMessages(ctx context.Context, locator string) *VideoFileRef {
	if c.Auth != nil && c.Auth.IsBotMode() {
		log.Printf("oxtelegram: skip DM history scan for %s (this MTProto session is a bot; BOT_METHOD_INVALID)", locator)
		return nil
	}
	api := c.API()
	if api == nil || locator == "" {
		return nil
	}
	// Archived DMs (decision 7) are invisible to SearchGlobal. Walk each prepared
	// provider-bot peer with getHistory — session users can enumerate; this is the
	// path that finds a copy that already landed when the live push was missed.
	for _, peer := range c.providerPeerSnapshot() {
		if ref := c.findLocatorInPeerHistory(ctx, api, peer, locator); ref != nil {
			return ref
		}
	}
	res, err := api.MessagesSearchGlobal(ctx, &tg.MessagesSearchGlobalRequest{
		Q:          locator,
		Filter:     &tg.InputMessagesFilterDocument{},
		OffsetPeer: &tg.InputPeerEmpty{},
		Limit:      20,
	})
	if err != nil {
		log.Printf("oxtelegram: SearchGlobal %s: %v", locator, err)
		return nil
	}
	if ref := videoRefMatchingLocator(c, messagesFromRPC(res), locator); ref != nil {
		return ref
	}
	log.Printf("oxtelegram: no DM history match for %s (peers=%d)", locator, len(c.providerPeerSnapshot()))
	return nil
}

func (c *Client) findLocatorInPeerHistory(ctx context.Context, api *tg.Client, peer *tg.InputPeerUser, locator string) *VideoFileRef {
	res, err := api.MessagesGetHistory(ctx, &tg.MessagesGetHistoryRequest{
		Peer:  peer,
		Limit: 50,
	})
	if err != nil {
		log.Printf("oxtelegram: GetHistory bot=%d locator=%s: %v", peer.UserID, locator, err)
		return nil
	}
	if ref := videoRefMatchingLocator(c, messagesFromRPC(res), locator); ref != nil {
		log.Printf("oxtelegram: found %s in bot %d history", locator, peer.UserID)
		return ref
	}
	return nil
}

func videoRefMatchingLocator(c *Client, msgs []tg.MessageClass, locator string) *VideoFileRef {
	for _, m := range msgs {
		doc, got, mid, sender := documentFromMessage(m)
		if doc == nil || mid <= 0 || !locatorCaptionMatches(got, locator) {
			continue
		}
		c.rememberDeliveryRef(locator, mid, sender)
		return videoFileRefFromDocument(doc, sender)
	}
	return nil
}

func videoFileRefFromDocument(doc *tg.Document, providerBotID int64) *VideoFileRef {
	return &VideoFileRef{
		DocumentID:    doc.ID,
		AccessHash:    doc.AccessHash,
		FileReference: doc.FileReference,
		MimeType:      doc.MimeType,
		Size:          doc.Size,
		DCID:          int32(doc.DCID),
		ProviderBotID: providerBotID,
	}
}

// documentFromMessage extracts a *tg.Document, its locator (the message's caption — see apps/api's
// resolveTelegramDelivery, which sets it to exactly this), the message's own id, and the id of the
// bot that sent it.
//
// The message id is the RECEIVER's, which is the only one that can be re-read later and the only
// one worth reporting back. The sender id is read from PeerID rather than FromID: in a private
// chat FromID is normally unset, and the dialog peer on an incoming message IS the other party —
// here, the delivery bot. FromID is used as a fallback for the shapes where it is populated.
func documentFromMessage(m tg.MessageClass) (doc *tg.Document, locator string, messageID, senderID int64) {
	msg, ok := m.(*tg.Message)
	if !ok || msg.Media == nil {
		return nil, "", 0, 0
	}
	mediaDoc, ok := msg.Media.(*tg.MessageMediaDocument)
	if !ok || mediaDoc.Document == nil {
		return nil, "", 0, 0
	}
	document, ok := mediaDoc.Document.(*tg.Document)
	if !ok {
		return nil, "", 0, 0
	}
	return document, msg.Message, int64(msg.ID), incomingSenderID(msg)
}

// incomingSenderID returns the user id on the other side of a private chat message, or 0 for any
// message shape this does not apply to (outgoing, group, channel).
func incomingSenderID(msg *tg.Message) int64 {
	if msg.Out {
		return 0
	}
	if peer, ok := msg.PeerID.(*tg.PeerUser); ok && peer.UserID != 0 {
		return peer.UserID
	}
	if from, ok := msg.FromID.(*tg.PeerUser); ok {
		return from.UserID
	}
	return 0
}
