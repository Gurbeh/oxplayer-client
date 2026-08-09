// Package spike is throwaway code for validating that `gomobile bind` can produce a working
// Android artifact from a package that internally uses github.com/gotd/td, before any real
// implementation work begins. See
// C:\Users\Aryan\.claude\plans\prancy-rolling-kernighan.md Phase 0.
//
// Deliberately crude: global mutable state instead of a Client type, no proper error wrapping.
// The only goal is proving the gomobile export surface builds and runs against live Telegram
// servers, not API design (that happens for real in Phase 1's go/oxtelegram package).
package spike

import (
	"context"
	"fmt"
	"sync"
	"time"

	"github.com/gotd/td/session"
	"github.com/gotd/td/telegram"
	"github.com/gotd/td/telegram/auth"
	"github.com/gotd/td/tg"
)

var (
	mu           sync.Mutex
	client       *telegram.Client
	api          *tg.Client
	lastCodeHash string
	lastPhone    string

	resolvedMu       sync.Mutex
	resolvedLocation *tg.InputDocumentFileLocation
)

// Ping is a trivial no-dependency export used to confirm the JNI bridge itself works under
// Android's process model before layering on any gotd/td-specific behavior.
func Ping() string {
	return "pong"
}

func ensureClient(apiID int, apiHash, sessionPath string) error {
	mu.Lock()
	defer mu.Unlock()
	if client != nil {
		return nil
	}

	c := telegram.NewClient(apiID, apiHash, telegram.Options{
		SessionStorage: &session.FileStorage{Path: sessionPath},
	})

	ready := make(chan struct{})
	errCh := make(chan error, 1)
	go func() {
		err := c.Run(context.Background(), func(ctx context.Context) error {
			api = c.API()
			close(ready)
			<-ctx.Done()
			return nil
		})
		if err != nil {
			select {
			case errCh <- err:
			default:
			}
		}
	}()

	select {
	case <-ready:
		client = c
		return nil
	case err := <-errCh:
		return fmt.Errorf("client.Run failed before ready: %w", err)
	case <-time.After(30 * time.Second):
		return fmt.Errorf("client did not become ready within 30s")
	}
}

