package oxtelegram

import (
	"context"
	"fmt"

	"github.com/gotd/td/tg"
)

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
}

// ResolveVideoFile resolves a public channel by @username and fetches messageID within it,
// returning the video/document file reference for a subsequent Download call.
//
// messageID is the raw server-side id — the same number in a t.me/{username}/{id} link. Unlike
// TDLib (which required messageId shl 20 to become its own internal id scheme), gotd/td's raw
// tg.InputMessageID takes this value directly. Do not reintroduce a shift here.
//
// This is a two-step resolve (username -> channel/access-hash -> message), unlike TDLib's
// one-call SearchPublicChat — see plan's noted resolve-speed regression risk.
func (c *Client) ResolveVideoFile(ctx context.Context, channelUsername string, messageID int64) (*VideoFileRef, error) {
	api := c.API()
	if api == nil {
		return nil, fmt.Errorf("client not configured")
	}

	resolved, err := api.ContactsResolveUsername(ctx, &tg.ContactsResolveUsernameRequest{Username: channelUsername})
	if err != nil {
		return nil, fmt.Errorf("ContactsResolveUsername: %w", err)
	}
	if len(resolved.Chats) == 0 {
		return nil, fmt.Errorf("no chat resolved for %q", channelUsername)
	}
	ch, ok := resolved.Chats[0].(*tg.Channel)
	if !ok {
		return nil, fmt.Errorf("resolved chat is not a channel: %T", resolved.Chats[0])
	}

	// Deliberately does not join/subscribe the account to the channel — ContactsResolveUsername
	// and ChannelsGetMessages are read-only lookups. See plan's no-join-channel regression check.
	msgsClass, err := api.ChannelsGetMessages(ctx, &tg.ChannelsGetMessagesRequest{
		Channel: &tg.InputChannel{ChannelID: ch.ID, AccessHash: ch.AccessHash},
		ID:      []tg.InputMessageClass{&tg.InputMessageID{ID: int(messageID)}},
	})
	if err != nil {
		return nil, fmt.Errorf("ChannelsGetMessages: %w", err)
	}
	messages, ok := msgsClass.(*tg.MessagesChannelMessages)
	if !ok {
		return nil, fmt.Errorf("unexpected messages response type %T", msgsClass)
	}
	if len(messages.Messages) == 0 {
		return nil, fmt.Errorf("message %d not found in %q", messageID, channelUsername)
	}
	msg, ok := messages.Messages[0].(*tg.Message)
	if !ok {
		return nil, fmt.Errorf("message %d is not a regular message: %T", messageID, messages.Messages[0])
	}
	mediaDoc, ok := msg.Media.(*tg.MessageMediaDocument)
	if !ok {
		return nil, fmt.Errorf("message %d has no document media: %T", messageID, msg.Media)
	}
	doc, ok := mediaDoc.Document.(*tg.Document)
	if !ok {
		return nil, fmt.Errorf("message %d document is empty/unavailable: %T", messageID, mediaDoc.Document)
	}

	return &VideoFileRef{
		DocumentID:    doc.ID,
		AccessHash:    doc.AccessHash,
		FileReference: doc.FileReference,
		MimeType:      doc.MimeType,
		Size:          doc.Size,
		DCID:          int32(doc.DCID),
	}, nil
}
