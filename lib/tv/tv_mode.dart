import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Presentation only. Rule versions, storage and playback stay upstream-owned.
class TvMode {
  TvMode._();

  static bool enabled = const bool.fromEnvironment('KAZUMI_TV');
  static const channel = MethodChannel('kazumi/tv');

  static Future<void> initialize() async {
    if (!enabled && Platform.isAndroid) {
      try {
        enabled = await channel.invokeMethod<bool>('isTv') ?? false;
      } on PlatformException {
        enabled = false;
      } on MissingPluginException {
        enabled = false;
      }
    }
    if (!enabled) return;
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    if (Platform.isAndroid) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }
}
