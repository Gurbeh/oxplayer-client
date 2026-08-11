# Legacy dual-edge routing + ox-stream client path (archived 2026-08-11)

Before the **native-only stream cleanup**, this app routed HTTP traffic (API + stream) across two
CDN edges (global via Cloudflare, Iran via Arvan) and resolved playback URLs to a legacy HTTP
proxy service (`ox-stream`, backend-side). Both were removed once Telegram-native playback (TDLib
plays a `t.me/...` link straight from the device) became the only playback path.

**Restore point:** `git checkout archive/pre-native-only-20260811`. Backend-side counterpart and
full architecture: `oxplayer-be/docs/archive/legacy-http-stream/README.md` at the same tag.

## What existed

- **Dual-edge routing** — `lib/oxplayer/oxplayer_route.dart` (`OxplayerEdge` enum: `global`/`iran`),
  `oxplayer_route_env.dart` (env keys: `OXPLAYER_API_BASE_IRAN`, `OXPLAYER_STREAM_BASE_IRAN`,
  `OXPLAYER_WEB_BASE_IRAN`, `OXPLAYER_IRAN_EDGE_ADDR`, `OXPLAYER_FORCE_EDGE`),
  `oxplayer_route_selector.dart` (startup probe + runtime switch on HTTP 451),
  `oxplayer_route_store.dart` (persisted last-known-good edge), `oxplayer_route_hints.dart`
  (parsed `X-Ox-Client-Country`/`X-Ox-Route-Required` response headers), `oxplayer_route_resume.dart`
  (re-probed edges on app resume), `oxplayer_route_interceptor.dart` (Chopper interceptor reacting
  to 451), `oxplayer_iran_stream_edge.dart` (Iran stream vanity-host 302 redirect handling — dropped
  `Authorization` header on redirect, so needed special-case resolution).
- **ox-stream HTTP client path** — `oxplayer_stream_nodes_api.dart` (fetched `/api/v1/stream/nodes`,
  picked a healthy CDN node), the ox-stream branch of `oxplayer_stream_url_resolver.dart` (rewrote
  an API-minted `/v/{id}.{ext}?token=...` URL to a healthy discovery node host),
  `oxplayer_stream_http_auth.dart` (Bearer-token/Cloudflare-Worker-signature header handling),
  `oxplayer_stream_warmup.dart` (CDN cache-warming range-GET prefetch), node-failover/repair logic
  in `oxplayer_playback_repair.dart` (`oxplayerIsOxStreamUrl`, `oxplayerTryRepairStreamUrl`).

## What replaced it

`writePlaybackInfoOK` (backend) now unconditionally returns a `t.me/{username}/{messageId}` link;
`oxplayer_tdlib_playback_resolver.dart` resolves it via the device's own TDLib session — no CDN
node, no JWT/slug URL, no dual-edge probing. `OxplayerEnv.apiBaseUrl` is the single API base for
all HTTP traffic (auth, feeds, config) that isn't playback.

Out of scope for the cleanup (still present, untouched): `ox_iran_flag_icon.dart` (Iran content
labeling UI — unrelated to routing), `oxplayer_pending_route.dart` (deep-link navigation — a
different meaning of "route", not CDN edge routing).
