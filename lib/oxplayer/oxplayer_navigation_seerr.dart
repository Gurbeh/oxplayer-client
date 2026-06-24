import 'package:flutter/widgets.dart';

import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/screens/home_screen.dart';

/// Opens the Discover (Seerr) tab when OX Seerr proxy is enabled for this session.
void oxplayerNavigateToSeerr(BuildContext context) {
  if (!OxplayerConfig.isEnabled) return;
  HomeTabs.seerr.navigate(context);
}