// SendCode requests an SMS/app login code for phone, returning the phone_code_hash needed by
// SignIn. sessionPath is a plain on-device file path (encryption is Phase 2's job, not this
// spike's) — e.g. the app's cache dir on Android.
func SendCode(apiID int, apiHash, phone, sessionPath string) (string, error) {
	if err := ensureClient(apiID, apiHash, sessionPath); err != nil {
		return "", err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	sentCode, err := client.Auth().SendCode(ctx, phone, auth.SendCodeOptions{})
	if err != nil {
		return "", fmt.Errorf("SendCode: %w", err)
	}
	sc, ok := sentCode.(*tg.AuthSentCode)
	if !ok {
		return "", fmt.Errorf("unexpected SentCode type %T", sentCode)
	}
	lastPhone = phone
	lastCodeHash = sc.PhoneCodeHash
	return sc.PhoneCodeHash, nil
}

// SignIn submits the code received via SMS/app. Returns "OK" on success, "PASSWORD_NEEDED" if
// the account has 2FA enabled (caller must then call SubmitPassword).
func SignIn(code string) (string, error) {
	if client == nil {
		return "", fmt.Errorf("client not configured — call SendCode first")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	_, err := client.Auth().SignIn(ctx, lastPhone, code, lastCodeHash)
	if err != nil {
		if err == auth.ErrPasswordAuthNeeded {
			return "PASSWORD_NEEDED", nil
		}
		return "", fmt.Errorf("SignIn: %w", err)
	}
	return "OK", nil
}

// SubmitPassword completes 2FA login after SignIn returned "PASSWORD_NEEDED".
func SubmitPassword(password string) error {
	if client == nil {
		return fmt.Errorf("client not configured")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	_, err := client.Auth().Password(ctx, password)
	if err != nil {
		return fmt.Errorf("Password: %w", err)
	}
	return nil
}

// ResolveMessageInfo resolves a public channel by @username and fetches messageID, returning a
// "size|mime" string for the video/document found there. Caches the resolved file location so a
// subsequent DownloadChunk call can use it — this spike only ever holds one resolved file.
func ResolveMessageInfo(channelUsername string, messageID int64) (string, error) {
	if api == nil {
		return "", fmt.Errorf("client not configured")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	resolved, err := api.ContactsResolveUsername(ctx, &tg.ContactsResolveUsernameRequest{
		Username: channelUsername,
	})
	if err != nil {
		return "", fmt.Errorf("ContactsResolveUsername: %w", err)
	}
	if len(resolved.Chats) == 0 {
		return "", fmt.Errorf("no chat resolved for %q", channelUsername)
	}
	ch, ok := resolved.Chats[0].(*tg.Channel)
	if !ok {
		return "", fmt.Errorf("resolved chat is not a channel: %T", resolved.Chats[0])
	}

	msgsClass, err := api.ChannelsGetMessages(ctx, &tg.ChannelsGetMessagesRequest{
		Channel: &tg.InputChannel{ChannelID: ch.ID, AccessHash: ch.AccessHash},
		ID:      []tg.InputMessageClass{&tg.InputMessageID{ID: int(messageID)}},
	})
	if err != nil {
		return "", fmt.Errorf("ChannelsGetMessages: %w", err)
	}
	messages, ok := msgsClass.(*tg.MessagesChannelMessages)
	if !ok {
		return "", fmt.Errorf("unexpected messages response type %T", msgsClass)
	}
	if len(messages.Messages) == 0 {
		return "", fmt.Errorf("message %d not found in %q", messageID, channelUsername)
	}
	msg, ok := messages.Messages[0].(*tg.Message)
	if !ok {
		return "", fmt.Errorf("message %d is not a regular message: %T", messageID, messages.Messages[0])
	}
	mediaDoc, ok := msg.Media.(*tg.MessageMediaDocument)
	if !ok {
		return "", fmt.Errorf("message %d has no document media: %T", messageID, msg.Media)
	}
	doc, ok := mediaDoc.Document.(*tg.Document)
	if !ok {
		return "", fmt.Errorf("message %d document is empty/unavailable: %T", messageID, mediaDoc.Document)
	}

	resolvedMu.Lock()
	resolvedLocation = &tg.InputDocumentFileLocation{
		ID:            doc.ID,
		AccessHash:    doc.AccessHash,
		FileReference: doc.FileReference,
	}
	resolvedMu.Unlock()

	return fmt.Sprintf("%d|%s", doc.Size, doc.MimeType), nil
}

// DownloadChunk fetches [offset, offset+limit) of the file resolved by the last
// ResolveMessageInfo call via raw upload.getFile. Deliberately ignores CDN-redirect/DC-migration
// handling — that's Phase 3's required work (see plan), this spike only needs to prove a single
// successful chunk fetch against a file that happens to live on the home DC.
func DownloadChunk(offset int64, limit int32) ([]byte, error) {
	resolvedMu.Lock()
	loc := resolvedLocation
	resolvedMu.Unlock()
	if loc == nil {
		return nil, fmt.Errorf("no file resolved — call ResolveMessageInfo first")
	}
	if api == nil {
		return nil, fmt.Errorf("client not configured")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	req := &tg.UploadGetFileRequest{
		Location: loc,
		Offset:   offset,
		Limit:    int(limit),
	}
	req.SetPrecise(true)
	req.SetCDNSupported(true)

	res, err := api.UploadGetFile(ctx, req)
	if err != nil {
		return nil, fmt.Errorf("UploadGetFile: %w", err)
	}
	file, ok := res.(*tg.UploadFile)
	if !ok {
		return nil, fmt.Errorf("unexpected upload.getFile response %T (likely a CDN redirect — not handled by this spike)", res)
	}
	return file.Bytes, nil
}
