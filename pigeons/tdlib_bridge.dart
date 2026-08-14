import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/tdlib_bridge.g.dart',
    dartOptions: DartOptions(),
    kotlinOut: 'android/app/src/main/kotlin/app/oxplayer/api/TdlibBridge.g.kt',
    kotlinOptions: KotlinOptions(
      includeErrorClass: false,
    ),
    dartPackageName: 'nl_jknaapen_fladder.tdlib_bridge',
  ),
)

/// Mirrors the subset of TdApi.AuthorizationState this module surfaces to Dart
/// (see app.oxplayer.tdlibbridge.auth.TdlibAuthState on the Kotlin side).
enum OxTdlibAuthStateKind {
  uninitialized,
  waitingForPhoneNumber,
  waitingForCode,
  waitingForPassword,
  waitingForQrConfirmation,
  ready,
  loggingOut,
  closed,
  failed,
}

class OxTdlibAuthState {
  final OxTdlibAuthStateKind kind;
  // Set when kind == waitingForQrConfirmation: the tg:// login URL to render as a QR code.
  final String? qrLoginUrl;
  // Set when kind == waitingForPassword: TDLib's password hint for the account, if any.
  final String? passwordHint;
  // Set when kind == failed: human-readable message for the login UI.
  final String? errorMessage;

  const OxTdlibAuthState({
    required this.kind,
    this.qrLoginUrl,
    this.passwordHint,
    this.errorMessage,
  });
}

/// One playback session's Telegram-backed video source, parsed from the PlaybackInfo Path
/// `oxplayer-tg://{providerBotId}/{messageId}?loc={locator}`.
class OxTdlibPlaybackSource {
  /// The delivery bot whose DM holds the video. 0 on a cold play: the backend round-robins across
  /// senders and may fail over mid-request, so it does not commit to one until the copy lands —
  /// the native side then learns the real sender from the update that carries [locator].
  final int providerBotId;
  /// The message id inside that DM, or 0 when the backend has none remembered yet and a fresh copy
  /// is on its way (the native side then matches the live push by [locator] instead).
  final int messageId;
  /// True when the target player is mpv/mdk (no DataSource-style hook for a custom scheme) —
  /// returns a http://127.0.0.1:{port}/{fileId} url served by TdlibHttpBridgeServer instead of
  /// tdlib-file://{fileId}. False (default) keeps the existing ExoPlayer DataSource path.
  final bool preferHttpBridge;
  /// The ?loc= query param off the PlaybackInfo Path: the caption on the copied message,
  /// OXM_PREFIX_recordNo with no '#' (see apps/api's resolveTelegramDelivery). Unique per stored
  /// file, and it does two jobs: it picks out the live-pushed document that answers THIS request
  /// instead of whatever arrives next on the shared receive channel (confirmed a real bug without
  /// it — concurrent dashboard-slider prefetches could hand one item's video to a different item's
  /// player), and on the remembered path it verifies [messageId] still holds the expected file.
  /// Always present now — both login modes read out of a DM.
  final String locator;

  const OxTdlibPlaybackSource({
    required this.providerBotId,
    required this.messageId,
    required this.locator,
    this.preferHttpBridge = false,
  });
}

/// One delivery sender, as published by the backend's GET /telegram/provider-bots. The username is
/// needed only for first contact (contacts.resolveUsername -> startBot); afterwards everything
/// addresses the bot by [id]. Tokens never reach the client.
class OxTdlibProviderBot {
  final int id;
  final String username;

  const OxTdlibProviderBot({required this.id, required this.username});
}

/// Where a delivered video actually landed, as observed by THIS session. Both halves can only come
/// from the receiving side: private-chat message ids are numbered per side, and the server
/// round-robins across senders so it does not know which one won.
class OxTdlibDeliveryRef {
  final int messageId;
  final int providerBotId;

  const OxTdlibDeliveryRef({required this.messageId, required this.providerBotId});
}

@HostApi()
abstract class OxTdlibBridgeApi {
  /// Must be called once before any other method (idempotent) — starts the underlying
  /// TDLib client with [apiId]/[apiHash] from OxplayerEnv (this module's own user-session
  /// credentials, distinct from the bot-based OX login's credentials).
  @async
  void configure(int apiId, String apiHash);

  /// Current auth state; also pushed via OxTdlibBridgeEvents.onAuthStateChanged.
  /// Synchronous — this just reads cached state, no TDLib round-trip.
  OxTdlibAuthState currentAuthState();

  /// Phone/tablet flow, step 1. Async: waits on the real TdApi round-trip.
  @async
  void submitPhoneNumber(String phoneNumber);

