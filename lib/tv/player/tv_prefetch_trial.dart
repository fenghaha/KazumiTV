import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

/// Profile-only A/B switch. No arbitrary mpv commands, URLs or persisted state.
abstract final class TvPrefetchTrial {
  static bool _registered = false;
  static Player? Function()? _currentPlayer;
  static Object? _owner;

  static void attach(Object owner, Player? Function() currentPlayer) {
    if (!kProfileMode) return;
    _owner = owner;
    _currentPlayer = currentPlayer;
    if (_registered) return;
    _registered = true;
    developer.registerExtension('ext.kazumi.tv.prefetchTrial', (_, parameters) async {
      final player = _currentPlayer?.call();
      if (player == null) {
        return developer.ServiceExtensionResponse.error(-32000, 'No active player');
      }
      final seconds = parameters['seconds'];
      if (seconds != null && seconds != '60' && seconds != '36000') {
        return developer.ServiceExtensionResponse.error(-32602, 'Expected 60 or 36000 seconds');
      }
      try {
        final native = player.platform as NativePlayer;
        if (seconds != null) await native.setProperty('cache-secs', seconds);
        final values = <String, String>{};
        for (final property in [
          'time-pos', 'duration', 'pause', 'cache-secs',
          'demuxer-cache-duration', 'paused-for-cache',
          'decoder-frame-drop-count', 'avsync',
        ]) {
          if (!identical(player, _currentPlayer?.call())) {
            return developer.ServiceExtensionResponse.error(-32000, 'Player changed');
          }
          values[property] = await native.getProperty(property);
        }
        return developer.ServiceExtensionResponse.result(jsonEncode(values));
      } catch (_) {
        return developer.ServiceExtensionResponse.error(-32000, 'Player unavailable');
      }
    });
  }

  static void detach(Object owner) {
    if (!kProfileMode || !identical(_owner, owner)) return;
    _owner = null;
    _currentPlayer = null;
  }
}
