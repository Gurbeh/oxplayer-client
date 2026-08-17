import 'dart:async';

import 'package:flutter/material.dart';

import 'package:fladder/oxplayer/ox_splash_brand.dart';
import 'package:fladder/util/localization_helper.dart';

/// Full-screen "we are actually working" experience shown while the first Telegram MTProto
/// connection for this device is establishing.
///
/// Confirmed on-device (2026-08-18, verbose gotd trace): the ~15-18s this takes is not network —
/// it is CPU-bound Diffie-Hellman key generation (big-integer modular exponentiation) for a fresh
/// MTProto auth key, which is unusually slow on this class of TV hardware. A bare spinner reads as
/// frozen for that whole stretch, so this cycles a typewriter-animated set of status lines instead
/// — the same trick modern AI-agent UIs use to keep a genuinely-working wait from feeling stuck.
///
/// Deliberately no back/cancel affordance: the operation underneath is bounded by the caller's own
/// timeout (submitBotToken's ~100s ceiling — see _kAuthRpcTimeout in
/// oxplayer_tdlib_bridge_controller.dart) and always resolves to either success (the caller stops
/// rendering this) or a thrown OxplayerTdlibBridgeException the caller's own error UI handles with
/// Retry — so there is no state this screen could trap someone in longer than that ceiling.
class OxplayerTdlibConnectingExperience extends StatefulWidget {
  const OxplayerTdlibConnectingExperience({super.key});

  /// True for as long as an instance of this widget is mounted anywhere. The login screen it
  /// lives inside watches this to hide its own chrome (switch-user button/FAB) while a takeover
  /// screen is up — a small escape hatch peeking through around the edges would defeat the point
  /// of "no back/cancel" documented above. A counter (not a plain bool) because the phone/QR
  /// panels can briefly mount a second instance while swapping state before the old one disposes.
  static final ValueNotifier<bool> isActive = ValueNotifier(false);
  static int _activeCount = 0;

  @override
  State<OxplayerTdlibConnectingExperience> createState() => _OxplayerTdlibConnectingExperienceState();
}

class _OxplayerTdlibConnectingExperienceState extends State<OxplayerTdlibConnectingExperience> {
  static const _charInterval = Duration(milliseconds: 45);
  static const _holdDuration = Duration(milliseconds: 1300);
  static const _fadeDuration = Duration(milliseconds: 220);

  Timer? _charTimer;
  Timer? _holdTimer;
  int _phraseIndex = 0;
  int _charCount = 0;
  bool _visible = true;

  List<String> _phrases(BuildContext context) {
    final loc = context.localized;
    return [
      loc.oxplayerConnectingPhrase1,
      loc.oxplayerConnectingPhrase2,
      loc.oxplayerConnectingPhrase3,
      loc.oxplayerConnectingPhrase4,
      loc.oxplayerConnectingPhrase5,
      loc.oxplayerConnectingPhrase6,
      loc.oxplayerConnectingPhrase7,
      loc.oxplayerConnectingPhrase8,
    ];
  }

  @override
  void initState() {
    super.initState();
    OxplayerTdlibConnectingExperience._activeCount++;
    OxplayerTdlibConnectingExperience.isActive.value = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _typeCurrentPhrase());
  }

  void _typeCurrentPhrase() {
    if (!mounted) return;
    _charTimer?.cancel();
    _charCount = 0;
    final length = _phrases(context)[_phraseIndex % 8].length;
    _charTimer = Timer.periodic(_charInterval, (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_charCount >= length) {
        timer.cancel();
        _holdTimer = Timer(_holdDuration, _advancePhrase);
        return;
      }
      setState(() => _charCount++);
    });
  }

  void _advancePhrase() {
    if (!mounted) return;
    setState(() => _visible = false);
    Timer(_fadeDuration, () {
      if (!mounted) return;
      setState(() {
        _phraseIndex++;
        _visible = true;
      });
      _typeCurrentPhrase();
    });
  }

  @override
  void dispose() {
    _charTimer?.cancel();
    _holdTimer?.cancel();
    OxplayerTdlibConnectingExperience._activeCount--;
    if (OxplayerTdlibConnectingExperience._activeCount <= 0) {
      OxplayerTdlibConnectingExperience._activeCount = 0;
      OxplayerTdlibConnectingExperience.isActive.value = false;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phrases = _phrases(context);
    final current = phrases[_phraseIndex % phrases.length];
    final shown = current.substring(0, _charCount.clamp(0, current.length));

    return PopScope(
      canPop: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const OxSplashBrand(),
            const SizedBox(height: 36),
            SizedBox(
              height: 28,
              width: double.infinity,
              child: AnimatedOpacity(
                opacity: _visible ? 1 : 0,
                duration: _fadeDuration,
                child: Text(
                  shown,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.75),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
