import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/credentials_model.dart';
import 'package:fladder/providers/arguments_provider.dart';
import 'package:fladder/util/application_info.dart';
import 'package:fladder/util/string_extensions.dart';

/// Shared by [WidgetRef.read] and [Ref.read] — avoids invalid `ref as Ref` casts.
typedef OxplayerRead = T Function<T>(ProviderListenable<T> provider);

Map<String, String> oxplayerMediaBrowserHeaders(OxplayerRead read, CredentialsModel credentials) {
  final application = read(applicationInfoProvider);
  final leanbackMode = read(argumentsStateProvider).leanBackMode;
  final os = switch (application.platform) {
    TargetPlatform.android => kIsWeb
        ? "${application.platform.name.capitalize()} Web"
        : (leanbackMode ? "${application.platform.name.capitalize()} TV" : application.platform.name.capitalize()),
    _ => !kIsWeb ? application.platform.name.capitalize() : "${application.platform.name.capitalize()} Web",
  };
  final versionLabel = application.buildNumber.isNotEmpty
      ? '${application.version}+${application.buildNumber}'
      : application.version;
  return {
    'authorization':
        'MediaBrowser Token="${credentials.token}", Client="${application.name}", Device="$os", DeviceId="${credentials.deviceId}", Version="$versionLabel"',
  };
}
