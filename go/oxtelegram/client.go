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
	"log"
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

	// sink is kept from the last Configure so the self-healing reconnect (see watchRun) can rebuild
	// the client without the host having to re-supply it.
	sink AuthEventSink
	// health is the last connection state reported to healthSink; guarded by mu.
	health ConnectionHealth
	// healthSink is optional — the host sets it via SetConnectionSink to drive UI. Connection
	// recovery does NOT depend on it.
	healthSink ConnectionSink
	// closed is set by Close/LogOut so watchRun stops reconnecting instead of fighting a
	// deliberate shutdown.
	closed bool
	// runGen increments per Configure so a watcher from a superseded run cannot reconnect on
	// behalf of a newer one.
	runGen int64

	// pushWaiters/pushArrived deliver documents from live-pushed private messages to whichever
	// resolve call is waiting for that SPECIFIC copy. The update dispatcher is registered from
	// Configure onward (not just during a resolve call), but registerPushWaiter can only run
	// *after* this client has the locator — which only exists after the PlaybackInfo HTTP round
	// trip that triggered the server-side copy already completed. So the push can legitimately
	// arrive before anyone is waiting for it; pushArrived is the buffer for exactly that ordering,
	// keyed by the same locator, checked first by registerPushWaiter before it falls back to
	// actually waiting.
	//
	// Keyed by the copied message's caption — the locator, OXM_PREFIX_recordNo (see apps/api's
	// resolveTelegramDelivery) — NOT a single shared channel/buffer. Confirmed a real bug on real
	// devices: prefetching several dashboard items copies several different videos into the same
	// DM in close succession, and a single shared channel handed whichever document arrived
	// next to whichever resolve call happened to be waiting, playing the wrong title. The locator
	// lets each concurrent resolve call wait only for its own answer, and since it is unique per
	// stored file, two concurrent copies that DO collide on it are the same bytes anyway.
	//
	// This waiting path is now only the cold case. A message whose id is known can be re-read
	// directly (messages.getMessages works for bots too; only enumeration — getHistory/search —
	// returns BOT_METHOD_INVALID), so once the server has been told the id, resolves go straight to
	// resolveVideoFileByDMMessageID and no copy happens at all.
	pushMu      sync.Mutex
	pushWaiters map[string]chan *pushedMessage
	pushArrived map[string]pushArrival

	// deliveryRefs remembers locator -> (message id, sending bot id) for messages this session has
	// actually read, so the Dart layer can report both to the backend (DeliveryRefForLocator).
	// Only the RECEIVER knows the message id: private-chat ids are numbered per side, so the id the
	// sending bot got back from copyMessage is a different one entirely. And only the receiver
	// knows WHICH sender won, because the server round-robins and may fail over mid-request.
	dmMu         sync.Mutex
	deliveryRefs map[string]deliveryRefEntry

	// providerPeers are InputPeerUser values from EnsureProviderBotsReady (access_hash included).
	// GetHistory against these DMs finds copies that live-push missed — SearchGlobal skips Archive.
	providerPeersMu sync.Mutex
	providerPeers   map[int64]*tg.InputPeerUser
}

// pushedMessage is one live-pushed document, the id it landed on in THIS session's DM, and the bot
// that sent it.
type pushedMessage struct {
	doc           *tg.Document
	messageID     int64
	providerBotID int64
}

type pushArrival struct {
	msg *pushedMessage
	at  time.Time
}

// DeliveryRef is the pair the backend needs to answer the next play of this file without copying
// anything: which message, in whose DM.
type DeliveryRef struct {
	MessageID     int64
	ProviderBotID int64
}

type deliveryRefEntry struct {
	ref DeliveryRef
	at  time.Time
}

// pushArrivedTTL bounds how long an unclaimed early-arrived push is kept — generous relative to
// botModeResolveTimeout so a slow-to-register waiter still finds it, but not unbounded (a
// cancelled/never-issued resolve for the same locator would otherwise leak this entry forever).
const pushArrivedTTL = 60 * time.Second

// deliveryRefTTL bounds how long a locator -> delivery ref entry is kept for reporting. Only needs
// to outlive the gap between a successful resolve and the Dart layer's report call, which is one
// method call away; kept generous anyway since each entry is three words.
const deliveryRefTTL = 10 * time.Minute

