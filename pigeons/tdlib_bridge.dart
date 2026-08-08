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

/// One playback session's Telegram-backed video source, resolved from the
/// PlaybackInfo structured fields (TelegramChannelUsername / TelegramMessageId).
class OxTdlibPlaybackSource {
  final String channelUsername;
  final int messageId;
  /// True when the target player is mpv/mdk (no DataSource-style hook for a custom scheme) —
  /// returns a http://127.0.0.1:{port}/{fileId} url served by TdlibHttpBridgeServer instead of
  /// tdlib-file://{fileId}. False (default) keeps the existing ExoPlayer DataSource path.
  final bool preferHttpBridge;

  const OxTdlibPlaybackSource({
    required this.channelUsername,
    required this.messageId,
    this.preferHttpBridge = false,
  });
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
