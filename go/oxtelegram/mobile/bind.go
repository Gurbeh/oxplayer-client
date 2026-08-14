// Package mobile is the gomobile-bind export surface for the oxtelegram facade — bound to an
// Android .aar via `gomobile bind`. Every exported type/function here must stay 100% flat per
// the plan's hard requirement: only primitives/strings/[]byte/simple structs/callback
// interfaces. No uint64, no Go generics, no github.com/gotd/td types (tg.*Class sum types,
// interfaces, etc.) may ever appear in an exported signature — gomobile bind cannot cross those,
// and Phase 0's spike already proved a fully-opaque facade like this one builds and works.
//
// gomobile also cannot marshal context.Context, so cancellation here is done via an explicit
// CancelCurrentRead() method instead of a context parameter — see PlaybackSession.
package mobile

import (
	"context"
	"encoding/json"
	"fmt"
	"sync"
	"time"

	"oxtelegram"
)

const callTimeout = 30 * time.Second

// providerBotsSetupTimeout covers start+mute+archive across the whole sender list, each of which is
// several sequential MTProto round trips. Generous because this runs off the playback path, at app
// enter, and a partial run leaves some senders unprepared.
const providerBotsSetupTimeout = 90 * time.Second

// SessionStorage is implemented by the host platform (Android EncryptedSharedPreferences,
// Windows DPAPI-protected file) to persist one opaque session blob.
type SessionStorage interface {
	Load() ([]byte, error)
	Store(data []byte) error
}

// AuthEventSink is implemented by the host platform to receive auth state push notifications —
// kind matches OxTdlibAuthStateKind's Pigeon-generated string values 1:1 (see oxtelegram.auth.go).
type AuthEventSink interface {
	OnAuthStateChanged(kind, qrLoginURL, passwordHint, errorMessage string)
}

type storageAdapter struct{ s SessionStorage }

func (a storageAdapter) Load() ([]byte, error)   { return a.s.Load() }
func (a storageAdapter) Store(data []byte) error { return a.s.Store(data) }

type sinkAdapter struct{ sink AuthEventSink }

func (a sinkAdapter) OnAuthStateChanged(kind, qrURL, hint, errMsg string) {
	a.sink.OnAuthStateChanged(kind, qrURL, hint, errMsg)
}

// Client is the gomobile-bound handle for one login/playback session's connection — mirrors
// oxtelegram.Client's lifecycle (Configure/Close), see that type's doc for why it's not kept
// alive across playback sessions.
type Client struct {
	inner *oxtelegram.Client
}

func NewClient(apiID int, apiHash string, storage SessionStorage) *Client {
	return &Client{inner: oxtelegram.NewClient(apiID, apiHash, storageAdapter{storage})}
}

// Configure starts the connection and blocks until ready for auth input (or 30s elapse).
func (c *Client) Configure(sink AuthEventSink) error {
	ctx, cancel := context.WithTimeout(context.Background(), callTimeout)
	defer cancel()
	return c.inner.Configure(ctx, sinkAdapter{sink})
}

func (c *Client) SubmitPhoneNumber(phone string) error {
	ctx, cancel := context.WithTimeout(context.Background(), callTimeout)
	defer cancel()
	return c.inner.Auth.SubmitPhoneNumber(ctx, phone)
}

// SubmitBotToken logs in as a bot instead of a personal phone/QR account — see
// oxtelegram.AuthController.SubmitBotToken.
func (c *Client) SubmitBotToken(token string) error {
	ctx, cancel := context.WithTimeout(context.Background(), callTimeout)
	defer cancel()
	return c.inner.Auth.SubmitBotToken(ctx, token)
}

func (c *Client) SubmitCode(code string) error {
	ctx, cancel := context.WithTimeout(context.Background(), callTimeout)
	defer cancel()
	return c.inner.Auth.SubmitCode(ctx, code)
}

// SubmitTwoFactorPassword completes 2FA login — reached from either the phone or QR flow (see
// oxtelegram.AuthController's doc on why this is one shared path, not two).
func (c *Client) SubmitTwoFactorPassword(password string) error {
	ctx, cancel := context.WithTimeout(context.Background(), callTimeout)
	defer cancel()
	return c.inner.Auth.SubmitTwoFactorPassword(ctx, password)
}

// RequestQrLogin starts the QR flow (Android TV). Long-lived by design — qrlogin.QR.Auth blocks
// internally until scanned/expired; cancelled only by LogOut/Close, not a timeout.
func (c *Client) RequestQrLogin() error {
	return c.inner.Auth.RequestQrLogin(context.Background())
}