// registerPushWaiter returns a channel that receives the pushed message for locator, checking
// first whether it already arrived (see pushArrived's doc comment) before falling back to
// actually waiting. Callers must eventually call unregisterPushWaiter (defer it).
func (c *Client) registerPushWaiter(locator string) chan *pushedMessage {
	ch := make(chan *pushedMessage, 1)
	c.pushMu.Lock()
	defer c.pushMu.Unlock()
	c.pruneStalePushesLocked()
	if c.pushWaiters == nil {
		c.pushWaiters = make(map[string]chan *pushedMessage)
	}
	if existing, ok := c.pushWaiters[locator]; ok {
		// Already armed (ArmDeliveryWaiter ran before the resolve). Reuse that channel rather than
		// replacing it, or the arm would be silently discarded and an early push would be dropped.
		return existing
	}
	if arrival, ok := c.pushArrived[locator]; ok {
		delete(c.pushArrived, locator)
		ch <- arrival.msg
		// Must keep this channel in the map. ArmDeliveryWaiter ignores the return
		// value — dropping it here discarded the early push, then warm/play both
		// waited 20s on an empty waiter (oxm_dev_459: copy sent, never recorded).
		c.pushWaiters[locator] = ch
		return ch
	}
	c.pushWaiters[locator] = ch
	return ch
}

// ArmDeliveryWaiter registers interest in locator BEFORE the delivery request goes out, so a copy
// that lands while the PlaybackInfo HTTP call is still in flight is captured rather than raced for.
//
// pushArrived already buffers an early push, so this is a latency guard rather than a correctness
// one — but the buffer has a TTL and is pruned, and arming first removes the window entirely.
// Idempotent: arming twice for the same locator keeps the first channel.
func (c *Client) ArmDeliveryWaiter(locator string) {
	if locator == "" {
		return
	}
	c.registerPushWaiter(locator)
}

func (c *Client) unregisterPushWaiter(locator string) {
	c.pushMu.Lock()
	delete(c.pushWaiters, locator)
	// Keep pushArrived: a second resolve (play after prefetch timeout) still needs it.
	c.pushMu.Unlock()
}

// deliverPushedDoc routes an incoming pushed document to whichever resolve call registered for
// its locator, or buffers it in pushArrived if none has registered yet.
func (c *Client) deliverPushedDoc(locator string, doc *tg.Document, messageID, providerBotID int64) {
	// Remember even if no waiter is armed yet. Play polls DeliveryRefForLocator and
	// can getMessages instead of sharing the 0/0 channel with prefetch warmDelivery.
	c.rememberDeliveryRef(locator, messageID, providerBotID)
	c.pushMu.Lock()
	defer c.pushMu.Unlock()
	c.pruneStalePushesLocked()
	msg := &pushedMessage{doc: doc, messageID: messageID, providerBotID: providerBotID}
	if ch, ok := c.pushWaiters[locator]; ok {
		delete(c.pushWaiters, locator)
		select {
		case ch <- msg:
		default:
		}
		return
	}
	c.pushArrived[locator] = pushArrival{msg: msg, at: time.Now()}
}

// pruneStalePushesLocked drops early-arrived pushes nobody ever claimed (a cancelled prefetch,
// or a resolve that gave up after its own timeout). Callers must hold pushMu.
func (c *Client) pruneStalePushesLocked() {
	if len(c.pushArrived) == 0 {
		return
	}
	cutoff := time.Now().Add(-pushArrivedTTL)
	for locator, arrival := range c.pushArrived {
		if arrival.at.Before(cutoff) {
			delete(c.pushArrived, locator)
		}
	}
}

// rememberDeliveryRef records that locator was read at messageID inside providerBotID's DM.
func (c *Client) rememberDeliveryRef(locator string, messageID, providerBotID int64) {
	if locator == "" || messageID <= 0 {
		return
	}
	c.dmMu.Lock()
	defer c.dmMu.Unlock()
	if c.deliveryRefs == nil {
		c.deliveryRefs = make(map[string]deliveryRefEntry)
	}
	cutoff := time.Now().Add(-deliveryRefTTL)
	for k, e := range c.deliveryRefs {
		if e.at.Before(cutoff) {
			delete(c.deliveryRefs, k)
		}
	}
	c.deliveryRefs[locator] = deliveryRefEntry{
		ref: DeliveryRef{MessageID: messageID, ProviderBotID: providerBotID},
		at:  time.Now(),
	}
}

// DeliveryRefForLocator returns the message id and sending bot this session read for locator, both
// zero if it has read none. The Dart layer calls this after a successful resolve and reports the
// pair to the backend (POST /me/telegram-delivery), which is what lets the NEXT play skip the copy.
func (c *Client) DeliveryRefForLocator(locator string) DeliveryRef {
	c.dmMu.Lock()
	defer c.dmMu.Unlock()
	return c.deliveryRefs[locator].ref
}

func NewClient(apiID int, apiHash string, storage SessionStorage) *Client {
	return &Client{apiID: apiID, apiHash: apiHash, storage: storage}
}