  /// Phone/tablet flow, step 2.
  @async
  void submitCode(String code);

  /// Phone/tablet flow, step 3 — only valid when state is waitingForPassword.
  @async
  void submitTwoFactorPassword(String password);

  /// Android TV flow: request a QR login token; UI renders the URL pushed via
  /// onAuthStateChanged(waitingForQrConfirmation) as a QR code.
  @async
  void requestQrLogin();

  /// Bot-token login: an alternative to phone/QR for users who don't want to give OXPlayer
  /// access to their personal Telegram account. Logs in as a bot (gotd/td
  /// auth.importBotAuthorization) instead — goes straight to ready, no code/2FA step.
  @async
  void submitBotToken(String token);

  /// Server-side session invalidation + local TDLib session wipe.
  @async
  void logOut();

  /// Resolves [source] and starts downloading via TDLib, returning either a
  /// tdlib-file://{fileId} uri (ExoPlayer DataSource path) or, when
  /// source.preferHttpBridge is true, a http://127.0.0.1:{port}/{fileId} uri served by
  /// TdlibHttpBridgeServer (mpv/mdk path — see that class for why).
  /// Throws if no MTProto/TDLib session is logged in yet — callers should
  /// check currentAuthState() first and prompt login if not ready.
  @async
  String startPlaybackSession(OxTdlibPlaybackSource source);

  /// Where the last successful resolve of [locator] landed, or null if this session has not read
  /// one. Dart reports it to the backend (POST /me/telegram-delivery) so the NEXT play of the same
  /// file is answered straight from the delivery table with no Telegram copy at all.
  ///
  /// It has to come from here rather than from the server: copyMessage hands the SENDING bot an id
  /// from its own side of the private chat, and private-chat ids are numbered per side, so only
  /// the receiving session ever sees the id that can be re-read later — and only it knows which
  /// sender the backend's round-robin actually settled on.
  /// Synchronous — reads an in-memory map, no MTProto round-trip.
  OxTdlibDeliveryRef? deliveryRefForLocator(String locator);

  /// Registers interest in [locator] BEFORE the PlaybackInfo call that triggers the copy, so a
  /// delivery that lands while that HTTP request is still in flight is captured rather than raced
  /// for. Idempotent, synchronous, no MTProto round-trip.
  void armDeliveryWaiter(String locator);

  /// Resolves [source] and remembers where it landed WITHOUT opening a download — the warm-up path.
  /// Scrolling the dashboard warms a dozen titles at once, and starting a dozen progressive
  /// downloads for videos nobody pressed play on would spend the user's data on bytes that get
  /// thrown away. Resolving is enough: it makes the backend remember the message id, so the
  /// eventual play needs no Telegram call at all.
  @async
  void warmDelivery(OxTdlibPlaybackSource source);

  /// Starts, mutes and archives every delivery sender on this account, so delivery copies never
  /// land in the user's visible inbox. Called on every app enter (not just after login) because a
  /// sender can be added to the backend's list at any time.
  ///
  /// No-op for a bot-token login: a bot is not a user account, has no dialog list to archive, and
  /// its B2B DM was already opened by main-bot's /connectbot.
  @async
  void ensureProviderBotsReady(List<OxTdlibProviderBot> bots);

  /// Stops the active playback session's download and closes the TDLib client (does not log
  /// out — the on-disk session persists, next play just reconnects). Callers on every backend
  /// (ExoPlayer's own hook is native-side via VideoPlayerImplementation.clearSession; mpv/mdk
  /// have no equivalent Activity-scoped teardown, so their wrapper must call this explicitly
  /// when a Telegram-sourced item finishes) — see TdlibBridgeObject.onTelegramPlaybackEnded.
  @async
  void stopPlaybackSession(String sessionUri);

  /// Fetches a Telegram-signed Mini App `initData` payload for [botUsername] via TDLib's
  /// GetWebAppLinkUrl/GetWebAppUrl/GetMainWebApp — requires a Ready auth state (real Telegram
  /// login already completed) and a Mini App configured on that bot via @BotFather. Exchange the
  /// result with the backend's POST /auth/telegram to obtain OX session tokens; see
  /// OxplayerTelegramAuthClient. [webAppShortName]/[hostedHttpsUrl] may be null/empty if unset —
  /// at least one working WebApp path must be configured on the bot for this to succeed.
  @async
  String fetchWebAppInitData(String botUsername, String? webAppShortName, String? hostedHttpsUrl);
}

@FlutterApi()
abstract class OxTdlibBridgeEvents {
  void onAuthStateChanged(OxTdlibAuthState state);
}
