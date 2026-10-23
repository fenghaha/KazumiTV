import 'dart:async';

import 'package:kazumi/tv/input/remote_input_service.dart';

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
    unawaited(
      RemoteInputService.instance.ensureStarted().then<void>(
        (_) {},
        onError: (Object _) {},
      ),
    );
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    if (Platform.isAndroid) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      // The native activity reapplies its stored system-bar state when an IME
      // dialog returns window focus. Keep that state consistent with TV mode.
      try {
        await const MethodChannel('com.predidit.kazumi/intent')
            .invokeMethod<void>('setSystemBarsHidden', true);
      } on PlatformException {
        // SystemChrome remains the fallback for older native shells.
      } on MissingPluginException {
        // No native activity in widget tests.
      }
    }
  }
}