// isClosed reports whether ch has been closed, without blocking. Used to tell a live gotd run
// loop from one that already exited — see Configure.
func isClosed(ch chan struct{}) bool {
	select {
	case <-ch:
		return true
	default:
		return false
	}
}

// ConnectionHealth is the liveness of the MTProto socket, which is deliberately NOT the same
// question as the auth state: a logged-in account whose run loop has died reports READY auth and
// still cannot fetch a single byte. Reporting that as "logged out" is what sent TV users to a
// login screen for a problem a reconnect fixes.
type ConnectionHealth string

const (
	// HealthUninitialized — Configure has never succeeded.
	HealthUninitialized ConnectionHealth = "uninitialized"
	// HealthConnecting — a Run loop is starting (first connect or a reconnect in progress).
	HealthConnecting ConnectionHealth = "connecting"
	// HealthReady — the run loop is live and RPCs can be issued.
	HealthReady ConnectionHealth = "ready"
	// HealthDegraded — the run loop exited while credentials are still believed valid. Recoverable
	// by rebuilding the client, which watchRun does automatically; never a reason to ask the user
	// to log in again.
	HealthDegraded ConnectionHealth = "degraded"
)

// ConnectionSink receives connection-health transitions. Optional and purely informational — the
// reconnect loop runs whether or not one is set. Separate from AuthEventSink so hosts that only
// care about login (and the Windows cshared build) need no change.
type ConnectionSink interface {
	OnConnectionHealthChanged(state string)
}

// reconnectBackoffs are the waits between self-healing reconnect attempts after the run loop dies.
// Front-loaded because the common cause is a brief transport blip (wifi roam, TV waking from
// sleep) that is fixed by the time the first retry lands; capped so a genuinely offline device
// settles into one cheap attempt a minute rather than spinning.
var reconnectBackoffs = []time.Duration{
	time.Second,
	2 * time.Second,
	5 * time.Second,
	15 * time.Second,
	30 * time.Second,
	60 * time.Second,
}

// SetConnectionSink registers (or clears, with nil) the health listener and immediately replays the
// current state, so a host attaching after Configure does not sit on a stale default.
func (c *Client) SetConnectionSink(sink ConnectionSink) {
	c.mu.Lock()
	c.healthSink = sink
	current := c.health
	if current == "" {
		current = HealthUninitialized
	}
	c.mu.Unlock()
	if sink != nil {
		sink.OnConnectionHealthChanged(string(current))
	}
}

// Health is the current connection state — the cheap synchronous read a playback gate uses before
// deciding whether starting a download is worth attempting.
func (c *Client) Health() ConnectionHealth {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.health == "" {
		return HealthUninitialized
	}
	return c.health
}

// setHealth records the state and notifies the sink outside the lock (the host implementation
// crosses a JNI boundary and must never run while holding c.mu).
func (c *Client) setHealth(next ConnectionHealth) {
	c.mu.Lock()
	if c.health == next {
		c.mu.Unlock()
		return
	}
	c.health = next
	sink := c.healthSink
	c.mu.Unlock()
	log.Printf("oxtelegram: connection health -> %s", next)
	if sink != nil {
		sink.OnConnectionHealthChanged(string(next))
	}
}

// watchRun turns a dead run loop from a silent hang into a reported, self-healing event.
//
// gotd does not resurrect Run, and the *telegram.Client keeps answering as if healthy afterwards,
// so without this every later UploadGetFile fails with "waitSession: connection dead" and the only
// cure is killing the app. gen guards against a watcher outliving its own Configure: if a newer
// Configure has already run, this watcher just exits.
func (c *Client) watchRun(gen int64, runDone chan struct{}, runCtx context.Context) {
	<-runDone

	c.mu.Lock()
	stale := c.runGen != gen
	closed := c.closed
	sink := c.sink
	c.mu.Unlock()
	// Deliberate teardown (Close/LogOut) or superseded by a newer Configure — nothing to heal.
	if stale || closed || runCtx.Err() != nil {
		return
	}

	log.Printf("oxtelegram: run loop exited unexpectedly — reconnecting")
	c.setHealth(HealthDegraded)

	for attempt := 0; ; attempt++ {
		wait := reconnectBackoffs[len(reconnectBackoffs)-1]
		if attempt < len(reconnectBackoffs) {
			wait = reconnectBackoffs[attempt]
		}
		time.Sleep(wait)

		c.mu.Lock()
		stale = c.runGen != gen
		closed = c.closed
		c.mu.Unlock()
		if stale || closed {
			return
		}

		// Configure sees the closed runDone and rebuilds from the same on-disk session — no user
		// interaction, because the credentials never became invalid.
		ctx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
		err := c.Configure(ctx, sink)
		cancel()
		if err == nil {
			log.Printf("oxtelegram: reconnected after %d attempt(s)", attempt+1)
			return
		}
		log.Printf("oxtelegram: reconnect attempt %d failed: %v", attempt+1, err)
	}
}