func (c *Client) LogOut() error {
	// AuthLogOut can hang on bad networks; keep OX sign-out snappy. Local session wipe
	// still runs in Kotlin after this returns.
	ctx, cancel := context.WithTimeout(context.Background(), 4*time.Second)
	defer cancel()
	return c.inner.Auth.LogOut(ctx)
}

func (c *Client) Close() error {
	return c.inner.Close()
}

// FetchWebAppInitData fetches a Telegram-signed Mini App initData payload for exchange with the
// backend's OX-account login endpoint. See oxtelegram.Client.FetchWebAppInitData's doc for the
// messages.requestAppWebView/requestWebView/requestMainWebView fallback chain this drives.
func (c *Client) FetchWebAppInitData(botUsername, webAppShortName, hostedHTTPSURL, platform string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), callTimeout)
	defer cancel()
	return c.inner.FetchWebAppInitData(ctx, botUsername, webAppShortName, hostedHTTPSURL, platform)
}

// StartPlaybackSession resolves the delivery message and opens a progressive download backed by a
// cache file under cacheDir, returning a handle the caller reads from as bytes land.
//
// providerBotID/messageID come from the PlaybackInfo Path (oxplayer-tg://{botId}/{msgId}); both are
// 0 when the backend has nothing remembered and a fresh copy is in flight, in which case locator —
// the ?loc= query param — is what identifies the incoming copy. See
// oxtelegram.Client.ResolveVideoFile.
func (c *Client) StartPlaybackSession(providerBotID, messageID int64, cacheDir string, locator string) (*PlaybackSession, error) {
	ctx, cancel := context.WithTimeout(context.Background(), callTimeout)
	defer cancel()

	ref, err := c.inner.ResolveVideoFile(ctx, providerBotID, messageID, locator)
	if err != nil {
		return nil, err
	}
	// A cold resolve learns the DM message id off the live push, so record THAT rather than the 0
	// we were called with: it is what refreshFileReference re-resolves against when a
	// file_reference expires mid-download, which used to be unrecoverable on the cold path.
	if messageID <= 0 {
		if learned := c.inner.DeliveryRefForLocator(locator); learned.MessageID > 0 {
			messageID = learned.MessageID
		}
	}
	dl, err := c.inner.OpenDownload(ref, messageID, locator, cacheDir)
	if err != nil {
		return nil, err
	}
	return &PlaybackSession{dl: dl, ref: ref}, nil
}

// WarmDelivery resolves the delivery message and records its id WITHOUT opening a download.
//
// This is the warm-up path: scrolling the dashboard warms a dozen titles at once, and starting a
// dozen progressive downloads for videos nobody has pressed play on would spend the user's data on
// bytes that get thrown away. Resolving is enough — it makes the backend remember the message id,
// so the eventual play answers from the delivery table with no Telegram call at all.
func (c *Client) WarmDelivery(providerBotID, messageID int64, locator string) error {
	ctx, cancel := context.WithTimeout(context.Background(), callTimeout)
	defer cancel()
	_, err := c.inner.ResolveVideoFile(ctx, providerBotID, messageID, locator)
	return err
}

// ArmDeliveryWaiter registers interest in locator before the delivery request is sent, so a copy
// that arrives while PlaybackInfo is still in flight is captured rather than raced for.
func (c *Client) ArmDeliveryWaiter(locator string) {
	c.inner.ArmDeliveryWaiter(locator)
}

// DeliveryMessageIDForLocator returns the DM message id this session read for locator, or 0; see
// DeliveryProviderBotIDForLocator for the other half.
//
// Split into two int64 getters rather than returning a struct because gomobile only binds a narrow
// set of types across the JNI boundary, and two primitive calls into an in-memory map are cheaper
// than teaching the bridge a new class.
func (c *Client) DeliveryMessageIDForLocator(locator string) int64 {
	return c.inner.DeliveryRefForLocator(locator).MessageID
}

// DeliveryProviderBotIDForLocator returns the delivery bot whose DM held locator, or 0.
//
// The Dart layer reports this together with the message id (POST /me/telegram-delivery) so the next
// play of the same file needs no copy. Only the receiving side can know either number: private-chat
// ids are numbered per side, and the server round-robins across senders, so it does not know which
// one actually won.
func (c *Client) DeliveryProviderBotIDForLocator(locator string) int64 {
	return c.inner.DeliveryRefForLocator(locator).ProviderBotID
}

