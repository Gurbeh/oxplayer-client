import 'package:fladder/src/tdlib_bridge.g.dart';

/// Web/stub — Windows gotd host unavailable.
bool oxTelegramUseWindowsHost() => false;

class OxTelegramWindowsBridge {
  OxTelegramWindowsBridge({void Function(OxTdlibAuthState state)? onAuthStateChanged});

  OxTdlibAuthState get state =>
      OxTdlibAuthState(kind: OxTdlibAuthStateKind.uninitialized);

  Future<void> configure(int apiId, String apiHash) async {
    throw UnsupportedError('oxtelegram Windows host not available on this platform');
  }

  OxTdlibAuthState currentAuthState() => state;

  Future<void> submitPhoneNumber(String phone) async => throw UnsupportedError('windows-only');
  Future<void> submitBotToken(String token) async => throw UnsupportedError('windows-only');
  Future<void> submitCode(String code) async => throw UnsupportedError('windows-only');
  Future<void> submitTwoFactorPassword(String password) async =>
      throw UnsupportedError('windows-only');
  Future<void> requestQrLogin() async => throw UnsupportedError('windows-only');
  Future<void> logOut() async => throw UnsupportedError('windows-only');
  Future<String> startPlaybackSession(OxTdlibPlaybackSource source) async =>
      throw UnsupportedError('windows-only');
  Future<void> stopPlaybackSession(String sessionUri) async =>
      throw UnsupportedError('windows-only');
  Future<void> warmDelivery(OxTdlibPlaybackSource source) async =>
      throw UnsupportedError('windows-only');
  Future<void> ensureProviderBotsReady(List<OxTdlibProviderBot> bots) async =>
      throw UnsupportedError('windows-only');
  // The next three are silent no-ops rather than throws: callers treat "nothing armed / no id" as a
  // normal outcome, and this file is only ever reached on a platform where the Windows host isn't
  // the active bridge anyway.
  void armDeliveryWaiter(String locator) {}
  OxTdlibDeliveryRef? deliveryRefForLocator(String locator) => null;
  Future<String> fetchWebAppInitData(
    String botUsername,
    String? webAppShortName,
    String? hostedHttpsUrl,
  ) async =>
      throw UnsupportedError('windows-only');
}