// Configure starts the underlying connection and blocks until it's ready to accept auth/API
// calls, or ctx is cancelled, or 30s elapse. Idempotent — a second call while already configured
// AND healthy is a no-op; a second call after the run loop died rebuilds, which is what makes
// recovery possible without restarting the process. sink receives auth state push notifications
// for the lifetime of this Client.
func (c *Client) Configure(ctx context.Context, sink AuthEventSink) error {
	c.mu.Lock()
	c.closed = false
	c.sink = sink
	if c.tg != nil {
		if c.runDone != nil && !isClosed(c.runDone) {
			c.mu.Unlock()
			return nil
		}
		// The run loop exited. gotd does not resurrect it, and c.tg keeps answering as if
		// healthy, so every later UploadGetFile fails with "waitSession: connection dead"
		// while ensureConfigured still reports "already configured" — a hang with no error
		// path, only recoverable by killing the app. Drop the corpse and rebuild below.
		if c.cancel != nil {
			c.cancel()
		}
		c.tg = nil
		c.cancel = nil
		c.runDone = nil
		c.Auth = nil
	}

	dispatcher := tg.NewUpdateDispatcher()
	c.pushMu.Lock()
	c.pushWaiters = make(map[string]chan *pushedMessage)
	c.pushArrived = make(map[string]pushArrival)
	c.pushMu.Unlock()
	dispatcher.OnNewMessage(func(_ context.Context, _ tg.Entities, u *tg.UpdateNewMessage) error {
		doc, locator, messageID, senderID := documentFromMessage(u.Message)
		if doc != nil {
			if locator != "" {
				log.Printf("oxtelegram: push %s msg=%d from=%d", locator, messageID, senderID)
			}
			c.deliverPushedDoc(locator, doc, messageID, senderID)
		}
		return nil
	})
	tgClient := telegram.NewClient(c.apiID, c.apiHash, telegram.Options{
		SessionStorage: &sessionStorageAdapter{backing: c.storage},
		// Required for QR: UpdateLoginToken must reach qrlogin.OnLoginToken. Default
		// (nil handler) sets NoUpdates=true and drops the scan signal.
		UpdateHandler: dispatcher,
		// gotd defaults MigrationTimeout to 15s (telegram/options.go). A DC migration is a full
		// second handshake to a different data-centre, not a round trip — confirmed on-device
		// (2026-08-17) that a bare connect alone already costs 15-18s on a TV/mobile link, so the
		// 15s default reliably starves the migration itself and every bot-token login on a
		// migrated account fails with "migrate to dc: context deadline exceeded", regardless of
		// authCallTimeout below (that only bounds the outer call — this is gotd's own inner
		// sub-timeout for the migration step and was never being overridden). Matches
		// authCallTimeout's existing 90s budget in mobile/bind.go so the outer deadline stays the
		// binding one.
		MigrationTimeout: 90 * time.Second,
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
	c.Auth = newAuthController(tgClient, c.apiID, c.apiHash, sink, dispatcher)
	c.runGen++
	gen := c.runGen
	c.mu.Unlock()

	c.setHealth(HealthConnecting)
	// Started before the readiness wait so a run loop that dies during startup is still noticed.
	go c.watchRun(gen, runDone, runCtx)

	select {
	case err := <-ready:
		if err != nil {
			c.setHealth(HealthDegraded)
			return fmt.Errorf("client run failed before ready: %w", err)
		}
	case <-ctx.Done():
		return ctx.Err()
	case <-time.After(30 * time.Second):
		return fmt.Errorf("client did not become ready within 30s")
	}

	c.setHealth(HealthReady)
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

// selfUserID is the logged-in Telegram user id, or 0 if Configure has not finished. Used to log
// whether startBot ran on the same account PlaybackInfo copies into.
func (c *Client) selfUserID(ctx context.Context) int64 {
	c.mu.Lock()
	tgClient := c.tg
	c.mu.Unlock()
	if tgClient == nil {
		return 0
	}
	self, err := tgClient.Self(ctx)
	if err != nil || self == nil {
		return 0
	}
	return self.ID
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
	// Marks this teardown deliberate so watchRun exits instead of treating it as a dropped
	// connection and reconnecting against the caller's wishes.
	c.closed = true
	c.mu.Unlock()

	c.setHealth(HealthUninitialized)

	if cancel == nil {
		return nil
	}
	cancel()
	if done != nil {
		<-done
	}
	return nil
}