// EnsureProviderBotsReady starts, mutes and archives every delivery sender on this account so
// delivery copies never land in the user's visible inbox. bots is the JSON array returned by the
// backend's GET /telegram/provider-bots: [{"id":123,"username":"SomeBot"}].
//
// JSON rather than a repeated call per bot because gomobile cannot bind a slice of structs, and one
// call keeps the whole set atomic from the caller's point of view.
func (c *Client) EnsureProviderBotsReady(botsJSON string) error {
	var bots []oxtelegram.ProviderBot
	if err := json.Unmarshal([]byte(botsJSON), &bots); err != nil {
		return fmt.Errorf("parse provider bots: %w", err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), providerBotsSetupTimeout)
	defer cancel()
	return c.inner.EnsureProviderBotsReady(ctx, bots)
}

// PlaybackSession is the gomobile-safe handle for one resolved file's progressive download — see
// oxtelegram.DownloadSession for the real multi-DC/CDN/cancellation logic this wraps.
type PlaybackSession struct {
	dl  *oxtelegram.DownloadSession
	ref *oxtelegram.VideoFileRef

	mu      sync.Mutex
	cancels []context.CancelFunc
}

func (p *PlaybackSession) Size() int64          { return p.ref.Size }
func (p *PlaybackSession) MimeType() string     { return p.ref.MimeType }
func (p *PlaybackSession) LocalPath() string    { return p.dl.LocalPath() }
func (p *PlaybackSession) AvailableFrom() int64 { return p.dl.AvailableFrom() }
func (p *PlaybackSession) AvailableUpTo() int64 { return p.dl.AvailableUpTo() }
func (p *PlaybackSession) IsComplete() bool     { return p.dl.IsComplete() }

// EnsureAvailable blocks until [offset, offset+length) is downloaded, or CancelCurrentRead() is
// called from another goroutine/thread, or 2 minutes elapse.
//
// Concurrent EnsureAvailable calls are supported (multi-range HTTP bridge). CancelCurrentRead
// aborts all in-flight fetches — call it when the last active stream ends, not between seeks
// that still have other ranges downloading.
func (p *PlaybackSession) EnsureAvailable(offset, length int64) error {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	p.mu.Lock()
	p.cancels = append(p.cancels, cancel)
	p.mu.Unlock()
	defer cancel()

	return p.dl.EnsureAvailable(ctx, offset, length)
}

// CancelCurrentRead cancels all in-flight EnsureAvailable calls. Safe if none are running.
func (p *PlaybackSession) CancelCurrentRead() {
	p.mu.Lock()
	cancels := p.cancels
	p.cancels = nil
	p.mu.Unlock()
	for _, cancel := range cancels {
		cancel()
	}
}

// Close releases this session's resources (migrated-DC connection, cache file handle). Does not
// delete the cache file — a fresh PlaybackSession for the same file resumes from what's cached.
func (p *PlaybackSession) Close() {
	p.CancelCurrentRead()
	p.dl.Cancel()
}

// AsByteSource exposes this session to oxtelegram.HttpBridgeServer (Register).
func (p *PlaybackSession) AsByteSource() oxtelegram.ByteSource {
	return playbackByteSource{p: p}
}

type playbackByteSource struct{ p *PlaybackSession }

func (b playbackByteSource) Size() int64          { return b.p.Size() }
func (b playbackByteSource) LocalPath() string    { return b.p.LocalPath() }
func (b playbackByteSource) AvailableFrom() int64 { return b.p.AvailableFrom() }
func (b playbackByteSource) AvailableUpTo() int64 { return b.p.AvailableUpTo() }
func (b playbackByteSource) IsComplete() bool     { return b.p.IsComplete() }
func (b playbackByteSource) EnsureAvailable(ctx context.Context, offset, length int64) error {
	return b.p.dl.EnsureAvailable(ctx, offset, length)
}
func (b playbackByteSource) CancelCurrentRead() { b.p.CancelCurrentRead() }

// HttpBridgeServer is the gomobile-safe loopback Range server for libmpv.
type HttpBridgeServer struct {
	inner *oxtelegram.HttpBridgeServer
}

func NewHttpBridgeServer() *HttpBridgeServer {
	return &HttpBridgeServer{inner: oxtelegram.NewHttpBridgeServer()}
}

func (s *HttpBridgeServer) Register(fileID int, session *PlaybackSession) {
	s.inner.Register(fileID, session.AsByteSource())
}

func (s *HttpBridgeServer) Unregister(fileID int) {
	s.inner.Unregister(fileID)
}

// EnsureStarted returns the bound loopback port.
func (s *HttpBridgeServer) EnsureStarted() (int, error) {
	return s.inner.EnsureStarted()
}

// URLFor returns http://127.0.0.1:{port}/{fileID}.
func (s *HttpBridgeServer) URLFor(fileID int) (string, error) {
	return s.inner.URLFor(fileID)
}

func (s *HttpBridgeServer) Close() error {
	return s.inner.Close()
}
