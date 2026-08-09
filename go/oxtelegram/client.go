// Package oxtelegram is the shared Go facade wrapping github.com/gotd/td for on-device
// Telegram direct-play — compiled to an Android .aar (gomobile bind) and a Windows .dll (cgo
// c-shared). See C:\Users\Aryan\.claude\plans\prancy-rolling-kernighan.md.
//
// Deliberately never imports github.com/gotd/td/telegram/updates: that package is gotd/td's
// opt-in equivalent of TDLib's forced account-wide backlog sync (the whole reason this
// migration exists — see the plan's Context section). Do not add it.
package oxtelegram

import (
	"context"
	"fmt"
	"sync"
	"time"

	"github.com/gotd/td/telegram"
	"github.com/gotd/td/tg"
)

// Client wraps a telegram.Client's connection lifecycle: created on Configure, torn down on
// Close. Callers are expected to Close it once a playback/login session ends rather than hold
// it open indefinitely — proven this session (see TdlibBridgeObject.onTelegramPlaybackEnded)
// that eager idle-close avoids background CPU/battery drain, and is kept here as a deliberate
// lifecycle choice even though gotd/td itself has no forced-backlog-sync problem to work around.
type Client struct {
	apiID   int
	apiHash string
	storage SessionStorage

	mu      sync.Mutex
	tg      *telegram.Client
	cancel  context.CancelFunc
	runDone chan struct{}

	// Auth is valid only between a successful Configure and the matching Close.
	Auth *AuthController
}

func NewClient(apiID int, apiHash string, storage SessionStorage) *Client {
	return &Client{apiID: apiID, apiHash: apiHash, storage: storage}
}

// Configure starts the underlying connection and blocks until it's ready to accept auth/API
// calls, or ctx is cancelled, or 30s elapse. Idempotent — a second call while already configured
// is a no-op. sink receives auth state push notifications for the lifetime of this Client.
func (c *Client) Configure(ctx context.Context, sink AuthEventSink) error {
	c.mu.Lock()
	if c.tg != nil {
		c.mu.Unlock()
		return nil
	}

	tgClient := telegram.NewClient(c.apiID, c.apiHash, telegram.Options{
		SessionStorage: &sessionStorageAdapter{backing: c.storage},
	})

	runCtx, cancel := context.WithCancel(context.Background())
	ready := make(chan error, 1)
	runDone := make(chan struct{})

	go func() {
		defer close(runDone)
		err := tgClient.Run(runCtx, func(innerCtx context.Context) error {
			select {
			case ready <- nil:
			default:
			}
			<-innerCtx.Done()
			return nil
		})
		if err != nil && runCtx.Err() == nil {
			select {
			case ready <- err:
			default:
			}
		}
	}()

	c.tg = tgClient
	c.cancel = cancel
	c.runDone = runDone
	c.Auth = newAuthController(tgClient, c.apiID, c.apiHash, sink)
	c.mu.Unlock()

	select {
	case err := <-ready:
		if err != nil {
			return fmt.Errorf("client run failed before ready: %w", err)
		}
	case <-ctx.Done():
		return ctx.Err()
	case <-time.After(30 * time.Second):
		return fmt.Errorf("client did not become ready within 30s")
	}

	c.Auth.checkInitialStatus(ctx)
	return nil
}

// API returns the raw RPC client for resolve/download calls (Phase 3). Valid only after a
// successful Configure; nil otherwise.
func (c *Client) API() *tg.Client {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.tg == nil {
		return nil
	}
	return c.tg.API()
}

// mediaOnlyDC opens a pooled connection to dcID for file downloads — used when a chunk fetch on
// the home DC returns FILE_MIGRATE_<n> (see download.go). telegram.Client.MediaOnly handles the
// auth.export/auth.import authorization transfer to that DC automatically; no manual key
// exchange needed.
func (c *Client) mediaOnlyDC(ctx context.Context, dcID int) (telegram.CloseInvoker, error) {
	c.mu.Lock()
	tgClient := c.tg
	c.mu.Unlock()
	if tgClient == nil {
		return nil, fmt.Errorf("client not configured")
	}
	return tgClient.MediaOnly(ctx, dcID, 1)
}

// Close cancels the connection and waits for its background goroutine to exit. Safe to call
// even if Configure was never called or already closed.
func (c *Client) Close() error {
	c.mu.Lock()
	cancel := c.cancel
	done := c.runDone
	c.tg = nil
	c.cancel = nil
	c.runDone = nil
	c.Auth = nil
	c.mu.Unlock()

	if cancel == nil {
		return nil
	}
	cancel()
	if done != nil {
		<-done
	}
	return nil
}
