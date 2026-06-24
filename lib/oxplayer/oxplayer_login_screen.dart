import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/oxplayer/oxplayer_claim_code_login_panel.dart';
import 'package:fladder/oxplayer/oxplayer_telegram_login_panel.dart';
import 'package:fladder/oxplayer/oxplayer_dotenv.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/providers/auth_provider.dart';
import 'package:fladder/screens/login/login_screen_credentials.dart';
import 'package:fladder/oxplayer/oxplayer_login_logo.dart';
import 'package:fladder/util/fladder_config.dart';

@RoutePage()
class OxplayerLoginScreen extends ConsumerStatefulWidget {
  const OxplayerLoginScreen({super.key});

  @override
  ConsumerState<OxplayerLoginScreen> createState() => _OxplayerLoginScreenState();
}

class _OxplayerLoginScreenState extends ConsumerState<OxplayerLoginScreen> {
  bool _bootstrapping = true;
  String? _bootstrapError;
  bool _manualCode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    setState(() {
      _bootstrapping = true;
      _bootstrapError = null;
    });

    await OxplayerDotenv.ensureLoaded();
    final media = OxplayerEnv.effectiveMediaServerUrl;
    if (media == null) {
      setState(() {
        _bootstrapping = false;
        _bootstrapError =
            'Set OXPLAYER_API_BASE_URL in assets/env/default.env (e.g. http://192.168.1.10:3004).';
      });
      return;
    }

    FladderConfig.baseUrl = media;

    try {
      await ref.read(authProvider.notifier).initModel();
    } catch (e) {
      if (mounted) {
        setState(() {
          _bootstrapping = false;
          _bootstrapError = '$e';
        });
      }
      return;
    }

    if (!mounted) return;
    final err = ref.read(authProvider).errorMessage;
    if (err != null) {
      setState(() {
        _bootstrapping = false;
        _bootstrapError = err;
      });
      return;
    }

    setState(() => _bootstrapping = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: _bootstrapping
                  ? const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        OxplayerLoginLogo(),
                        SizedBox(height: 24),
                        CircularProgressIndicator(),
                      ],
                    )
                  : _bootstrapError != null
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const OxplayerLoginLogo(),
                            const SizedBox(height: 16),
                            Text(
                              _bootstrapError!,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Theme.of(context).colorScheme.error),
                            ),
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: _bootstrap,
                              child: const Text('Retry'),
                            ),
                          ],
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const OxplayerLoginLogo(),
                            const SizedBox(height: 24),
                            if (_manualCode)
                              OxplayerClaimCodeLoginPanel(
                                onSuccess: () => loggedInGoToHome(context, ref),
                                onBack: () => setState(() => _manualCode = false),
                              )
                            else
                              OxplayerTelegramLoginPanel(
                                onSuccess: () => loggedInGoToHome(context, ref),
                                onManualCode: () => setState(() => _manualCode = true),
                              ),
                          ],
                        ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
